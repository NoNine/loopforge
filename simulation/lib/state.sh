#!/usr/bin/env bash

sha256_file() {
  sha256sum "$1" | awk '{print $1}'
}

runtime_env_fingerprint() {
  local runtime_env
  runtime_env="${1:-${HARNESS_RUNTIME_ENV:-}}"
  [ -n "$runtime_env" ] || die "runtime env path required"
  sha256_file "$runtime_env"
}

marker_value() {
  local file key
  file="${1:?file required}"
  key="${2:?key required}"
  awk -F= -v key="$key" '$1 == key { print substr($0, length(key) + 2); found = 1; exit } END { exit !found }' "$file"
}

write_runtime_marker() {
  local marker mode run_id project_name repo_root generated_run_dir runtime_env fingerprint
  marker="${1:?marker required}"
  mode="${2:?mode required}"
  run_id="${3:?run ID required}"
  project_name="${4:?project name required}"
  repo_root="${5:?repo root required}"
  generated_run_dir="${6:?generated run dir required}"
  runtime_env="${7:?runtime env required}"
  fingerprint="$(runtime_env_fingerprint "$runtime_env")"
  mkdir -p "$(dirname "$marker")"
  cat >"$marker" <<EOF
mode=$mode
run_id=$run_id
project_name=$project_name
repo_root=$repo_root
generated_run_dir=$generated_run_dir
runtime_env_fingerprint=$fingerprint
EOF
  chmod "${LF_MODE_PUBLIC_FILE:-0644}" "$marker"
}

verify_runtime_marker() {
  local marker mode run_id project_name repo_root generated_run_dir runtime_env label fingerprint
  marker="${1:?marker required}"
  mode="${2:?mode required}"
  run_id="${3:?run ID required}"
  project_name="${4:?project name required}"
  repo_root="${5:?repo root required}"
  generated_run_dir="${6:?generated run dir required}"
  runtime_env="${7:?runtime env required}"
  label="${8:-Run marker}"

  [ -f "$marker" ] || die "Missing $label: $marker"
  [ "$(marker_value "$marker" mode)" = "$mode" ] ||
    die "$label mode does not match selected runtime config"
  [ "$(marker_value "$marker" run_id)" = "$run_id" ] ||
    die "$label run ID does not match selected runtime config"
  [ "$(marker_value "$marker" project_name)" = "$project_name" ] ||
    die "$label project name does not match selected runtime config"
  [ "$(marker_value "$marker" repo_root)" = "$repo_root" ] ||
    die "$label repo root does not match this checkout"
  [ "$(marker_value "$marker" generated_run_dir)" = "$generated_run_dir" ] ||
    die "$label generated run dir does not match selected runtime config"
  fingerprint="$(runtime_env_fingerprint "$runtime_env")"
  [ "$(marker_value "$marker" runtime_env_fingerprint)" = "$fingerprint" ] ||
    die "$label runtime env fingerprint does not match selected runtime config"
}

write_checkpoint_marker() {
  local marker mode run_id project_name runtime_env fingerprint
  marker="${1:?marker required}"
  mode="${2:?mode required}"
  run_id="${3:?run ID required}"
  project_name="${4:?project name required}"
  runtime_env="${5:?runtime env required}"
  fingerprint="$(runtime_env_fingerprint "$runtime_env")"
  mkdir -p "$(dirname "$marker")"
  cat >"$marker" <<EOF
mode=$mode
run_id=$run_id
project_name=$project_name
runtime_env_fingerprint=$fingerprint
EOF
  chmod "${LF_MODE_PUBLIC_FILE:-0644}" "$marker"
}

verify_checkpoint_marker() {
  local marker mode run_id project_name runtime_env label fingerprint
  marker="${1:?marker required}"
  mode="${2:?mode required}"
  run_id="${3:?run ID required}"
  project_name="${4:?project name required}"
  runtime_env="${5:?runtime env required}"
  label="${6:-Checkpoint marker}"

  [ -f "$marker" ] || die "Missing $label: $marker"
  [ "$(marker_value "$marker" mode)" = "$mode" ] ||
    die "$label mode does not match selected runtime config"
  [ "$(marker_value "$marker" run_id)" = "$run_id" ] ||
    die "$label run ID does not match selected runtime config"
  [ "$(marker_value "$marker" project_name)" = "$project_name" ] ||
    die "$label project name does not match selected runtime config"
  fingerprint="$(runtime_env_fingerprint "$runtime_env")"
  [ "$(marker_value "$marker" runtime_env_fingerprint)" = "$fingerprint" ] ||
    die "$label runtime env fingerprint does not match selected runtime config"
}

require_generated_state_file() {
  local state_name label file
  state_name="${1:?state name required}"
  label="${2:?label required}"
  file="${3:?file required}"
  [ -f "$file" ] || die "Inconsistent $state_name: missing $label: $file"
  [ -r "$file" ] || die "Inconsistent $state_name: unreadable $label: $file"
}

require_generated_state_dir() {
  local state_name label dir
  state_name="${1:?state name required}"
  label="${2:?label required}"
  dir="${3:?dir required}"
  [ -d "$dir" ] || die "Inconsistent $state_name: missing $label: $dir"
  [ ! -L "$dir" ] || die "Inconsistent $state_name: $label must not be a symlink: $dir"
}

any_path_exists() {
  local path
  for path in "$@"; do
    [ -e "$path" ] && return 0
  done
  return 1
}
