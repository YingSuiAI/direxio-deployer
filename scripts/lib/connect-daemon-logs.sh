# connect-daemon-logs.sh - shared direxio-connect daemon log classification.

connect_recent_daemon_logs() {
  awk '
    /config loaded|direxio-connect is running|acquired instance lock/ {
      buffer = ""
    }
    {
      buffer = buffer $0 "\n"
    }
    END {
      printf "%s", buffer
    }
  ' <<EOF
$1
EOF
}

connect_daemon_agent_error_from_text() {
  connect_recent_daemon_logs "$1" \
    | grep -Eio 'ACP_SESSION_INIT_FAILED|ACP metadata is missing|Recreate this ACP session|failed to create agent|CLI not found in PATH|Authentication required|agent login|Workspace Trust Required' \
    | head -n 1 || true
}

connect_daemon_agent_error_from_logs() {
  local binary=$1 service_name=$2 logs
  logs=$("$binary" daemon logs --service-name "$service_name" -n "${DIREXIO_CONNECT_LOG_TAIL_LINES:-120}" 2>/dev/null || true)
  connect_daemon_agent_error_from_text "$logs"
}
