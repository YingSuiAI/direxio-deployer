#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck disable=SC1090
source "$ROOT/tests/lib/json_test.sh"
tmp=$(mktemp -d "$ROOT/.tmp-mcp-tools.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

export HOME="$tmp/home"
mkdir -p "$HOME"

fakebin="$tmp/bin"
mkdir -p "$fakebin"

windows_path() {
  local path=$1 drive rest
  case "$path" in
    /mnt/[A-Za-z]/*)
      drive=${path#/mnt/}
      drive=${drive%%/*}
      rest=${path#/mnt/$drive/}
      printf '%s:\\%s\n' "$(printf '%s' "$drive" | tr '[:lower:]' '[:upper:]')" "$(printf '%s' "$rest" | sed 's#/#\\#g')"
      ;;
    /[A-Za-z]/*)
      drive=${path#/}
      drive=${drive%%/*}
      rest=${path#/$drive/}
      printf '%s:\\%s\n' "$(printf '%s' "$drive" | tr '[:lower:]' '[:upper:]')" "$(printf '%s' "$rest" | sed 's#/#\\#g')"
      ;;
    *) printf '%s\n' "$path" ;;
  esac
}

cat > "$fakebin/direxio-mcp" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [ "${DIREXIO_CREDENTIALS_FILE:-}" != "${EXPECTED_CREDENTIALS_FILE:-}" ]; then
  echo "wrong DIREXIO_CREDENTIALS_FILE" >&2
  exit 1
fi

printf '%s\n' '{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2024-11-05","capabilities":{"tools":{}},"serverInfo":{"name":"fake-direxio-mcp","version":"0.0.0"}}}'
printf '%s\n' '{"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"search_rooms","description":"Search rooms"},{"name":"send_message","description":"Send message"},{"name":"list_messages","description":"List messages"}]}}'
EOF
chmod 700 "$fakebin/direxio-mcp"

cat > "$tmp/fake-mcp.ps1" <<'EOF'
if ($env:DIREXIO_CREDENTIALS_FILE -ne $env:EXPECTED_CREDENTIALS_FILE) {
  [Console]::Error.WriteLine("wrong DIREXIO_CREDENTIALS_FILE")
  exit 1
}

[Console]::Out.WriteLine('{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2024-11-05","capabilities":{"tools":{}},"serverInfo":{"name":"fake-direxio-mcp","version":"0.0.0"}}}')
[Console]::Out.WriteLine('{"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"search_rooms","description":"Search rooms"},{"name":"send_message","description":"Send message"},{"name":"list_messages","description":"List messages"}]}}')
EOF

mcp_command=direxio-mcp
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) use_windows_mcp=1 ;;
  *) use_windows_mcp=0 ;;
esac
if { [ "$use_windows_mcp" = "1" ] || ! command -v node >/dev/null 2>&1; } && command -v node.exe >/dev/null 2>&1; then
  fake_mcp_ps1=$(windows_path "$tmp/fake-mcp.ps1")
  mcp_command="powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"$fake_mcp_ps1\""
fi

service_dir="$HOME/.direxio/nodes/mcp-tools.example.test"
mkdir -p "$service_dir"
credentials="$service_dir/credentials.json"
: > "$credentials"
expected_credentials="$credentials"
if command -v cygpath >/dev/null 2>&1; then
  expected_credentials=$(cygpath -m "$expected_credentials")
fi
state="$service_dir/state.json"
json_build object \
  run_id=mcp-tools-test \
  region=ap-northeast-1 \
  domain_mode=user \
  domain=mcp-tools.example.test \
  agent_service_id=mcp-tools.example.test \
  "agent_service_dir=$service_dir" \
  "agent_credentials_file=$credentials" \
  "mcp_credentials_file=$credentials" \
  "mcp_command=$mcp_command" \
  phase=S7_VERIFY_E2E \
  'phases={"S0_PREREQ_AWS":{"status":"done"},"S1_PREFLIGHT":{"status":"done"},"S2_DOMAIN":{"status":"done"},"S3_PROVISION":{"status":"done"},"S4_BOOTSTRAP_STACK":{"status":"done"},"S5_INIT_TOKENS":{"status":"done"},"S6_WIRE_LOCAL":{"status":"done"},"S7_VERIFY_E2E":{"status":"done"}}' \
  'resources={}' > "$state"

verify_output=$(P2P_WORKDIR="$service_dir" PATH="$fakebin:$PATH" EXPECTED_CREDENTIALS_FILE="$expected_credentials" bash "$ROOT/scripts/orchestrate.sh" verify mcp_tools)
printf '%s\n' "$verify_output" | grep -q 'verified runtime check: mcp_tools'

json_test_check "$state" "data.runtime_checks.mcp_tools.status === 'passed' && data.runtime_checks.mcp_tools.tool_count === 3 && data.runtime_checks.mcp_tools.tools.includes('search_rooms') && data.runtime_checks.mcp_tools.tools.includes('send_message') && data.runtime_checks.mcp_tools.tools.includes('list_messages') && !data.user_confirmations?.agent_mcp_runtime"

report_output=$(P2P_WORKDIR="$service_dir" bash "$ROOT/scripts/orchestrate.sh" report new_deploy)
report_path=$(printf '%s\n' "$report_output" | sed -nE 's/^operation report: //p' | tail -n 1)
json_test_check "$report_path" "data.runtime_checks.mcp_tools.status === 'passed' && data.runtime_checks.mcp_tools.tool_count === 3 && data.gates.user_confirmation.agent_mcp_runtime === 'pending_runtime_confirmation'"

echo "mcp tools runtime check ok"
