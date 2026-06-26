#!/usr/bin/env bash
# shellcheck disable=SC2016

set -euo pipefail

repo_root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir" "$repo_root/generated/simulation/docker"/run-workflow-*-"$$" 2>/dev/null || true' EXIT

fake_bin="$tmp_dir/bin"
mkdir -p "$fake_bin"
cat >"$fake_bin/docker" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$DOCKER_CALLS_LOG"
case "$*" in
  *"compose version"*) printf 'Docker Compose version v2.0.0\n' ;;
  ps\ -a\ --format*) exit 0 ;;
  *) exit 0 ;;
esac
SH
chmod +x "$fake_bin/docker"

run_id="run-workflow-$$"
run_dir="$repo_root/generated/simulation/docker/$run_id"
fresh_calls="$tmp_dir/fresh-calls.log"
resume_calls="$tmp_dir/resume-calls.log"
blocked_output="$tmp_dir/blocked.out"

mkdir -p "$run_dir"

set +e
PATH="$fake_bin:$PATH" DOCKER_CALLS_LOG="$fresh_calls" \
  HARNESS_RUN_ID="$run_id" HARNESS_PROJECT_NAME="$run_id" \
  "$repo_root/simulation/docker/simulate.sh" run >"$tmp_dir/fresh.out" 2>&1
fresh_rc=$?
set -e
[ "$fresh_rc" -eq 0 ] || {
  printf 'fresh workflow failed\n' >&2
  sed -n '1,120p' "$tmp_dir/fresh.out" >&2
  exit 1
}
grep -Fq 'run: mode=fresh run-id='"$run_id" "$tmp_dir/fresh.out"

mkdir -p "$run_dir/state/rendered/runtime-inputs"
cat >"$run_dir/state/rendered/harness.env" <<EOF
HARNESS_MODE=docker-simulation
HARNESS_RUN_ID=$run_id
HARNESS_PROJECT_NAME=$run_id
HARNESS_GERRIT_ENV_FILE=examples/gerrit.env.example
HARNESS_JENKINS_CONTROLLER_ENV_FILE=examples/jenkins-controller.env.example
HARNESS_JENKINS_AGENT_ENV_FILE=examples/jenkins-agent.env.example
HARNESS_INTEGRATION_ENV_FILE=examples/integration.env.example
EOF
cat >"$run_dir/state/rendered/harness.runtime.env" <<EOF
HARNESS_MODE=docker-simulation
HARNESS_RUN_ID=$run_id
HARNESS_PROJECT_NAME=$run_id
HARNESS_GERRIT_ENV_FILE=examples/gerrit.env.example
HARNESS_JENKINS_CONTROLLER_ENV_FILE=examples/jenkins-controller.env.example
HARNESS_JENKINS_AGENT_ENV_FILE=examples/jenkins-agent.env.example
HARNESS_INTEGRATION_ENV_FILE=examples/integration.env.example
EOF
cat >"$run_dir/state/rendered/artifact-manifest-contract.txt" <<'EOF'
contract=original
EOF
for file in harness.env gerrit.env jenkins-controller.env jenkins-agent.env integration.env; do
  printf 'sentinel=%s\n' "$file" >"$run_dir/state/rendered/runtime-inputs/$file"
done
cat >"$run_dir/.loopforge-docker-run.env" <<EOF
mode=docker-simulation
run_id=$run_id
project_name=$run_id
repo_root=$repo_root
generated_run_dir=$run_dir
runtime_env_fingerprint=$(sha256sum "$run_dir/state/rendered/harness.runtime.env" | awk '{print $1}')
EOF

set +e
PATH="$fake_bin:$PATH" DOCKER_CALLS_LOG="$resume_calls" \
  HARNESS_RUN_ID="$run_id" HARNESS_PROJECT_NAME="$run_id" \
  "$repo_root/simulation/docker/simulate.sh" run >"$tmp_dir/resume.out" 2>&1
resume_rc=$?
set -e
[ "$resume_rc" -eq 0 ] || {
  printf 'resume workflow failed\n' >&2
  sed -n '1,160p' "$tmp_dir/resume.out" >&2
  exit 1
}
grep -Fq 'run: mode=resume run-id='"$run_id" "$tmp_dir/resume.out"

blocked_run_id="run-workflow-blocked-$$"
blocked_dir="$repo_root/generated/simulation/docker/$blocked_run_id"
mkdir -p "$blocked_dir/state/rendered"
cat >"$blocked_dir/state/rendered/harness.env" <<EOF
HARNESS_MODE=docker-simulation
HARNESS_RUN_ID=$blocked_run_id
HARNESS_PROJECT_NAME=$blocked_run_id
EOF

set +e
PATH="$fake_bin:$PATH" HARNESS_RUN_ID="$blocked_run_id" HARNESS_PROJECT_NAME="$blocked_run_id" \
  "$repo_root/simulation/docker/simulate.sh" run >"$blocked_output" 2>&1
blocked_rc=$?
set -e
[ "$blocked_rc" -ne 0 ] || {
  printf 'blocked workflow unexpectedly succeeded\n' >&2
  exit 1
}
grep -Eq 'partial or inconsistent|run down or clean' "$blocked_output"
