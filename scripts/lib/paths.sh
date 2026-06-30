#!/usr/bin/env bash
# lib/paths.sh - local Direxio service directory helpers.

direxio_home() {
  printf '%s\n' "${DIREXIO_HOME:-$HOME/.direxio}"
}

direxio_service_id() {
  local raw=${1:-} host
  host=${raw#http://}
  host=${host#https://}
  host=${host%%/*}
  case "$host" in
    *:*) host="${host%%:*}-${host#*:}" ;;
  esac
  printf '%s\n' "$host" | tr '[:upper:]' '[:lower:]' | sed -E 's/:/-/g; s/[^a-z0-9._-]+/-/g; s/^-+//; s/-+$//; s/^$/direxio-service/'
}

direxio_service_dir() {
  local service_id
  service_id=$(direxio_service_id "$1")
  printf '%s/nodes/%s\n' "$(direxio_home)" "$service_id"
}

direxio_default_workdir() {
  if [ -n "${DIREXIO_WORKDIR:-}" ]; then
    printf '%s\n' "$DIREXIO_WORKDIR"
  elif [ -n "${DOMAIN:-}" ]; then
    direxio_service_dir "$DOMAIN"
  else
    printf '%s/nodes\n' "$(direxio_home)"
  fi
}
