#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir" "$repo_root/generated/simulation/docker"/requires-render-*-"$$" 2>/dev/null || true' EXIT

calls="$tmp_dir/calls.log"

run_lifecycle_without_render() {
  local label run_id state output rc
  label="${1:?label required}"
  shift
  run_id="requires-render-$label-$$"
  state="$repo_root/generated/simulation/docker/$run_id/state"
  output="$tmp_dir/$label.out"
  rm -f "$calls"

  set +e
  HARNESS_TEST_STUB_ROLE_COMMANDS="$calls" \
  HARNESS_RUN_ID="$run_id" \
  HARNESS_PROJECT_NAME="$run_id" \
    "$repo_root/simulation/docker/simulate.sh" "$@" \
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
