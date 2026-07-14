#!/usr/bin/env bash

set -euo pipefail

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

validate_runtime_identity_name() {
  local kind value label
  kind="${1:?identity kind required}"
  value="${2:?identity name required}"
  label="${3:?label required}"

  case "$value" in
    *[$'\001'-$'\037'$'\177']*|""|*[!a-z_0-9-]*)
      die "$label runtime $kind must use lowercase letters, digits, underscore, or dash"
      ;;
  esac
  case "$value" in
    -*|[0-9]*|root|daemon|bin|sys|sync|games|man|lp|mail|news|uucp|proxy|www-data|backup|list|irc|_apt|nobody|systemd-*)
      die "$label runtime $kind is not allowed: $value"
      ;;
  esac
  [ "${#value}" -le 32 ] || die "$label runtime $kind must be 32 characters or fewer"
}

validate_runtime_identity_number() {
  local kind value label
  kind="${1:?identity kind required}"
  value="${2:?numeric identity required}"
  label="${3:?label required}"

  case "$value" in
    ""|*[!0-9]*) die "$label runtime $kind must be a positive decimal integer" ;;
  esac
  [ "$value" -gt 0 ] || die "$label runtime $kind must be greater than zero"
  [ "$value" -le 4294967294 ] || die "$label runtime $kind exceeds the supported Unix identity range"
}

validate_runtime_identity_inputs() {
  local account group uid gid label
  account="${1:?account required}"
  group="${2:?group required}"
  uid="${3:?uid required}"
  gid="${4:?gid required}"
  label="${5:?label required}"

  validate_runtime_identity_name account "$account" "$label"
  validate_runtime_identity_name group "$group" "$label"
  validate_runtime_identity_number UID "$uid" "$label"
  validate_runtime_identity_number GID "$gid" "$label"
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

classify_runtime_identity_state() {
  local account group uid gid home label passwd_entry group_entry home_type
  local uid_entry gid_entry
  local account_present group_present home_present
  account="${1:?account required}"
  group="${2:?group required}"
  uid="${3:?uid required}"
  gid="${4:?gid required}"
  home="${5:?home required}"
  label="${6:?label required}"

  validate_runtime_identity_inputs "$account" "$group" "$uid" "$gid" "$label"
  passwd_entry="$(getent passwd "$account" 2>/dev/null || true)"
  group_entry="$(getent group "$group" 2>/dev/null || true)"
  account_present=0
  group_present=0
  home_present=0
  [ -z "$passwd_entry" ] || account_present=1
  [ -z "$group_entry" ] || group_present=1
  home_type="$(stat -c '%F' "$home" 2>/dev/null || true)"
  [ -z "$home_type" ] || home_present=1

  if [ "$account_present" -eq 0 ] && [ "$group_present" -eq 0 ] && [ "$home_present" -eq 0 ]; then
    uid_entry="$(getent passwd "$uid" 2>/dev/null || true)"
    gid_entry="$(getent group "$gid" 2>/dev/null || true)"
    if [ -n "$uid_entry" ]; then
      die "$label runtime UID $uid is already assigned to another account"
    fi
    if [ -n "$gid_entry" ]; then
      die "$label runtime GID $gid is already assigned to another group"
    fi
    printf 'absent\n'
    return 0
  fi

  if [ "$account_present" -eq 1 ] && [ "$group_present" -eq 1 ] && [ "$home_present" -eq 1 ]; then
    [ "$home_type" = "directory" ] || die "$label product home exists but is not a directory: $home"
    [ "$(printf '%s\n' "$passwd_entry" | awk -F: '{print $3}')" = "$uid" ] ||
      die "$label runtime account $account UID must be $uid"
    [ "$(printf '%s\n' "$group_entry" | awk -F: '{print $3}')" = "$gid" ] ||
      die "$label runtime group $group GID must be $gid"
    require_runtime_account_home "$account" "$group" "$home" "$label"
    require_product_home_ownership "$home" "$account" "$group" "$label"
    printf 'ready\n'
    return 0
  fi

  die "$label runtime identity state is partial; account, group, and product home must be all absent or all present"
}

realize_runtime_identity() {
  local account group uid gid home label state command
  account="${1:?account required}"
  group="${2:?group required}"
  uid="${3:?uid required}"
  gid="${4:?gid required}"
  home="${5:?home required}"
  label="${6:?label required}"
  state="$(classify_runtime_identity_state "$account" "$group" "$uid" "$gid" "$home" "$label")"

  if [ "$state" = "ready" ]; then
    printf 'reused\n'
    return 0
  fi

  require_command groupadd
  require_command useradd
  require_command install
  command="groupadd --gid $(shell_quote "$gid") $(shell_quote "$group")"
  command="$command && useradd --uid $(shell_quote "$uid") --gid $(shell_quote "$gid") --home-dir $(shell_quote "$home") --no-create-home --shell /bin/bash $(shell_quote "$account")"
  command="$command && install -d -m 0755 -o $(shell_quote "$account") -g $(shell_quote "$group") $(shell_quote "$home")"
  run_with_privilege "$command"
  [ "$(classify_runtime_identity_state "$account" "$group" "$uid" "$gid" "$home" "$label")" = "ready" ] ||
    die "$label runtime identity creation did not establish the required state"
  printf 'created\n'
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
