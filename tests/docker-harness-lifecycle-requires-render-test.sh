#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir" "$repo_root/generated/simulation/docker"/requires-render-*-"$$" \
    "$repo_root/generated/simulation/docker/sets"/rr-*-"$$" 2>/dev/null || true
  rm -f "$repo_root/generated/simulation/docker/locks"/rr-*-"$$".lock 2>/dev/null || true
}
trap cleanup EXIT

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
  local label run_id set_id host state output rc
  label="${1:?label required}"
  shift
  run_id="requires-render-$label-$$"
  set_id="rr-${label:0:8}-$$"
  host="$repo_root/generated/simulation/docker/$run_id/host"
  state="$repo_root/generated/simulation/docker/$run_id/target/helper-state"
  output="$tmp_dir/$label.out"
  rm -f "$docker_calls" "$role_calls"

  set +e
  PATH="$fake_bin:$PATH" \
  DOCKER_CALLS_LOG="$docker_calls" \
  HARNESS_RUN_ID="$run_id" \
  HARNESS_SET_ID="$set_id" \
    "$repo_root/simulation/docker/simulate.sh" "$@" \
    >"$output" 2>&1
  rc=$?
  set -e

  [ "$rc" -ne 0 ] || {
    printf 'Expected %s to fail before init-run\n' "$*" >&2
    sed -n '1,80p' "$output" >&2
    exit 1
  }
  grep -Fq 'run init-run first' "$output"

  [ ! -e "$host/rendered/harness.env" ] || {
    printf '%s unexpectedly created rendered harness env\n' "$*" >&2
    exit 1
  }
  [ ! -e "$host/rendered/harness.runtime.env" ] || {
    printf '%s unexpectedly created runtime harness env\n' "$*" >&2
    exit 1
  }
  [ ! -d "$host/runtime-inputs" ] || {
    printf '%s unexpectedly created runtime input copies\n' "$*" >&2
    exit 1
  }
  [ ! -e "$role_calls" ] || {
    printf '%s unexpectedly reached role dispatch\n' "$*" >&2
    exit 1
  }
}

run_lifecycle_without_render start start
run_lifecycle_without_render stop stop
run_lifecycle_without_render create create
run_lifecycle_without_render prepare prepare-artifacts
run_lifecycle_without_render stage stage-artifacts
run_lifecycle_without_render configure-role configure-role --role gerrit
run_lifecycle_without_render validate-role validate-role --role gerrit
run_lifecycle_without_render configure-integration configure-integration
run_lifecycle_without_render validate-integration validate-integration
run_lifecycle_without_render prove-integration prove-integration
run_lifecycle_without_render verify audit-state

run_recovery_without_render() {
  local label run_id set_id host state output
  label="${1:?label required}"
  shift
  run_id="requires-render-$label-$$"
  set_id="rr-${label:0:8}-$$"
  host="$repo_root/generated/simulation/docker/$run_id/host"
  state="$repo_root/generated/simulation/docker/$run_id/target/helper-state"
  output="$tmp_dir/$label.out"
  rm -f "$docker_calls" "$role_calls"

  PATH="$fake_bin:$PATH" \
  DOCKER_CALLS_LOG="$docker_calls" \
  HARNESS_RUN_ID="$run_id" \
  HARNESS_SET_ID="$set_id" \
    "$repo_root/simulation/docker/simulate.sh" "$@" \
    >"$output" 2>&1

  [ ! -e "$host/rendered/harness.env" ] || {
    printf '%s unexpectedly created rendered harness env\n' "$*" >&2
    exit 1
  }
  [ ! -e "$host/rendered/harness.runtime.env" ] || {
    printf '%s unexpectedly created runtime harness env\n' "$*" >&2
    exit 1
  }
  [ ! -d "$host/runtime-inputs" ] || {
    printf '%s unexpectedly created runtime input copies\n' "$*" >&2
    exit 1
  }
}

run_recovery_without_render clean clean
