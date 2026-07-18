#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
docker_harness_sources=("$repo_root/simulation/docker/simulate.sh" "$repo_root/simulation/docker/lib/"*.sh)
tmp_dir="$(mktemp -d)"
fake_bin="$tmp_dir/bin"
run_id="clean-test-$$"
run_dir="$repo_root/generated/simulation/docker/$run_id"
set_runtime_dir="$repo_root/generated/simulation/docker/sets/$run_id/runtime"
calls="$tmp_dir/docker-calls.log"
trap 'rm -rf "$tmp_dir" "$run_dir" "$repo_root/generated/simulation/docker/sets/$run_id"; rm -f "$repo_root/generated/simulation/docker/locks/$run_id.lock"' EXIT

mkdir -p "$fake_bin"
cat >"$fake_bin/docker" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$DOCKER_CALLS_LOG"
case "$*" in
  *"compose version"*) printf 'Docker Compose version v2.0.0\n' ;;
  *"compose down --remove-orphans"*) exit 0 ;;
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
    if printf '%s\n' "$script" | grep -Fq 'backup_root="/cleanup-root/host/retained-output-backups/$backup_name"'; then
      backup_name="$5"
      backup_root="$source_path/host/retained-output-backups/$backup_name"
      mkdir -p "$backup_root/target/artifacts" "$backup_root/host" "$backup_root/target"
      [ ! -e "$source_path/target/artifacts/exported" ] || cp -a "$source_path/target/artifacts/exported" "$backup_root/target/artifacts/exported"
      [ ! -e "$source_path/host/evidence" ] || cp -a "$source_path/host/evidence" "$backup_root/host/evidence"
      [ ! -e "$source_path/host/logs" ] || cp -a "$source_path/host/logs" "$backup_root/host/logs"
      [ ! -e "$source_path/target/evidence" ] || cp -a "$source_path/target/evidence" "$backup_root/target/evidence"
      [ ! -e "$source_path/target/logs" ] || cp -a "$source_path/target/logs" "$backup_root/target/logs"
      rm -rf -- "$source_path/target/artifacts/exported" "$source_path/host/evidence" "$source_path/host/logs" "$source_path/target/evidence" "$source_path/target/logs"
    fi
    ;;
  *) exit 0 ;;
esac
SH
chmod +x "$fake_bin/docker"

cat >"$tmp_dir/harness.env" <<EOF
HARNESS_MODE=docker-simulation
HARNESS_RUN_ID=$run_id
HARNESS_SET_ID=$run_id
HARNESS_GERRIT_ENV_FILE=examples/gerrit.env.example
HARNESS_JENKINS_CONTROLLER_ENV_FILE=examples/jenkins-controller.env.example
HARNESS_JENKINS_AGENT_ENV_FILE=examples/jenkins-agent.env.example
HARNESS_INTEGRATION_ENV_FILE=examples/integration.env.example
EOF

PATH="$fake_bin:$PATH" \
DOCKER_CALLS_LOG="$calls" \
  "$repo_root/simulation/docker/simulate.sh" --env "$tmp_dir/harness.env" init-run >/dev/null

mkdir -p \
  "$set_runtime_dir/helper-state/runtime" \
  "$set_runtime_dir/product-homes/gerrit" \
  "$set_runtime_dir/artifacts/staging/gerrit" \
  "$run_dir/target/artifacts/exported/gerrit" \
  "$run_dir/host/evidence/harness" \
  "$run_dir/host/logs/harness" \
  "$run_dir/target/evidence/gerrit" \
  "$run_dir/target/logs/gerrit"
printf 'state\n' >"$set_runtime_dir/helper-state/runtime/file"
printf 'product\n' >"$set_runtime_dir/product-homes/gerrit/file"
printf 'stage\n' >"$set_runtime_dir/artifacts/staging/gerrit/file"
printf 'artifact\n' >"$run_dir/target/artifacts/exported/gerrit/file"
printf 'evidence\n' >"$run_dir/host/evidence/harness/file"
printf 'log\n' >"$run_dir/host/logs/harness/file"
printf 'role-evidence\n' >"$run_dir/target/evidence/gerrit/file"
printf 'role-log\n' >"$run_dir/target/logs/gerrit/file"

PATH="$fake_bin:$PATH" \
DOCKER_CALLS_LOG="$calls" \
  "$repo_root/simulation/docker/simulate.sh" --env "$tmp_dir/harness.env" clean >"$tmp_dir/clean.out"

grep -Eq 'clean: removed runtime data backup=clean-[0-9]{8}T[0-9]{6}Z cleanup=host' "$tmp_dir/clean.out"
if grep -Eq '/.*/host/retained-output-backups/clean-[0-9]{8}T[0-9]{6}Z' "$tmp_dir/clean.out"; then
  printf 'clean terminal summary must not print absolute backup path\n' >&2
  exit 1
fi
grep -Fq 'down --remove-orphans' "$calls"
[ -f "$set_runtime_dir/helper-state/runtime/file" ] || {
  printf 'clean must preserve durable helper state\n' >&2
  exit 1
}
[ -f "$set_runtime_dir/product-homes/gerrit/file" ] || {
  printf 'clean must preserve durable product homes\n' >&2
  exit 1
}
[ -f "$set_runtime_dir/artifacts/staging/gerrit/file" ] || {
  printf 'clean must preserve durable target staging\n' >&2
  exit 1
}
backup_dir="$(find "$run_dir/host/retained-output-backups" -mindepth 1 -maxdepth 1 -type d -name 'clean-*' -print | sort | tail -1)"
[ -n "$backup_dir" ] || {
  printf 'clean should create a retained output backup\n' >&2
  exit 1
}
grep -Fq 'artifact' "$backup_dir/target/artifacts/exported/gerrit/file"
grep -Fq 'evidence' "$backup_dir/host/evidence/harness/file"
grep -Fq 'log' "$backup_dir/host/logs/harness/file"
grep -Fq 'role-evidence' "$backup_dir/target/evidence/gerrit/file"
grep -Fq 'role-log' "$backup_dir/target/logs/gerrit/file"
[ -d "$run_dir/target/logs/gerrit" ] && [ -d "$run_dir/target/evidence/gerrit" ] || {
  printf 'clean should recreate active target evidence/log dirs\n' >&2
  exit 1
}
[ ! -e "$run_dir/target/artifacts/exported/gerrit/file" ] || {
  printf 'clean should clear active exported artifact contents\n' >&2
  exit 1
}
[ ! -e "$run_dir/target/evidence/gerrit/file" ] || {
  printf 'clean should clear active target evidence contents\n' >&2
  exit 1
}
if grep -Fq 'chown -R "$uid:$gid" "$path"' "${docker_harness_sources[@]}"; then
  printf 'clean must not normalize retained output ownership in place\n' >&2
  exit 1
fi

set +e
PATH="$fake_bin:$PATH" \
DOCKER_CALLS_LOG="$calls" \
HARNESS_STATE_DIR="$tmp_dir/custom-state" \
  "$repo_root/simulation/docker/simulate.sh" --env "$tmp_dir/harness.env" clean >"$tmp_dir/custom.out" 2>&1
custom_rc=$?
set -e
[ "$custom_rc" -ne 0 ] || {
  printf 'clean should reject custom output roots\n' >&2
  exit 1
}
grep -Fq 'output paths are fixed under generated/simulation/docker/<run-id>' "$tmp_dir/custom.out"
