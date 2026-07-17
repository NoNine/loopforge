#!/usr/bin/env bash

resolve_base_relative_path() {
  local base path
  base="${1:?base required}"
  path="${2:?path required}"
  case "$path" in
    /*) printf '%s\n' "$path" ;;
    *) printf '%s/%s\n' "$base" "$path" ;;
  esac
}

source_env_file() {
  local label file
  label="${1:?label required}"
  file="${2:?env file required}"
  require_readable_file "$label" "$file"
  set -a
  # shellcheck disable=SC1090
  . "$file"
  set +a
}

set_env_file_value() {
  local file name value tmp
  file="${1:?env file required}"
  name="${2:?env name required}"
  value="${3-}"
  tmp="$(mktemp "${file}.XXXXXX")"
  grep -v "^$name=" "$file" >"$tmp" || true
  printf '%s=%s\n' "$name" "$(shell_quote "$value")" >>"$tmp"
  chmod "${LF_MODE_PRIVATE_FILE:-0600}" "$tmp"
  mv -- "$tmp" "$file"
}

remove_env_file_value() {
  local file name tmp
  file="${1:?env file required}"
  name="${2:?env name required}"
  tmp="$(mktemp "${file}.XXXXXX")"
  grep -v "^$name=" "$file" >"$tmp" || true
  chmod "${LF_MODE_PRIVATE_FILE:-0600}" "$tmp"
  mv -- "$tmp" "$file"
}

copy_simulation_input_bundle() {
  local dest_dir harness_env role1_env role2_env role3_env integration_env
  dest_dir="${1:?destination required}"
  harness_env="${2:?harness env required}"
  role1_env="${3:?first role env required}"
  role2_env="${4:?second role env required}"
  role3_env="${5:?third role env required}"
  integration_env="${6:?integration env required}"

  install -d -m "${LF_MODE_PRIVATE_DIR:-0700}" "$dest_dir"
  install -m "${LF_MODE_PRIVATE_FILE:-0600}" "$harness_env" "$dest_dir/harness.env"
  install -m "${LF_MODE_PRIVATE_FILE:-0600}" "$role1_env" "$dest_dir/gerrit.env"
  install -m "${LF_MODE_PRIVATE_FILE:-0600}" "$role2_env" "$dest_dir/jenkins-controller.env"
  install -m "${LF_MODE_PRIVATE_FILE:-0600}" "$role3_env" "$dest_dir/jenkins-agent.env"
  install -m "${LF_MODE_PRIVATE_FILE:-0600}" "$integration_env" "$dest_dir/integration.env"
}

simulation_input_bundles_are_identical() {
  local left right file
  left="${1:?first input directory required}"
  right="${2:?second input directory required}"
  for file in harness.env gerrit.env jenkins-controller.env jenkins-agent.env integration.env; do
    [ -f "$left/$file" ] && [ -f "$right/$file" ] || return 1
    cmp -s -- "$left/$file" "$right/$file" || return 1
  done
}

simulation_input_staging_dir() {
  local target
  target="${1:?target input directory required}"
  mktemp -d "$(dirname "$target")/.effective-inputs.XXXXXX"
}

publish_simulation_input_bundle() {
  local staged target
  staged="${1:?staged input directory required}"
  target="${2:?target input directory required}"
  [ ! -e "$target" ] || die "Effective input directory already exists: $target"
  simulation_input_bundle_fingerprint "$staged" >/dev/null
  chmod "${LF_MODE_PRIVATE_DIR:-0700}" "$staged"
  mv -- "$staged" "$target"
}
