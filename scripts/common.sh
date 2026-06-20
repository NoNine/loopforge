#!/usr/bin/env bash

set -euo pipefail

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

require_runtime_account_home() {
  local account group expected_home label passwd_entry account_home primary_gid group_gid
  account="${1:?account required}"
  group="${2:?group required}"
  expected_home="${3:?expected home required}"
  label="${4:?label required}"

  passwd_entry="$(getent passwd "$account" 2>/dev/null || true)"
  [ -n "$passwd_entry" ] || die "Missing $label runtime account: $account"
  getent group "$group" >/dev/null 2>&1 ||
    die "Missing $label runtime group: $group"

  account_home="$(printf '%s\n' "$passwd_entry" | awk -F: '{print $6}')"
  [ "$account_home" = "$expected_home" ] ||
    die "$label runtime account $account passwd HOME must be $expected_home, got $account_home"

  primary_gid="$(printf '%s\n' "$passwd_entry" | awk -F: '{print $4}')"
  group_gid="$(getent group "$group" | awk -F: '{print $3}')"
  [ "$primary_gid" = "$group_gid" ] ||
    die "$label runtime account $account primary group must be $group"
}

require_product_home_ownership() {
  local path account group label file_type owner actual_group
  path="${1:?path required}"
  account="${2:?account required}"
  group="${3:?group required}"
  label="${4:?label required}"

  file_type="$(stat -c '%F' "$path" 2>/dev/null || true)"
  [ "$file_type" = "directory" ] || die "$label product home does not exist or is not a directory: $path"
  owner="$(stat -c '%U' "$path")"
  actual_group="$(stat -c '%G' "$path")"
  [ "$owner:$actual_group" = "$account:$group" ] ||
    die "$label product home $path owner/group must be $account:$group, got $owner:$actual_group"
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
