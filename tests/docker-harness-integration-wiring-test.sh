#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir" 2>/dev/null || true' EXIT

state_dir="$tmp_dir/state"
staging_dir="$tmp_dir/staging"
evidence_dir="$tmp_dir/evidence"
log_dir="$tmp_dir/logs"
role_calls="$tmp_dir/role-calls.log"
integration_calls="$tmp_dir/integration-calls.log"
integration_helper="$tmp_dir/integration-setup.sh"

for file in gerrit jenkins-controller jenkins-agent integration; do
  printf '%s\n' "SENTINEL=original-$file" >"$tmp_dir/$file.env"
done
cat >>"$tmp_dir/integration.env" <<'EOF'
JENKINS_SHARED_STORAGE_PATH=/mnt/harness-shared
EOF
cat >"$tmp_dir/harness.env" <<EOF
HARNESS_MODE=docker-simulation
HARNESS_RUN_ID=integration-$$
HARNESS_PROJECT_NAME=integration-$$
HARNESS_GERRIT_ENV_FILE=$(printf '%q' "$tmp_dir/gerrit.env")
HARNESS_JENKINS_CONTROLLER_ENV_FILE=$(printf '%q' "$tmp_dir/jenkins-controller.env")
HARNESS_JENKINS_AGENT_ENV_FILE=$(printf '%q' "$tmp_dir/jenkins-agent.env")
HARNESS_INTEGRATION_ENV_FILE=$(printf '%q' "$tmp_dir/integration.env")
EOF

cat >"$integration_helper" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$HARNESS_TEST_INTEGRATION_CALLS"
SH
chmod +x "$integration_helper"

HARNESS_RUN_ID="integration-$$" \
HARNESS_PROJECT_NAME="integration-$$" \
HARNESS_STATE_DIR="$state_dir" \
HARNESS_STAGING_DIR="$staging_dir" \
HARNESS_EVIDENCE_DIR="$evidence_dir" \
HARNESS_LOG_DIR="$log_dir" \
  "$repo_root/simulation/docker/simulate.sh" render-config --env "$tmp_dir/harness.env" \
  >"$tmp_dir/render.out"

runtime_dir="$state_dir/rendered/runtime-inputs"
for file in gerrit jenkins-controller jenkins-agent integration; do
  printf '%s\n' "SENTINEL=mutated-$file" >"$tmp_dir/$file.env"
  grep -Fq "SENTINEL=original-$file" "$runtime_dir/$file.env"
done

common_env=(
  HARNESS_TEST_STUB_ROLE_COMMANDS="$role_calls"
  HARNESS_TEST_INTEGRATION_HELPER="$integration_helper"
  HARNESS_TEST_INTEGRATION_CALLS="$integration_calls"
  HARNESS_RUN_ID="integration-$$"
  HARNESS_PROJECT_NAME="integration-$$"
  HARNESS_STATE_DIR="$state_dir"
  HARNESS_STAGING_DIR="$staging_dir"
  HARNESS_EVIDENCE_DIR="$evidence_dir"
  HARNESS_LOG_DIR="$log_dir"
)

env "${common_env[@]}" \
  "$repo_root/simulation/docker/simulate.sh" check >"$tmp_dir/check.out"

grep -Fxq 'run-role-gate gerrit' "$role_calls"
grep -Fxq 'run-role-gate jenkins-controller' "$role_calls"
grep -Fxq 'run-role-gate jenkins-agent' "$role_calls"
grep -Fq -- '--yes configure-gerrit-ssh' "$integration_calls"
grep -Fq -- '--yes configure-agent-ssh' "$integration_calls"
grep -Fq -- '--yes configure-trigger' "$integration_calls"
grep -Fq -- '--yes validate-integration' "$integration_calls"
grep -Fq -- "--gerrit-env $runtime_dir/gerrit.env" "$integration_calls"
grep -Fq -- "--integration-env $runtime_dir/integration.env" "$integration_calls"
if grep -Fq -- "$tmp_dir/gerrit.env" "$integration_calls"; then
  printf 'integration wiring used original Gerrit env path after render\n' >&2
  exit 1
fi

: >"$role_calls"
: >"$integration_calls"
env "${common_env[@]}" \
  "$repo_root/simulation/docker/simulate.sh" full-verify >"$tmp_dir/full.out"

grep -Fq -- '--yes validate-integration' "$integration_calls"
grep -Fq -- '--yes verify-trigger' "$integration_calls"

failing_role_calls="$tmp_dir/failing-role-calls.log"
failing_integration_calls="$tmp_dir/failing-integration-calls.log"
set +e
env \
  HARNESS_TEST_STUB_ROLE_COMMANDS="$failing_role_calls" \
  HARNESS_TEST_STUB_ROLE_FAIL="jenkins-controller" \
  HARNESS_TEST_INTEGRATION_HELPER="$integration_helper" \
  HARNESS_TEST_INTEGRATION_CALLS="$failing_integration_calls" \
  HARNESS_RUN_ID="integration-$$" \
  HARNESS_PROJECT_NAME="integration-$$" \
  HARNESS_STATE_DIR="$state_dir" \
  HARNESS_STAGING_DIR="$staging_dir" \
  HARNESS_EVIDENCE_DIR="$evidence_dir" \
  HARNESS_LOG_DIR="$log_dir" \
  "$repo_root/simulation/docker/simulate.sh" full-verify >"$tmp_dir/full-failing.out" 2>&1
failing_rc=$?
set -e

[ "$failing_rc" -ne 0 ] || {
  printf 'Expected full-verify to fail when a role gate fails\n' >&2
  exit 1
}
grep -Fxq 'run-role-gate jenkins-controller' "$failing_role_calls"
[ ! -s "$failing_integration_calls" ] || {
  printf 'full-verify called integration after role gate failure\n' >&2
  sed -n '1,120p' "$failing_integration_calls" >&2
  exit 1
}

failing_configure_calls="$tmp_dir/failing-configure-calls.log"
failing_configure_helper="$tmp_dir/failing-configure-integration-setup.sh"
cat >"$failing_configure_helper" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$HARNESS_TEST_INTEGRATION_CALLS"
case "$*" in
  *' configure-gerrit-ssh') exit 42 ;;
esac
SH
chmod +x "$failing_configure_helper"

set +e
env "${common_env[@]}" \
  HARNESS_TEST_INTEGRATION_HELPER="$failing_configure_helper" \
  HARNESS_TEST_INTEGRATION_CALLS="$failing_configure_calls" \
  "$repo_root/simulation/docker/simulate.sh" check >"$tmp_dir/check-failing-configure.out" 2>&1
failing_configure_rc=$?
set -e

[ "$failing_configure_rc" -eq 42 ] || {
  printf 'Expected check to return configure-gerrit-ssh failure rc 42, got %s\n' "$failing_configure_rc" >&2
  exit 1
}
grep -Fq -- '--yes configure-gerrit-ssh' "$failing_configure_calls"
if grep -Eq -- '--yes configure-agent-ssh|--yes configure-trigger|--yes validate-integration' "$failing_configure_calls"; then
  printf 'check continued integration commands after configure-gerrit-ssh failure\n' >&2
  sed -n '1,120p' "$failing_configure_calls" >&2
  exit 1
fi
