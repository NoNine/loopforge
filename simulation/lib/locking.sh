#!/usr/bin/env bash

simulation_set_lock_path() {
  local backend_root set_id
  backend_root="${1:?backend generated root required}"
  set_id="${2:?set ID required}"
  validate_harness_set_id "$set_id"
  printf '%s/locks/%s.lock\n' "$backend_root" "$set_id"
}

simulation_set_lock_acquire() {
  local mode lock_file set_id lock_option
  mode="${1:?lock mode required}"
  lock_file="${2:?lock file required}"
  set_id="${3:?set ID required}"
  [ -z "${SIMULATION_SET_LOCK_FD:-}" ] || die "Simulation set lock is already held"
  case "$mode" in
    shared) lock_option=-s ;;
    exclusive) lock_option=-x ;;
    *) die "Unknown simulation set lock mode: $mode" ;;
  esac
  install -d -m "${LF_MODE_PUBLIC_DIR:-0755}" "$(dirname "$lock_file")"
  exec {SIMULATION_SET_LOCK_FD}>"$lock_file"
  chmod "${LF_MODE_PUBLIC_FILE:-0644}" "$lock_file"
  if ! flock -n "$lock_option" "$SIMULATION_SET_LOCK_FD"; then
    exec {SIMULATION_SET_LOCK_FD}>&-
    unset SIMULATION_SET_LOCK_FD
    die "set busy: $set_id"
  fi
}

simulation_set_lock_release() {
  [ -n "${SIMULATION_SET_LOCK_FD:-}" ] || return 0
  flock -u "$SIMULATION_SET_LOCK_FD"
  exec {SIMULATION_SET_LOCK_FD}>&-
  unset SIMULATION_SET_LOCK_FD
}

simulation_with_set_lock() {
  local mode lock_file set_id rc
  mode="${1:?lock mode required}"
  lock_file="${2:?lock file required}"
  set_id="${3:?set ID required}"
  shift 3
  simulation_set_lock_acquire "$mode" "$lock_file" "$set_id"
  if "$@"; then
    rc=0
  else
    rc=$?
  fi
  simulation_set_lock_release
  return "$rc"
}
