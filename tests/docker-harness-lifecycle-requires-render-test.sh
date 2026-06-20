#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

state_dir="$tmp_dir/state"
staging_dir="$tmp_dir/staging"
evidence_dir="$tmp_dir/evidence"
log_dir="$tmp_dir/logs"
calls="$tmp_dir/calls.log"

run_lifecycle_without_render() {
  local label state staging evidence logs output rc
  label="${1:?label required}"
  shift
  state="$state_dir/$label"
  staging="$staging_dir/$label"
  evidence="$evidence_dir/$label"
  logs="$log_dir/$label"
  output="$tmp_dir/$label.out"
  rm -f "$calls"

  set +e
  HARNESS_TEST_STUB_ROLE_COMMANDS="$calls" \
  HARNESS_RUN_ID="requires-render-$label-$$" \
  HARNESS_PROJECT_NAME="requires-render-$label-$$" \
  HARNESS_STATE_DIR="$state" \
  HARNESS_STAGING_DIR="$staging" \
  HARNESS_EVIDENCE_DIR="$evidence" \
  HARNESS_LOG_DIR="$logs" \
    "$repo_root/simulation/docker/docker-harness.sh" "$@" \
    >"$output" 2>&1
  rc=$?
  set -e

  [ "$rc" -ne 0 ] || {
    printf 'Expected %s to fail before render-config\n' "$*" >&2
    exit 1
  }
  grep -Fq 'run render-config first' "$output"

  [ ! -e "$state/rendered/harness.env" ] || {
    printf '%s unexpectedly created rendered harness env\n' "$*" >&2
    exit 1
  }
  [ ! -e "$state/rendered/harness.runtime.env" ] || {
    printf '%s unexpectedly created runtime harness env\n' "$*" >&2
    exit 1
  }
  [ ! -d "$state/rendered/runtime-inputs" ] || {
    printf '%s unexpectedly created runtime input copies\n' "$*" >&2
    exit 1
  }
  [ ! -e "$calls" ] || {
    printf '%s unexpectedly reached role dispatch\n' "$*" >&2
    exit 1
  }
}

run_lifecycle_without_render up up
run_lifecycle_without_render prepare prepare-artifacts
run_lifecycle_without_render stage stage-artifacts
run_lifecycle_without_render gate run-role-gate --role gerrit
run_lifecycle_without_render check check
run_lifecycle_without_render full full-verify
run_lifecycle_without_render down down
