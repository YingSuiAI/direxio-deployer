#!/usr/bin/env bash

# shellcheck disable=SC1090
source "$ROOT/scripts/lib/json.sh"

json_test_check() {
  json_check "$@" >/dev/null
}
