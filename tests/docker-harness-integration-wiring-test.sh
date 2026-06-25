#!/usr/bin/env bash
# shellcheck disable=SC2016

set -euo pipefail

repo_root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
run_id="integration-$$"
run_dir="$repo_root/generated/simulation/docker/$run_id"
trap 'rm -rf "$tmp_dir" "$run_dir" 2>/dev/null || true' EXIT

state_dir="$run_dir/state"
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
HARNESS_RUN_ID=$run_id
HARNESS_PROJECT_NAME=$run_id
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

  "$repo_root/simulation/docker/simulate.sh" render-config --env "$tmp_dir/harness.env" \
  >"$tmp_dir/render.out"

runtime_dir="$state_dir/rendered/runtime-inputs"
for file in gerrit jenkins-controller jenkins-agent integration; do
  printf '%s\n' "SENTINEL=mutated-$file" >"$tmp_dir/$file.env"
  grep -Fq "SENTINEL=original-$file" "$runtime_dir/$file.env"
done
mkdir -p "$state_dir/jenkins-controller"
chmod 0555 "$state_dir/jenkins-controller"

common_env=(
  HARNESS_TEST_STUB_ROLE_COMMANDS="$role_calls"
  HARNESS_TEST_INTEGRATION_HELPER="$integration_helper"
  HARNESS_TEST_INTEGRATION_CALLS="$integration_calls"
  HARNESS_ENV_FILE="$tmp_dir/harness.env"
)

env "${common_env[@]}" \
  "$repo_root/simulation/docker/simulate.sh" --env "$tmp_dir/harness.env" check >"$tmp_dir/check.out"

grep -Fxq 'run-role-gate gerrit' "$role_calls"
grep -Fxq 'run-role-gate jenkins-controller' "$role_calls"
grep -Fxq 'run-role-gate jenkins-agent' "$role_calls"
grep -Fq -- '--yes configure-gerrit-ssh' "$integration_calls"
grep -Fq -- '--yes configure-agent-ssh' "$integration_calls"
grep -Fq -- '--yes configure-trigger' "$integration_calls"
grep -Fq -- '--yes validate-integration' "$integration_calls"
grep -Fq -- "--gerrit-env $runtime_dir/gerrit.env" "$integration_calls"
grep -Fq -- "--integration-env $runtime_dir/integration.env" "$integration_calls"
grep -Fq -- 'listener_pid_file="/tmp/loopforge-stream-events-listener.pid"' "$repo_root/scripts/integration-setup.sh"
grep -Fq -- 'container_listener_log="$(integration_container_log_dir)/$listener_name"' "$repo_root/scripts/integration-setup.sh"
grep -Fq -- "gerrit stream-events >'\$container_listener_log' 2>&1 &" "$repo_root/scripts/integration-setup.sh"
grep -Fq -- 'cleanup_stream_events_listener()' "$repo_root/scripts/integration-setup.sh"
grep -Fq -- 'Gerrit REST could not create stream-events validation change' "$repo_root/scripts/integration-setup.sh"
if grep -Fq -- 'docker exec "$(jenkins_container)" ssh' "$repo_root/scripts/integration-setup.sh"; then
  printf 'stream-events validation must not background a host-side docker exec listener\n' >&2
  exit 1
fi
if grep -Fq -- "$tmp_dir/gerrit.env" "$integration_calls"; then
  printf 'integration wiring used original Gerrit env path after render\n' >&2
  exit 1
fi
[ ! -e "$state_dir/jenkins-controller/integration" ] || {
  printf 'check must not create integration state under Jenkins controller helper state\n' >&2
  exit 1
}
chmod 0755 "$state_dir/jenkins-controller"

: >"$role_calls"
: >"$integration_calls"
env "${common_env[@]}" \
  "$repo_root/simulation/docker/simulate.sh" --env "$tmp_dir/harness.env" full-verify >"$tmp_dir/full.out"

[ ! -s "$role_calls" ] || {
  printf 'full-verify unexpectedly ran role gates\n' >&2
  exit 1
}
if grep -Eq -- '--yes configure-gerrit-ssh|--yes configure-agent-ssh|--yes configure-trigger|--yes validate-integration' "$integration_calls"; then
  printf 'full-verify unexpectedly ran check-phase integration commands\n' >&2
  sed -n '1,120p' "$integration_calls" >&2
  exit 1
fi
grep -Fq -- '--yes verify-trigger' "$integration_calls"

missing_marker_calls="$tmp_dir/missing-marker-integration-calls.log"
rm -f "$state_dir/rendered/check-pass.env"
set +e
env \
  HARNESS_TEST_INTEGRATION_HELPER="$integration_helper" \
  HARNESS_TEST_INTEGRATION_CALLS="$missing_marker_calls" \
  HARNESS_ENV_FILE="$tmp_dir/harness.env" \
  "$repo_root/simulation/docker/simulate.sh" --env "$tmp_dir/harness.env" full-verify >"$tmp_dir/full-missing-marker.out" 2>&1
missing_marker_rc=$?
set -e
[ "$missing_marker_rc" -ne 0 ] || {
  printf 'full-verify unexpectedly succeeded without a prior check marker\n' >&2
  exit 1
}
grep -Fq 'Missing successful check marker; run check first' "$tmp_dir/full-missing-marker.out"
[ ! -s "$missing_marker_calls" ] || {
  printf 'full-verify called integration without a prior check marker\n' >&2
  sed -n '1,120p' "$missing_marker_calls" >&2
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
  "$repo_root/simulation/docker/simulate.sh" --env "$tmp_dir/harness.env" check >"$tmp_dir/check-failing-configure.out" 2>&1
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
