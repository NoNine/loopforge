#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
fake_bin="$tmp_dir/bin"
calls="$tmp_dir/docker-calls.log"
run_id="state-lifecycle-$$"
set_id="state-life-$$"
run_dir="$repo_root/generated/simulation/docker/$run_id"
cleanup() {
  rc=$?
  if [ "$rc" -ne 0 ] && [ -f "$calls" ]; then
    printf '%s\n' '--- docker calls ---' >&2
    sed -n '1,240p' "$calls" >&2
  fi
  rm -rf "$tmp_dir" "$run_dir" "$repo_root/generated/simulation/docker/sets/$set_id"
  rm -f "$repo_root/generated/simulation/docker/locks/$set_id.lock"
  exit "$rc"
}
trap cleanup EXIT

mkdir -p "$fake_bin"
cat >"$fake_bin/docker" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$DOCKER_CALLS_LOG"
containers_file="$DOCKER_CONTAINERS_FILE"
case "$*" in
  *"compose version"*) printf 'Docker Compose version v2.0.0\n' ;;
  ps\ -a\ --format*)
    [ -f "$containers_file" ] && cat "$containers_file"
    ;;
  rm\ -f\ *)
    name="${*:3}"
    if [ -f "$containers_file" ]; then
      grep -Fxv "$name" "$containers_file" >"$containers_file.tmp" || true
      mv "$containers_file.tmp" "$containers_file"
    fi
    printf '%s\n' "$name"
    ;;
  network\ rm*) exit 0 ;;
  run\ --rm\ --mount*)
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --mount)
          mount_spec="$2"
          shift 2
          ;;
        ubuntu:24.04)
          shift
          break
          ;;
        *)
          shift
          ;;
      esac
    done
    source_path=""
    IFS=',' read -r _ source_part _ <<EOF_MOUNT
${mount_spec:-}
EOF_MOUNT
    case "$source_part" in
      source=*) source_path="${source_part#source=}" ;;
    esac
    [ -n "$source_path" ] || exit 1
    [ "${1:-}" = "sh" ] || exit 1
    [ "${2:-}" = "-c" ] || exit 1
    script="$3"
    if printf '%s\n' "$script" | grep -Fq 'rm -rf -- /cleanup-root/target/helper-state'; then
      rm -rf -- \
        "$source_path/target/helper-state" \
        "$source_path/target/product-homes" \
        "$source_path/target/artifacts/staging" \
        "$source_path/target/ldap" \
        "$source_path/target/shared-jenkins-storage" \
        "$source_path/host/rendered" \
        "$source_path/host/runtime-inputs" \
        "$source_path/host/target-ssh" \
        "$source_path/host/validation-secrets" \
        "$source_path/host/bundle-factory"
    fi
    if printf '%s\n' "$script" | grep -Fq 'backup_root="/cleanup-root/host/retained-output-backups/$backup_name"'; then
      backup_name="$5"
      backup_root="$source_path/host/retained-output-backups/$backup_name"
      mkdir -p "$backup_root/target/artifacts" "$backup_root/host" "$backup_root/target"
      [ ! -e "$source_path/target/artifacts/exported" ] || cp -a "$source_path/target/artifacts/exported" "$backup_root/target/artifacts/exported"
      [ ! -e "$source_path/host/evidence" ] || cp -a "$source_path/host/evidence" "$backup_root/host/evidence"
      [ ! -e "$source_path/target/evidence" ] || cp -a "$source_path/target/evidence" "$backup_root/target/evidence"
      rm -rf -- "$source_path/target/artifacts/exported" "$source_path/host/evidence" "$source_path/host/logs" "$source_path/target/evidence" "$source_path/target/logs"
    fi
    ;;
  compose*)
    if [ "${1:-}" = "compose" ]; then
      shift
    fi
    while [ "$#" -gt 0 ]; do
      case "$1" in
        -f|--file|--project-name|-p)
          shift 2
          ;;
        -*)
          shift
          ;;
        *)
          break
          ;;
      esac
    done
    case "${1:-}" in
      ps)
        shift
        [ "${1:-}" = "-q" ] && shift
        service="${1:-}"
        if grep -Fxq "$HARNESS_PROJECT_NAME-$service" "$containers_file" 2>/dev/null; then
          printf 'container-id\n'
        fi
        ;;
      up)
        printf 'compose up must not be called by role phases\n' >&2
        exit 99
        ;;
      down)
        exit 0
        ;;
      *)
        exit 0
        ;;
    esac
    ;;
  inspect\ -f\ *State.Running*)
    printf 'false\n'
    ;;
  inspect\ -f\ *Mounts*)
    case "$*" in
      *-gerrit-target)
        printf '%s\t%s\n' "$REPO_ROOT" /workspace
        printf '%s\t%s\n' "$RUN_DIR/target/helper-state/gerrit" /var/lib/loopforge
        printf '%s\t%s\n' "$RUN_DIR/target/product-homes/gerrit" /srv/gerrit
        printf '%s\t%s\n' "$RUN_DIR/host/validation-secrets/gerrit" /var/lib/loopforge/validation-secrets
        printf '%s\t%s\n' "$RUN_DIR/target/evidence/gerrit" /var/lib/loopforge/evidence
        printf '%s\t%s\n' "$RUN_DIR/target/logs/gerrit" /var/log/loopforge
        ;;
    esac
    ;;
  inspect*)
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
SH
chmod +x "$fake_bin/docker"

cat >"$tmp_dir/harness.env" <<EOF
HARNESS_MODE=docker-simulation
HARNESS_RUN_ID=$run_id
HARNESS_SET_ID=$set_id
HARNESS_GERRIT_ENV_FILE=examples/gerrit.env.example
HARNESS_JENKINS_CONTROLLER_ENV_FILE=examples/jenkins-controller.env.example
HARNESS_JENKINS_AGENT_ENV_FILE=examples/jenkins-agent.env.example
HARNESS_INTEGRATION_ENV_FILE=examples/integration.env.example
EOF

common_env=(
  PATH="$fake_bin:$PATH"
  DOCKER_CALLS_LOG="$calls"
  DOCKER_CONTAINERS_FILE="$tmp_dir/containers"
  REPO_ROOT="$repo_root"
  RUN_DIR="$run_dir"
)

printf 'loopforge-docker-%s-bundle-factory\n' "$set_id" >"$tmp_dir/containers"
set +e
env "${common_env[@]}" \
  "$repo_root/simulation/docker/simulate.sh" --env "$tmp_dir/harness.env" init-run \
  >"$tmp_dir/render-with-container.out" 2>&1
rc=$?
set -e
[ "$rc" -ne 0 ] || {
  printf 'init-run should fail when selected containers exist\n' >&2
  exit 1
}
grep -Fq 'Selected Docker simulation containers already exist' "$tmp_dir/render-with-container.out"

rm -f "$tmp_dir/containers"
env "${common_env[@]}" \
  "$repo_root/simulation/docker/simulate.sh" --env "$tmp_dir/harness.env" init-run >/dev/null

printf 'loopforge-docker-%s-gerrit-target\n' "$set_id" >"$tmp_dir/containers"
set +e
env "${common_env[@]}" \
  "$repo_root/simulation/docker/simulate.sh" --env "$tmp_dir/harness.env" stage-artifacts --role gerrit \
  >"$tmp_dir/stage-not-running.out" 2>&1
rc=$?
set -e
[ "$rc" -ne 0 ] || {
  printf 'stage-artifacts should fail when target is not running\n' >&2
  exit 1
}
grep -Fq 'Simulation effective inputs are pending; run start first' "$tmp_dir/stage-not-running.out"
if grep -Fq 'compose up -d --build' "$calls"; then
  printf 'stage-artifacts must not call Compose startup implicitly\n' >&2
  exit 1
fi

env "${common_env[@]}" \
  "$repo_root/simulation/docker/simulate.sh" --env "$tmp_dir/harness.env" stop >"$tmp_dir/stop.out"
grep -Fq 'stop: stopped harness containers' "$tmp_dir/stop.out"
[ -f "$repo_root/generated/simulation/docker/sets/$set_id/active-run.env" ]
[ -f "$run_dir/.loopforge-docker-run.env" ]
