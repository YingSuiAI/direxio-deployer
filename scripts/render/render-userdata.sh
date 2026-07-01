#!/usr/bin/env bash
# render-userdata.sh - render final cloud-init user-data.
#
# Bundle cloud-init deployment files (docker-compose.yml / Caddyfile /
# init-tokens.sh) into a tar.gz, inline it as one write_files entry, and unpack
# it to /var/direxio-message-server in runcmd. Comment-only lines are stripped at the end to keep
# AWS user-data below the 16384-byte limit. Replaces __DOMAIN__ /
# __ACME_EMAIL__ / __MESSAGE_SERVER_IMAGE__; the EC2 instance does not need to
# clone repos.
#
# Usage:
#   render-userdata.sh --domain <domain> --acme <email> --message-server-image <img> > user-data.yaml
set -euo pipefail

HERE=$(cd "$(dirname "$0")/.." && pwd)
CI="$HERE/cloud-init"
source "$HERE/lib/domain.sh"

DOMAIN=""; ACME=""; MESSAGE_SERVER_IMAGE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --domain) DOMAIN=$2; shift 2;;
    --acme) ACME=$2; shift 2;;
    --message-server-image) MESSAGE_SERVER_IMAGE=$2; shift 2;;
    --as-image) MESSAGE_SERVER_IMAGE=$2; shift 2;;
    *) echo "unknown arg: $1" >&2; exit 1;;
  esac
done
[ -n "$MESSAGE_SERVER_IMAGE" ] || { echo "--message-server-image required" >&2; exit 1; }
[ -n "$DOMAIN" ] || { echo "--domain required; production deployments require a real domain" >&2; exit 1; }
DOMAIN=$(domain_normalize "$DOMAIN")
[ "$DOMAIN" != "PLACEHOLDER" ] || { echo "PLACEHOLDER/sslip.io domains are not accepted in the production renderer" >&2; exit 1; }
domain_is_formal_name "$DOMAIN" || { echo "invalid production domain: $DOMAIN" >&2; exit 1; }

# Single-line base64 compatible with GNU/Linux and macOS/BSD base64.
b64() { base64 | tr -d '\n'; }
sed_replacement_escape() { printf '%s' "$1" | sed 's/[\\&#]/\\&/g'; }

# Build a deterministic tar.gz bundle with fixed permissions and no extra attrs.
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cp "$CI/docker-compose.yml" "$WORK/docker-compose.yml"
cp "$CI/Caddyfile"          "$WORK/Caddyfile"
tr -d '\r' < "$CI/init-tokens.sh" > "$WORK/init-tokens.sh"
chmod 0644 "$WORK/docker-compose.yml" "$WORK/Caddyfile"
chmod 0755 "$WORK/init-tokens.sh"
find "$WORK" -name '._*' -delete
# -C creates a flat archive. Explicit gzip avoids macOS tar stdout quirks.
# COPYFILE_DISABLE=1 avoids AppleDouble ._* extended-attribute files.
BUNDLE_B64=$(COPYFILE_DISABLE=1 tar -C "$WORK" -cf - docker-compose.yml Caddyfile init-tokens.sh | gzip -n | b64)

# Generate user-data: append the bundle entry to write_files and unpack first in runcmd.
# Avoid passing multiline strings via awk -v; macOS awk rejects newline in string.
EXTRA_WF=$(mktemp); trap 'rm -rf "$WORK" "$EXTRA_WF"' EXIT
cat > "$EXTRA_WF" <<EOF
  - path: /var/direxio-message-server/bundle.tar.gz
    permissions: '0644'
    encoding: b64
    content: $BUNDLE_B64
EOF

# Insert unpack as the first runcmd step before Docker install / compose up.
UNPACK='  - mkdir -p /var/direxio-message-server && tar -xzf /var/direxio-message-server/bundle.tar.gz -C /var/direxio-message-server && chmod 0755 /var/direxio-message-server/init-tokens.sh'

strip_userdata_comments() {
  awk '
    NR == 1 && $0 == "#cloud-config" { print; next }
    /^[[:space:]]*#/ { next }
    { print }
  '
}

awk -v wf="$EXTRA_WF" -v unpack="$UNPACK" '
  # Insert bundle entry before runcmd.
  /^runcmd:/ && !wfdone {
    while ((getline line < wf) > 0) print line
    close(wf)
    print
    print unpack
    wfdone=1
    next
  }
  { print }
' "$CI/user-data.yaml" \
| sed "s#__DOMAIN__#$(sed_replacement_escape "$DOMAIN")#g; s#__ACME_EMAIL__#$(sed_replacement_escape "$ACME")#g; s#__MESSAGE_SERVER_IMAGE__#$(sed_replacement_escape "$MESSAGE_SERVER_IMAGE")#g" \
| strip_userdata_comments
