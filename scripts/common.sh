#!/usr/bin/env bash

set -euo pipefail

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

unsupported_placeholder() {
  local script_name command_name
  script_name="${1:?script name required}"
  command_name="${2:-}"

  if [ -n "$command_name" ]; then
    die "$script_name $command_name is not implemented in this repository step"
  fi

  die "$script_name is a placeholder; lifecycle commands are not implemented yet"
}
