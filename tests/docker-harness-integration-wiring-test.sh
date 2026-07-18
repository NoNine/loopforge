#!/usr/bin/env bash
# shellcheck disable=SC2016

set -euo pipefail

repo_root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
fake_bin="$tmp_dir/bin"
run_id="integration-$$"
run_dir="$repo_root/generated/simulation/docker/$run_id"
trap 'rm -rf "$tmp_dir" "$run_dir" "$repo_root/generated/simulation/docker/sets/$run_id" 2>/dev/null || true; rm -f "$repo_root/generated/simulation/docker/locks/$run_id.lock"' EXIT

host_dir="$run_dir/host"
state_dir="$repo_root/generated/simulation/docker/sets/$run_id/runtime/helper-state"
integration_calls="$tmp_dir/integration-calls.log"
integration_helper="$tmp_dir/integration-setup.sh"

mkdir -p "$fake_bin"
cat >"$fake_bin/docker" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
. "$DOCKER_SET_FAKE_LIB"
if fake_docker_set_handle "$@"; then exit 0; else rc=$?; [ "$rc" -eq 125 ] || exit "$rc"; fi
case "$*" in
  *"compose version"*) printf 'Docker Compose version v2.0.0\n' ;;
  *" ps -q "*) printf 'container-id\n' ;;
  *"/etc/os-release"*) printf 'release=24.04 codename=noble pretty=Ubuntu 24.04\n' ;;
  *"inspect -f"*) printf 'true\n' ;;
  *) exit 0 ;;
esac
SH
chmod +x "$fake_bin/docker"
export DOCKER_SET_FAKE_LIB="$repo_root/tests/fixtures/docker-set-state.sh"
export DOCKER_SET_FAKE_STATE_DIR="$tmp_dir/docker-state"
export REPO_ROOT="$repo_root"
cat >"$fake_bin/ssh-keyscan" <<'SH'
#!/usr/bin/env bash
printf '[127.0.0.1]:%s ssh-ed25519 test-key\n' "${4:-22}"
SH
chmod +x "$fake_bin/ssh-keyscan"

for file in gerrit jenkins-controller jenkins-agent integration; do
  printf '%s\n' "SENTINEL=original-$file" >"$tmp_dir/$file.env"
done
cat >>"$tmp_dir/integration.env" <<'EOF'
JENKINS_SHARED_STORAGE_PATH=/data/jenkins-shared
EOF
cat >"$tmp_dir/harness.env" <<EOF
HARNESS_MODE=docker-simulation
HARNESS_RUN_ID=$run_id
HARNESS_SET_ID=$run_id
HARNESS_GERRIT_ENV_FILE=$(printf '%q' "$tmp_dir/gerrit.env")
HARNESS_JENKINS_CONTROLLER_ENV_FILE=$(printf '%q' "$tmp_dir/jenkins-controller.env")
HARNESS_JENKINS_AGENT_ENV_FILE=$(printf '%q' "$tmp_dir/jenkins-agent.env")
HARNESS_INTEGRATION_ENV_FILE=$(printf '%q' "$tmp_dir/integration.env")
EOF

cat >"$integration_helper" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$HARNESS_TEST_INTEGRATION_CALLS"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --integration-env)
      printf '%s\n' "$2" >"$HARNESS_TEST_ADAPTER_PATH"
      cp "$2" "$HARNESS_TEST_ADAPTER_COPY"
      shift 2
      ;;
    *) shift ;;
  esac
done
SH
chmod +x "$integration_helper"

PATH="$fake_bin:$PATH" \
  "$repo_root/simulation/docker/simulate.sh" init-run --env "$tmp_dir/harness.env" \
  >"$tmp_dir/init-run.out"

source_dir="$host_dir/source-inputs"
runtime_dir="$host_dir/runtime-inputs"
for file in gerrit jenkins-controller jenkins-agent integration; do
  printf '%s\n' "SENTINEL=mutated-$file" >"$tmp_dir/$file.env"
  grep -Fq "SENTINEL=original-$file" "$source_dir/$file.env"
done
PATH="$fake_bin:$PATH" \
  "$repo_root/simulation/docker/simulate.sh" create --env "$tmp_dir/harness.env" >/dev/null
PATH="$fake_bin:$PATH" \
  "$repo_root/simulation/docker/simulate.sh" start --env "$tmp_dir/harness.env" >/dev/null
for file in gerrit jenkins-controller jenkins-agent integration; do
  grep -Fq "SENTINEL=original-$file" "$runtime_dir/$file.env"
done
mkdir -p "$state_dir/jenkins-controller"
chmod 0555 "$state_dir/jenkins-controller"

common_env=(
  HARNESS_TEST_INTEGRATION_HELPER="$integration_helper"
  HARNESS_TEST_INTEGRATION_CALLS="$integration_calls"
  HARNESS_TEST_ADAPTER_PATH="$tmp_dir/adapter.path"
  HARNESS_TEST_ADAPTER_COPY="$tmp_dir/adapter.env"
  HARNESS_ENV_FILE="$tmp_dir/harness.env"
  PATH="$fake_bin:$PATH"
)

env "${common_env[@]}" \
  "$repo_root/simulation/docker/simulate.sh" --env "$tmp_dir/harness.env" configure-integration \
  >"$tmp_dir/configure-integration.out"

grep -Fq -- '--yes configure-integration' "$integration_calls"
grep -Fq -- "--gerrit-env $runtime_dir/gerrit.env" "$integration_calls"
adapter_path="$(cat "$tmp_dir/adapter.path")"
[ ! -e "$adapter_path" ]
grep -Fq 'INTEGRATION_GERRIT_TARGET_SSH_HOST=127.0.0.1' "$tmp_dir/adapter.env"
grep -Fq 'INTEGRATION_JENKINS_CONTROLLER_TARGET_SSH_HOST=127.0.0.1' "$tmp_dir/adapter.env"
grep -Fq 'INTEGRATION_JENKINS_AGENT_TARGET_SSH_HOST=127.0.0.1' "$tmp_dir/adapter.env"
grep -Fq 'SENTINEL=original-integration' "$tmp_dir/adapter.env"
if grep -Fq -- "$tmp_dir/gerrit.env" "$integration_calls"; then
  printf 'integration wiring used original Gerrit env path after render\n' >&2
  exit 1
fi
[ ! -e "$state_dir/jenkins-controller/integration" ] || {
  printf 'integration phases must not create integration state under Jenkins controller helper state\n' >&2
  exit 1
}
chmod 0755 "$state_dir/jenkins-controller"

env "${common_env[@]}" \
  "$repo_root/simulation/docker/simulate.sh" --env "$tmp_dir/harness.env" validate-integration \
  >"$tmp_dir/validate-integration.out"
grep -Fq -- '--yes validate-integration' "$integration_calls"

env "${common_env[@]}" \
  "$repo_root/simulation/docker/simulate.sh" --env "$tmp_dir/harness.env" prove-integration \
  >"$tmp_dir/prove-integration.out"
grep -Fq -- '--yes prove-integration' "$integration_calls"

grep -Fq -- 'listener_pid_file="/tmp/loopforge-stream-events-listener.pid"' "$repo_root/scripts/integration-setup.sh"
grep -Fq -- 'target_listener_log="$(jenkins_ops_tmp_dir)/$listener_name"' "$repo_root/scripts/integration-setup.sh"
grep -Fq -- "gerrit stream-events >'\$target_listener_log' 2>&1 &" "$repo_root/scripts/integration-setup.sh"
grep -Fq -- 'cleanup_stream_events_listener()' "$repo_root/scripts/integration-setup.sh"
grep -Fq -- 'Gerrit REST could not create stream-events validation change' "$repo_root/scripts/integration-setup.sh"
grep -Fq -- 'server.start()' "$repo_root/scripts/integration-setup.sh"
if grep -Fq -- 'server.startConnection()' "$repo_root/scripts/integration-setup.sh"; then
  printf 'configure-integration must not call startConnection after server.start\n' >&2
  exit 1
fi
if sed -n '/cmd_prove_integration()/,/^}/p' "$repo_root/scripts/integration-setup.sh" | grep -Fq -- 'validate_integration_impl'; then
  printf 'prove-integration must require validate-integration state, not rerun it\n' >&2
  exit 1
fi
if sed -n '/validate_integration_impl()/,/^}/p' "$repo_root/scripts/integration-setup.sh" |
  grep -Eq -- 'prove_stream_events|schedule_smoke_build|prove_shared_storage_rw|create_gerrit_change|validate_agent_online|configure_verification_job'
then
  printf 'validate-integration must stay passive and must not run active proof\n' >&2
  exit 1
fi
grep -Fq -- 'GERRIT_TRIGGER_SERVER_NAME="${GERRIT_TRIGGER_SERVER_NAME:-gerrit}"' "$repo_root/scripts/integration-setup.sh"
grep -Fq -- 'JENKINS_VERIFICATION_JOB="${JENKINS_VERIFICATION_JOB:-gerrit-verification}"' "$repo_root/scripts/integration-setup.sh"
grep -Fq -- 'JENKINS_GERRIT_TOKEN_ID="${JENKINS_GERRIT_TOKEN_ID:-jenkins-trigger}"' "$repo_root/scripts/integration-setup.sh"
grep -Fq -- 'ensure_gerrit_admin_account_provisioned "$log"' "$repo_root/scripts/integration-setup.sh"
grep -Fq -- 'ensure_gerrit_test_account_provisioned "$log"' "$repo_root/scripts/integration-setup.sh"
grep -Fq -- 'ensure_gerrit_integration_account "$log"' "$repo_root/scripts/integration-setup.sh"
grep -Fq -- 'gerrit_account_provision=simulation-login' "$repo_root/scripts/integration-setup.sh"
grep -Fq -- 'Gerrit $role account is not provisioned or the credential was rejected; sign in once as' "$repo_root/scripts/integration-setup.sh"
grep -Fq -- 'review_apply=gerrit-trigger-rest' "$repo_root/scripts/integration-setup.sh"
if ! awk '
  /^prove_stream_events\(\)/ { in_fn=1 }
  /^validate_integration_impl\(\)/ { exit }
  in_fn { print }
' "$repo_root/scripts/integration-setup.sh" |
  grep -Fq -- 'ensure_gerrit_test_account_provisioned "$log"'
then
  printf 'stream-events proof must provision/check the Gerrit test account\n' >&2
  exit 1
fi
if ! awk '
  /^create_gerrit_change\(\)/ { in_fn=1 }
  /^run_verification_build\(\)/ { exit }
  in_fn { print }
' "$repo_root/scripts/integration-setup.sh" |
  grep -Fq -- 'ensure_gerrit_test_account_provisioned "$log"'
then
  printf 'verification change proof must provision/check the Gerrit test account\n' >&2
  exit 1
fi
if grep -Fq -- 'JENKINS_GERRIT_INTEGRATION_PASSWORD' "$repo_root/scripts/integration-setup.sh"; then
  printf 'integration helper must not require a password-backed jenkins-gerrit account\n' >&2
  exit 1
fi
if grep -Fq -- 'post_simulation_verified_vote' "$repo_root/scripts/integration-setup.sh"; then
  printf 'prove-integration must not post the Gerrit Verified vote directly\n' >&2
  exit 1
fi
if grep -Fq -- 'docker-gerrit' "$repo_root/scripts/integration-setup.sh"; then
  printf 'integration helper defaults must not use Docker-specific Gerrit names\n' >&2
  exit 1
fi
if grep -Fq -- 'docker exec "$(jenkins_container)" ssh' "$repo_root/scripts/integration-setup.sh"; then
  printf 'stream-events proof must not background a host-side docker exec listener\n' >&2
  exit 1
fi

missing_marker_calls="$tmp_dir/missing-marker-integration-calls.log"
rm -f "$host_dir/rendered/integration-validate-pass.env"
set +e
env \
  HARNESS_TEST_INTEGRATION_HELPER="$integration_helper" \
  HARNESS_TEST_INTEGRATION_CALLS="$missing_marker_calls" \
  HARNESS_ENV_FILE="$tmp_dir/harness.env" \
  "$repo_root/simulation/docker/simulate.sh" --env "$tmp_dir/harness.env" prove-integration \
  >"$tmp_dir/prove-missing-marker.out" 2>&1
missing_marker_rc=$?
set -e
[ "$missing_marker_rc" -ne 0 ] || {
  printf 'prove-integration unexpectedly succeeded without prior validate-integration\n' >&2
  exit 1
}
grep -Fq 'Missing successful validate-integration marker; run validate-integration first' "$tmp_dir/prove-missing-marker.out"
[ ! -s "$missing_marker_calls" ] || {
  printf 'prove-integration called integration without a prior validate marker\n' >&2
  sed -n '1,120p' "$missing_marker_calls" >&2
  exit 1
}

for old_command in render-config verify-state verify-integration check full-verify run-role-gate; do
  set +e
  "$repo_root/simulation/docker/simulate.sh" --env "$tmp_dir/harness.env" "$old_command" \
    >"$tmp_dir/old-$old_command.out" 2>&1
  old_rc=$?
  set -e
  [ "$old_rc" -ne 0 ] || {
    printf 'old Docker command unexpectedly succeeded: %s\n' "$old_command" >&2
    exit 1
  }
done

for old_command in configure-gerrit-ssh configure-agent-ssh configure-trigger verify-trigger verify-integration; do
  set +e
  "$repo_root/scripts/integration-setup.sh" \
    --gerrit-env "$runtime_dir/gerrit.env" \
    --jenkins-controller-env "$runtime_dir/jenkins-controller.env" \
    --jenkins-agent-env "$runtime_dir/jenkins-agent.env" \
    --integration-env "$runtime_dir/integration.env" \
    "$old_command" >"$tmp_dir/old-helper-$old_command.out" 2>&1
  old_rc=$?
  set -e
  [ "$old_rc" -ne 0 ] || {
    printf 'old integration helper command unexpectedly succeeded: %s\n' "$old_command" >&2
    exit 1
  }
done

failing_configure_calls="$tmp_dir/failing-configure-calls.log"
failing_configure_helper="$tmp_dir/failing-configure-integration-setup.sh"
cat >"$failing_configure_helper" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$HARNESS_TEST_INTEGRATION_CALLS"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --integration-env)
      printf '%s\n' "$2" >"$HARNESS_TEST_FAILING_ADAPTER_PATH"
      shift 2
      ;;
    *) shift ;;
  esac
done
case "$*" in
  *) exit 42 ;;
esac
SH
chmod +x "$failing_configure_helper"

set +e
env "${common_env[@]}" \
  HARNESS_TEST_INTEGRATION_HELPER="$failing_configure_helper" \
  HARNESS_TEST_INTEGRATION_CALLS="$failing_configure_calls" \
  HARNESS_TEST_FAILING_ADAPTER_PATH="$tmp_dir/failing-adapter.path" \
  "$repo_root/simulation/docker/simulate.sh" --env "$tmp_dir/harness.env" configure-integration \
  >"$tmp_dir/configure-failure.out" 2>&1
failing_configure_rc=$?
set -e

[ "$failing_configure_rc" -eq 42 ] || {
  printf 'Expected configure-integration failure rc 42, got %s\n' "$failing_configure_rc" >&2
  exit 1
}
grep -Fq -- '--yes configure-integration' "$failing_configure_calls"
[ ! -e "$(cat "$tmp_dir/failing-adapter.path")" ] || {
  printf 'Failed Docker integration helper left its invocation adapter behind\n' >&2
  exit 1
}
