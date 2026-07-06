#!/usr/bin/env bash

json_quote() {
  local value
  value="${1-}"
  require_command python3
  python3 -c 'import json, sys; print(json.dumps(sys.argv[1]))' "$value"
}

shell_quote() {
  local value
  value="${1-}"
  printf '%q' "$value"
}
