#!/usr/bin/env bash

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

print_command_summary() {
  local command_name role message
  command_name="${1:?command required}"
  role="${2-}"
  message="${3:?message required}"
  if [ -n "$role" ]; then
    printf '%s[%s]: %s\n' "$command_name" "$role" "$message"
  else
    printf '%s: %s\n' "$command_name" "$message"
  fi
}

print_command_failure() {
  local command_name role message log evidence
  command_name="${1:?command required}"
  role="${2-}"
  message="${3:?message required}"
  log="${4-}"
  evidence="${5-}"
  print_command_summary "$command_name" "$role" "$message"
  [ -n "$log" ] && printf 'log=%s\n' "$log"
  [ -n "$evidence" ] && printf 'evidence=%s\n' "$evidence"
}

timestamp_utc() {
  date -u +%Y%m%dT%H%M%SZ
}

iso_timestamp_utc() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

require_readable_file() {
  local name file
  name="${1:?name required}"
  file="${2:?file required}"
  [ -f "$file" ] || die "$name does not exist: $file"
  [ -r "$file" ] || die "$name is not readable: $file"
}
