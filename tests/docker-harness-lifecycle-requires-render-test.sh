#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir" "$repo_root/generated/simulation/docker"/requires-render-*-"$$" 2>/dev/null || true' EXIT

docker_calls="$tmp_dir/docker-calls.log"
role_calls="$tmp_dir/role-calls.log"
fake_bin="$tmp_dir/bin"

mkdir -p "$fake_bin"
cat >"$fake_bin/docker" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$DOCKER_CALLS_LOG"
case "$*" in
  *"compose version"*) printf 'Docker Compose version v2.0.0\n' ;;
  ps\ -a\ --format*) exit 0 ;;
  network\ rm*) exit 0 ;;
  *) exit 0 ;;
esac
SH
chmod +x "$fake_bin/docker"

run_lifecycle_without_render() {
  local label run_id state output rc
  label="${1:?label required}"
  shift
  run_id="requires-render-$label-$$"
  state="$repo_root/generated/simulation/docker/$run_id/state"
  output="$tmp_dir/$label.out"
  rm -f "$docker_calls" "$role_calls"

  set +e
  PATH="$fake_bin:$PATH" \
  DOCKER_CALLS_LOG="$docker_calls" \
  HARNESS_TEST_STUB_ROLE_COMMANDS="$role_calls" \
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
  [ ! -e "$role_calls" ] || {
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

run_recovery_without_render() {
  local label run_id state output
  label="${1:?label required}"
  shift
  run_id="requires-render-$label-$$"
  state="$repo_root/generated/simulation/docker/$run_id/state"
  output="$tmp_dir/$label.out"
  rm -f "$docker_calls" "$role_calls"

  PATH="$fake_bin:$PATH" \
  DOCKER_CALLS_LOG="$docker_calls" \
  HARNESS_RUN_ID="$run_id" \
  HARNESS_PROJECT_NAME="$run_id" \
    "$repo_root/simulation/docker/simulate.sh" "$@" \
    >"$output" 2>&1

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
}

run_recovery_without_render down down
run_recovery_without_render clean clean
