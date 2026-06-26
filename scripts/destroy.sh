#!/usr/bin/env bash
# destroy.sh - remove AWS resources recorded by deployment state.
#
# Source:
#   1. $P2P_WORKDIR/state.json written by orchestrate.sh; by default
#      DOMAIN=__DOMAIN__ maps to ~/.direxio/nodes/<service_id>/state.json.
#   2. explicit argument: bash destroy.sh /path/to/state.json
#
# Order: terminate instance -> release EIP -> delete security group -> delete key pair
# -> remove the corresponding local service directory.
# Each cloud step is tolerant of already-removed resources.
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC1090
source "$HERE/lib/paths.sh"
P2P_WORKDIR=$(direxio_default_workdir)

log() { echo -e "\033[33m[destroy]\033[0m $*"; }

# Resolve source and load INSTANCE_ID/EIP_ID/SG_ID/KEY_NAME/KEY_FILE/REGION.
SRC=${1:-}
if [ -z "$SRC" ]; then
  if   [ -f "$P2P_WORKDIR/state.json" ]; then SRC="$P2P_WORKDIR/state.json"
  else echo "state.json not found; set DOMAIN=<service domain> or P2P_WORKDIR=<service dir> to destroy a specific deployment."; exit 1
  fi
fi
[ -f "$SRC" ] || { echo "$SRC not found."; exit 1; }
P2P_ROOT=$(cd "${DIREXIO_HOME:-$HOME/.direxio}" 2>/dev/null && pwd -P || printf '%s' "${DIREXIO_HOME:-$HOME/.direxio}")

command -v jq >/dev/null 2>&1 || { echo "jq is required to parse state.json."; exit 1; }
REGION=$(jq -r '.region // empty' "$SRC")
INSTANCE_ID=$(jq -r '.resources.instance_id // empty' "$SRC")
EIP_ID=$(jq -r '.resources.eip_id // empty' "$SRC")
SG_ID=$(jq -r '.resources.sg_id // empty' "$SRC")
KEY_NAME=$(jq -r '.resources.key_name // empty' "$SRC")
KEY_FILE=$(jq -r '.resources.key_file // empty' "$SRC")
DOMAIN_MODE=$(jq -r '.domain_mode // empty' "$SRC")
DOMAIN=$(jq -r '.domain // empty' "$SRC")
AS_URL=$(jq -r '.as_url // empty' "$SRC")
PUBLIC_IP=$(jq -r '.resources.public_ip // empty' "$SRC")
CC_CONNECT_CONFIG=$(jq -r '.cc_connect_config // empty' "$SRC")
CC_CONNECT_BINARY=$(jq -r '.cc_connect_binary // empty' "$SRC")
CC_CONNECT_RUNTIME_DIR=$(jq -r '.cc_connect_runtime_dir // empty' "$SRC")
AGENT_SERVICE_DIR=$(jq -r '.agent_service_dir // empty' "$SRC")

export NO_PROXY="*"; export no_proxy="*"
unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy 2>/dev/null || true
[ -n "${REGION:-${AWS_DEFAULT_REGION:-}}" ] || {
  echo "Region is missing. Add .region to state.json or set AWS_DEFAULT_REGION, then retry."
  exit 1
}
export AWS_DEFAULT_REGION=${REGION:-${AWS_DEFAULT_REGION:-}}

log "source = $SRC (region=$AWS_DEFAULT_REGION)"

if ! aws sts get-caller-identity >/dev/null 2>&1; then
  echo "AWS credentials are required before destroy can remove cloud resources or local state."
  exit 1
fi

find_route53_zone() {
  local domain=$1 best_id="" best_name="" best_len=0 id name clean len
  while IFS=$'\t' read -r id name; do
    id=${id%$'\r'}
    name=${name%$'\r'}
    clean=${name%.}
    case "$domain" in
      "$clean"|*."$clean")
        len=${#clean}
        if [ "$len" -gt "$best_len" ]; then
          best_id=${id#/hostedzone/}
          best_name=$clean
          best_len=$len
        fi
        ;;
    esac
  done < <(aws route53 list-hosted-zones --output json 2>/dev/null | jq -r '.HostedZones[] | [.Id, .Name] | @tsv')
  [ -n "$best_id" ] && printf '%s\t%s\n' "$best_id" "$best_name"
}

delete_route53_record() {
  local domain=$1 public_ip=$2 zone zone_id zone_name change_file
  [ -n "$domain" ] && [ -n "$public_ip" ] || return 0
  zone=$(find_route53_zone "$domain")
  zone_id=$(printf '%s' "$zone" | cut -f1)
  zone_name=$(printf '%s' "$zone" | cut -f2)
  if [ -z "$zone_id" ]; then
    log "Route53 hosted zone not found for $domain; leaving DNS record untouched"
    return 0
  fi

  log "deleting Route53 A record $domain -> $public_ip (zone=$zone_name) ..."
  change_file=$(mktemp)
  cat > "$change_file" <<EOF
{
  "Comment": "p2p-matrix destroy",
  "Changes": [
    {
      "Action": "DELETE",
      "ResourceRecordSet": {
        "Name": "$domain.",
        "Type": "A",
        "TTL": 60,
        "ResourceRecords": [{ "Value": "$public_ip" }]
      }
    }
  ]
}
EOF
  local change_file_aws="$change_file"
  if command -v cygpath >/dev/null 2>&1; then
    change_file_aws=$(cygpath -w "$change_file")
  fi
  aws route53 change-resource-record-sets \
    --hosted-zone-id "$zone_id" \
    --change-batch "file://$change_file_aws" >/dev/null 2>&1 \
    || log "  (Route53 A record may already be absent or changed; check DNS manually)"
  rm -f "$change_file"
}

normalize_local_path() {
  local path=$1 drive rest
  path=$(printf '%s' "$path" | sed 's#\\#/#g')
  case "$path" in
    /mnt/[A-Za-z]/*)
      drive=${path#/mnt/}
      drive=${drive%%/*}
      rest=${path#/mnt/$drive/}
      printf '%s:/%s\n' "$(printf '%s' "$drive" | tr '[:lower:]' '[:upper:]')" "$rest"
      return 0
      ;;
    /cygdrive/[A-Za-z]/*)
      drive=${path#/cygdrive/}
      drive=${drive%%/*}
      rest=${path#/cygdrive/$drive/}
      printf '%s:/%s\n' "$(printf '%s' "$drive" | tr '[:lower:]' '[:upper:]')" "$rest"
      return 0
      ;;
    /[A-Za-z]/*)
      drive=${path#/}
      drive=${drive%%/*}
      rest=${path#/$drive/}
      printf '%s:/%s\n' "$(printf '%s' "$drive" | tr '[:lower:]' '[:upper:]')" "$rest"
      return 0
      ;;
  esac
  while [ "${#path}" -gt 1 ] && [ "${path%/}" != "$path" ]; do
    case "$path" in [A-Za-z]:/) break ;; esac
    path=${path%/}
  done
  printf '%s\n' "$path"
}

local_dirname() {
  local path
  path=$(normalize_local_path "$1")
  case "$path" in
    */*) printf '%s\n' "${path%/*}" ;;
    *) printf '.\n' ;;
  esac
}

paths_equal() {
  local left right
  left=$(normalize_local_path "$1")
  right=$(normalize_local_path "$2")
  case "$left:$right" in
    [A-Za-z]:/*:[A-Za-z]:/*)
      [ "$(printf '%s' "$left" | tr '[:upper:]' '[:lower:]')" = "$(printf '%s' "$right" | tr '[:upper:]' '[:lower:]')" ]
      ;;
    *)
      [ "$left" = "$right" ]
      ;;
  esac
}

current_service_dir() {
  local recorded=$1 asurl=$2 domain=$3 config=${4:-}
  if [ -n "$recorded" ]; then
    printf '%s\n' "$recorded"
    return 0
  fi
  if [ -n "$asurl" ] || [ -n "$domain" ]; then
    direxio_service_dir "${asurl:-$domain}"
    return 0
  fi
  if [ -n "$config" ]; then
    local_dirname "$(local_dirname "$config")"
  fi
}

cc_connect_stop_binary() {
  local binary=$1 runtime_dir=$2 candidate
  if [ -n "$runtime_dir" ]; then
    candidate="$runtime_dir/bin/direxio-connect"
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
    candidate="$runtime_dir/bin/direxio-connect.exe"
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  fi
  if [ -n "$binary" ]; then
    printf '%s\n' "$binary"
    return 0
  fi
  printf 'direxio-connect\n'
}

cc_connect_target_work_dir() {
  local config=$1 runtime_dir=$2 service_dir=$3
  if [ -n "$config" ]; then
    local_dirname "$config"
    return 0
  fi
  if [ -n "$runtime_dir" ]; then
    normalize_local_path "$runtime_dir"
    return 0
  fi
  if [ -n "$service_dir" ]; then
    normalize_local_path "$service_dir/cc-connect"
  fi
}

cc_connect_status_work_dir() {
  local binary=$1 out
  out=$("$binary" daemon status 2>/dev/null) || return 1
  printf '%s\n' "$out" | sed -nE 's/^[[:space:]]*WorkDir:[[:space:]]*//p' | head -n 1
}

stop_current_cc_connect_daemon() {
  local config=$1 binary=$2 runtime_dir=$3 service_dir=$4 target_work_dir running_work_dir stop_binary
  target_work_dir=$(cc_connect_target_work_dir "$config" "$runtime_dir" "$service_dir")
  if [ -z "$target_work_dir" ]; then
    log "cc-connect service directory not recorded; skipping local daemon stop"
    return 0
  fi

  stop_binary=$(cc_connect_stop_binary "$binary" "$runtime_dir")
  case "$stop_binary" in
    */*|[A-Za-z]:/*|[A-Za-z]:\\*) ;;
    *)
      if ! command -v "$stop_binary" >/dev/null 2>&1; then
        log "cc-connect binary not found on PATH; skipping local daemon stop"
        return 0
      fi
      ;;
  esac

  running_work_dir=$(cc_connect_status_work_dir "$stop_binary")
  if [ -z "$running_work_dir" ]; then
    log "cc-connect daemon status has no WorkDir; skipping local daemon stop"
    return 0
  fi

  if ! paths_equal "$target_work_dir" "$running_work_dir"; then
    log "cc-connect daemon belongs to another service; leaving daemon running"
    return 0
  fi

  log "stopping cc-connect daemon for current service ..."
  if "$stop_binary" daemon stop >/dev/null 2>&1; then
    log "cc-connect daemon stopped"
  else
    log "cc-connect daemon stop failed or service was not installed; continuing destroy"
  fi
}

cleanup_local_service_dir() {
  local service_dir=$1 root=$2 nodes_root src_real nodes_real src_norm nodes_norm name

  if [ "${P2P_KEEP_WORKDIR:-0}" = "1" ]; then
    log "keeping local service dir because P2P_KEEP_WORKDIR=1: $service_dir"
    return 0
  fi

  [ -n "$service_dir" ] && [ -d "$service_dir" ] || return 0
  [ -n "$root" ] || return 0

  nodes_root="$root/nodes"
  [ -d "$nodes_root" ] || {
    log "local service root not found; leaving $service_dir untouched"
    return 0
  }
  src_real=$(cd "$service_dir" 2>/dev/null && pwd -P) || return 0
  nodes_real=$(cd "$nodes_root" 2>/dev/null && pwd -P) || return 0
  src_norm=$(normalize_local_path "$src_real")
  nodes_norm=$(normalize_local_path "$nodes_real")
  case "$src_norm" in
    "$nodes_norm"/*) ;;
    *)
      log "refusing to remove local service dir outside $nodes_norm: $service_dir"
      return 0
      ;;
  esac

  name=$(basename "$src_norm")
  case "$name" in
    ""|"."|".."|"nodes"|"cc-connect")
      log "refusing to remove unexpected local service dir: $service_dir"
      return 0
      ;;
  esac

  log "removing local service dir $src_real ..."
  rm -rf -- "$src_real"
}

# 0. Remove DNS record if ops created it through Route53 mode.
CURRENT_SERVICE_DIR=$(current_service_dir "$AGENT_SERVICE_DIR" "$AS_URL" "$DOMAIN" "$CC_CONNECT_CONFIG")
stop_current_cc_connect_daemon "$CC_CONNECT_CONFIG" "$CC_CONNECT_BINARY" "$CC_CONNECT_RUNTIME_DIR" "$CURRENT_SERVICE_DIR"

if [ "${DOMAIN_MODE:-}" = "route53" ]; then
  delete_route53_record "$DOMAIN" "$PUBLIC_IP"
fi

# 1. Terminate instance.
if [ -n "${INSTANCE_ID:-}" ]; then
  log "terminating instance $INSTANCE_ID ..."
  aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" >/dev/null 2>&1 || log "  (instance may already be gone)"
  aws ec2 wait instance-terminated --instance-ids "$INSTANCE_ID" 2>/dev/null || true
fi

# 2. Release Elastic IP.
if [ -n "${EIP_ID:-}" ]; then
  log "releasing Elastic IP $EIP_ID ..."
  aws ec2 release-address --allocation-id "$EIP_ID" 2>/dev/null || log "  (EIP may already be released)"
fi

# 3. Delete security group after instance/network interfaces detach.
if [ -n "${SG_ID:-}" ]; then
  log "deleting security group $SG_ID ..."
  for i in 1 2 3 4 5; do
    if aws ec2 delete-security-group --group-id "$SG_ID" 2>/dev/null; then break; fi
    sleep 6
    [ "$i" = 5 ] && log "  (security group delete failed; an ENI may still be attached, delete it manually later)"
  done
fi

# 4. Delete key pair and local private key.
if [ -n "${KEY_NAME:-}" ]; then
  log "deleting key pair $KEY_NAME ..."
  aws ec2 delete-key-pair --key-name "$KEY_NAME" 2>/dev/null || true
  [ -n "${KEY_FILE:-}" ] && [ -f "$KEY_FILE" ] && rm -f "$KEY_FILE"
fi

log "Done. Processed resources recorded in $SRC."
log "User-managed DNS and domain purchases are outside automatic destroy scope; handle them manually if needed."
cleanup_local_service_dir "$CURRENT_SERVICE_DIR" "$P2P_ROOT"
