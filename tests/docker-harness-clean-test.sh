#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
fake_bin="$tmp_dir/bin"
run_id="clean-test-$$"
run_dir="$repo_root/generated/simulation/docker/$run_id"
calls="$tmp_dir/docker-calls.log"
trap 'rm -rf "$tmp_dir" "$run_dir"' EXIT

mkdir -p "$fake_bin"
cat >"$fake_bin/docker" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$DOCKER_CALLS_LOG"
case "$*" in
  *"compose version"*) printf 'Docker Compose version v2.0.0\n' ;;
  *"compose down --remove-orphans"*) exit 0 ;;
  *) exit 0 ;;
esac
SH
chmod +x "$fake_bin/docker"

cat >"$tmp_dir/harness.env" <<EOF
HARNESS_MODE=docker-simulation
HARNESS_RUN_ID=$run_id
HARNESS_PROJECT_NAME=$run_id
HARNESS_GERRIT_ENV_FILE=examples/gerrit.env.example
HARNESS_JENKINS_CONTROLLER_ENV_FILE=examples/jenkins-controller.env.example
HARNESS_JENKINS_AGENT_ENV_FILE=examples/jenkins-agent.env.example
HARNESS_INTEGRATION_ENV_FILE=examples/integration.env.example
EOF

PATH="$fake_bin:$PATH" \
DOCKER_CALLS_LOG="$calls" \
  "$repo_root/simulation/docker/simulate.sh" --env "$tmp_dir/harness.env" render-config >/dev/null

mkdir -p \
  "$run_dir/state/runtime" \
  "$run_dir/product-homes/gerrit" \
  "$run_dir/staging/gerrit" \
  "$run_dir/exported-artifacts/gerrit" \
  "$run_dir/evidence" \
  "$run_dir/logs"
printf 'state\n' >"$run_dir/state/runtime/file"
printf 'product\n' >"$run_dir/product-homes/gerrit/file"
printf 'stage\n' >"$run_dir/staging/gerrit/file"
printf 'artifact\n' >"$run_dir/exported-artifacts/gerrit/file"
printf 'evidence\n' >"$run_dir/evidence/file"
printf 'log\n' >"$run_dir/logs/file"

PATH="$fake_bin:$PATH" \
DOCKER_CALLS_LOG="$calls" \
  "$repo_root/simulation/docker/simulate.sh" --env "$tmp_dir/harness.env" clean >"$tmp_dir/clean.out"

grep -Fq 'clean: removed runtime data preserved exported-artifacts evidence logs cleanup=host' "$tmp_dir/clean.out"
grep -Fq 'down --remove-orphans' "$calls"
[ ! -e "$run_dir/state" ] || {
  printf 'clean should remove state\n' >&2
  exit 1
}
[ ! -e "$run_dir/product-homes" ] || {
  printf 'clean should remove product homes\n' >&2
  exit 1
}
[ ! -e "$run_dir/staging" ] || {
  printf 'clean should remove staging\n' >&2
  exit 1
}
grep -Fq 'artifact' "$run_dir/exported-artifacts/gerrit/file"
grep -Fq 'evidence' "$run_dir/evidence/file"
[ -d "$run_dir/logs" ] || {
  printf 'clean should preserve logs directory\n' >&2
  exit 1
}

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
