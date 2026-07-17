#!/usr/bin/env bash

validate_harness_set_id() {
  local value
  value="${1-}"
  if [ "${#value}" -lt 1 ] || [ "${#value}" -gt 24 ]; then
    die "HARNESS_SET_ID must be 1-24 characters"
  fi
  case "$value" in
    *[!a-z0-9-]*|-*|*-) die "HARNESS_SET_ID must use lowercase letters, digits, and internal hyphens" ;;
  esac
}

simulation_resource_namespace() {
  local backend set_id
  backend="${1:?backend required}"
  set_id="${2:?set ID required}"
  validate_harness_set_id "$set_id"
  case "$backend" in
    docker|vm) printf 'loopforge-%s-%s\n' "$backend" "$set_id" ;;
    *) die "Unknown simulation backend: $backend" ;;
  esac
}

simulation_short_resource_name() {
  local backend set_id resource_kind prefix max_length digest digest_length
  backend="${1:?backend required}"
  set_id="${2:?set ID required}"
  resource_kind="${3:?resource kind required}"
  prefix="${4:?prefix required}"
  max_length="${5:?maximum length required}"
  validate_harness_set_id "$set_id"
  case "$max_length" in
    ''|*[!0-9]*) die "Maximum resource-name length must be numeric" ;;
  esac
  digest_length=$((max_length - ${#prefix}))
  [ "$digest_length" -ge 8 ] || die "Resource-name limit is too short for collision-resistant derivation"
  digest="$(printf 'schema=1\nbackend=%s\nset_id=%s\nresource_kind=%s\n' \
    "$backend" "$set_id" "$resource_kind" | sha256sum | awk '{print $1}')"
  printf '%s%s\n' "$prefix" "${digest:0:digest_length}"
}

generate_harness_run_id() {
  local timestamp entropy digest
  timestamp="$(date -u +%Y%m%dt%H%M%Sz)"
  entropy="$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"
  digest="$(printf '%s:%s:%s\n' "$timestamp" "$$" "$entropy" |
    sha256sum | awk '{print $1}')"
  printf 'run-%s-%s\n' "$timestamp" "${digest:0:12}"
}

resolve_harness_run_id() {
  local backend backend_root set_id selected active_file
  backend="${1:?backend required}"
  backend_root="${2:?backend generated root required}"
  set_id="${3:?set ID required}"
  selected="${4-}"
  if [ -n "$selected" ]; then
    printf '%s\n' "$selected"
    return
  fi
  active_file="$backend_root/sets/$set_id/active-run.env"
  if [ -e "$active_file" ]; then
    active_run_record_is_strict "$active_file" ||
      die "Active-run pointer has malformed or unexpected fields: $active_file"
    [ "$(strict_record_value "$active_file" backend)" = "$backend" ] ||
      die "Active-run pointer backend does not match selected backend"
    [ "$(strict_record_value "$active_file" set_id)" = "$set_id" ] ||
      die "Active-run pointer set ID does not match selected set"
    printf '%s\n' "$(strict_record_value "$active_file" run_id)"
    return
  fi
  generate_harness_run_id
}
