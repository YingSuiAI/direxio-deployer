#!/usr/bin/env bash
# S5 INIT_TOKENS - fetch AS-written bootstrap credentials from the instance.
# Also verify owner.json so the client does not report Portal as undeployed.

run_phase() {
  phase_set S5_INIT_TOKENS in_progress "fetching tokens"
  local domain pubip keyfile
  domain=$(state_get domain)
  pubip=$(res_get public_ip)
  keyfile=$(res_get key_file)
  local out="$P2P_WORKDIR/outputs.json" raw
  raw=$(mktemp)
  trap 'rm -f "${raw:-}"; trap - RETURN' RETURN

  log "Fetching /opt/p2p/bootstrap.json ..."
  if ! poll_until "read bootstrap.json" "${TOKEN_POLL_INTERVAL:-10}" "${TOKEN_POLL_MAX:-12}" \
        _read_remote_bootstrap "$keyfile" "$pubip" "$raw"; then
    phase_set S5_INIT_TOKENS failed "failed to fetch bootstrap.json"
    warn "Could not read /opt/p2p/bootstrap.json. Check whether message-server wrote credentials:"
    warn "  ssh -i $keyfile ubuntu@$pubip 'sudo cat /opt/p2p/bootstrap.json 2>/dev/null; cd /opt/p2p; sudo docker compose logs message-server | tail -40'"
    return 1
  fi
  if ! _normalize_bootstrap_output "$domain" "$raw" "$out"; then
    phase_set S5_INIT_TOKENS failed "invalid bootstrap.json"
    fail "bootstrap.json could not be normalized."
  fi

  # Verify owner.json; missing file makes the client report Portal as undeployed.
  if _healthz_ok_ownerjson "$domain"; then
    log "owner.json 200 OK (Portal discovery healthy)"
  else
    warn "/.well-known/portal/owner.json did not return 200. The client may report Portal as undeployed."
    warn "  Check Caddy file_server and /opt/p2p/wellknown/owner.json generation."
  fi

  local password token access_token asurl agent_room_id
  if ! IFS=$'\t' read -r password token access_token < <(_extract_output_tokens "$out"); then
    phase_set S5_INIT_TOKENS failed "bootstrap.json missing password/access/agent credentials"
    fail "bootstrap.json does not contain password, access_token, and agent_token."
  fi
  asurl=$(jq -r --arg domain "$domain" '.as_url // ("https://" + $domain)' "$out")
  agent_room_id=$(jq -r '.agent_room_id // empty' "$out")
  if [ -z "$agent_room_id" ] || [[ "$agent_room_id" == \!agent:* ]]; then
    phase_set S5_INIT_TOKENS failed "bootstrap.json missing real agent_room_id"
    fail "bootstrap.json must contain a real Matrix agent_room_id; legacy !agent:<domain> ids are not supported."
  fi

  # Store tokens in state for S6. state.json is local-only and chmod 0600.
  state_set as_url "$asurl"
  state_set password "$password"
  state_set agent_token "$token"
  state_set access_token "$access_token"
  state_set agent_room_id "$agent_room_id"

  phase_set S5_INIT_TOKENS done "got password (len=${#password}) as_url=$asurl agent_room_id=$agent_room_id"
  ok "Tokens fetched from bootstrap.json."
  return 0
}

_extract_output_tokens() {
  local out=$1 password token access_token
  password=$(jq -r '.password // empty' "$out")
  token=$(jq -r '.agent_token // empty' "$out")
  access_token=$(jq -r '.access_token // empty' "$out")
  [ -n "$password" ] && [ -n "$token" ] && [ -n "$access_token" ] || return 1
  printf '%s\t%s\t%s\n' "$password" "$token" "$access_token"
}

_read_remote_bootstrap() {
  local keyfile=$1 pubip=$2 out=$3
  ssh -i "$keyfile" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 \
    ubuntu@"$pubip" "sudo test -s /opt/p2p/bootstrap.json && sudo cat /opt/p2p/bootstrap.json" > "$out" 2>/dev/null
}

_normalize_bootstrap_output() {
  local domain=$1 src=$2 out=$3
  local tmp
  tmp=$(mktemp)
  if ! jq --arg domain "$domain" --arg asurl "https://$domain" '
    . + {
      domain: (.domain // $domain),
      as_url: (.as_url // $asurl),
      p2p_url: (.p2p_url // $asurl),
      user_id: (.user_id // .owner_user_id // ""),
      bot_mxid: (.bot_mxid // .owner_user_id // .user_id // ("@owner:" + $domain)),
      access_token: (.access_token // ""),
      agent_token: (.agent_token // ""),
      agent_room_id: (.agent_room_id // "")
    }
  ' "$src" > "$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  mv "$tmp" "$out"
  chmod 600 "$out" 2>/dev/null || true
}

_healthz_ok_ownerjson() {
  local domain=$1 pubip args=()
  pubip=$(res_get public_ip)
  [ -n "$pubip" ] && args=(--resolve "$domain:443:$pubip")
  [ "$(curl -sk "${args[@]}" -o /dev/null -w '%{http_code}' "https://$domain/.well-known/portal/owner.json" 2>/dev/null)" = "200" ]
}
