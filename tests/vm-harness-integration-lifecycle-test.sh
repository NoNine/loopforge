#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

. "$repo_root/simulation/lib/common.sh"
. "$repo_root/simulation/lib/quote.sh"
. "$repo_root/simulation/lib/roles.sh"
. "$repo_root/simulation/lib/env.sh"
. "$repo_root/simulation/lib/identity.sh"
. "$repo_root/simulation/lib/state.sh"
. "$repo_root/simulation/lib/permissions.sh"
. "$repo_root/simulation/lib/logs.sh"
. "$repo_root/simulation/lib/evidence.sh"
. "$repo_root/simulation/vm/lib/paths.sh"
. "$repo_root/simulation/vm/lib/state.sh"
. "$repo_root/simulation/vm/lib/integration.sh"
. "$repo_root/simulation/vm/lib/lifecycle.sh"

HARNESS_MODE=vm-simulation
HARNESS_RUN_ID=m8-test
HARNESS_SET_ID=m8-set
HARNESS_PROJECT_NAME=loopforge-vm-m8-set
HARNESS_GENERATED_RUN_DIR="$tmp_dir/run"
HARNESS_HOST_DIR="$HARNESS_GENERATED_RUN_DIR/host"
HARNESS_TARGET_DIR="$HARNESS_GENERATED_RUN_DIR/target"
HARNESS_SOURCE_INPUT_DIR="$HARNESS_HOST_DIR/source-inputs"
HARNESS_RUNTIME_INPUT_DIR="$HARNESS_HOST_DIR/runtime-inputs"
HARNESS_EVIDENCE_DIR="$HARNESS_HOST_DIR/evidence/harness"
HARNESS_LOG_DIR="$HARNESS_HOST_DIR/logs/harness"
HARNESS_INTEGRATION_EVIDENCE_DIR="$HARNESS_HOST_DIR/evidence/integration"
HARNESS_INTEGRATION_LOG_DIR="$HARNESS_HOST_DIR/logs/integration"
HARNESS_ROLE_STATE_DIR="$HARNESS_HOST_DIR/state/roles"
HARNESS_RUNTIME_ENV="$HARNESS_HOST_DIR/rendered/harness.runtime.env"
HARNESS_GERRIT_ENV_FILE="$HARNESS_RUNTIME_INPUT_DIR/gerrit.env"
HARNESS_JENKINS_CONTROLLER_ENV_FILE="$HARNESS_RUNTIME_INPUT_DIR/jenkins-controller.env"
HARNESS_JENKINS_AGENT_ENV_FILE="$HARNESS_RUNTIME_INPUT_DIR/jenkins-agent.env"
HARNESS_INTEGRATION_ENV_FILE="$HARNESS_RUNTIME_INPUT_DIR/integration.env"
HARNESS_TARGET_SSH_IDENTITY_FILE="$HARNESS_HOST_DIR/target-ssh/ci-operator"
HARNESS_TARGET_SSH_KNOWN_HOSTS_FILE="$HARNESS_HOST_DIR/target-ssh/known_hosts"
HARNESS_LDAP_DOMAIN=example.test
HARNESS_LDAP_HOST=ldap.example.test
HARNESS_LDAP_PORT=389
VM_OPERATOR_USER=ci-operator
roles=(gerrit jenkins-controller jenkins-agent)
calls="$tmp_dir/integration-calls.log"

mkdir -p "$HARNESS_SOURCE_INPUT_DIR" "$HARNESS_RUNTIME_INPUT_DIR" "$HARNESS_EVIDENCE_DIR" \
  "$HARNESS_LOG_DIR" "$HARNESS_INTEGRATION_EVIDENCE_DIR" \
  "$HARNESS_INTEGRATION_LOG_DIR" "$HARNESS_HOST_DIR/rendered" \
  "$HARNESS_HOST_DIR/target-ssh"
printf 'runtime=m8\n' >"$HARNESS_RUNTIME_ENV"
printf 'input=harness\n' >"$HARNESS_RUNTIME_INPUT_DIR/harness.env"
printf 'identity\n' >"$HARNESS_TARGET_SSH_IDENTITY_FILE"
printf 'known-hosts\n' >"$HARNESS_TARGET_SSH_KNOWN_HOSTS_FILE"
chmod 0600 "$HARNESS_TARGET_SSH_IDENTITY_FILE" "$HARNESS_TARGET_SSH_KNOWN_HOSTS_FILE"

cat >"$HARNESS_GERRIT_ENV_FILE" <<'EOF'
SENTINEL=runtime-gerrit
GERRIT_HOST=stale-gerrit
GERRIT_HTTP_PORT=8080
GERRIT_SSH_PORT=29418
EOF
cat >"$HARNESS_JENKINS_CONTROLLER_ENV_FILE" <<'EOF'
SENTINEL=runtime-controller
JENKINS_HOST=stale-controller
JENKINS_URL=http://stale-controller:8080/
JENKINS_HTTP_PORT=8080
JENKINS_RUNTIME_UID=61020
JENKINS_RUNTIME_GID=61020
EOF
cat >"$HARNESS_JENKINS_AGENT_ENV_FILE" <<'EOF'
SENTINEL=runtime-agent
JENKINS_AGENT_HOST=stale-agent
JENKINS_AGENT_SSH_PORT=22
EOF
cat >"$HARNESS_INTEGRATION_ENV_FILE" <<'EOF'
SENTINEL=runtime-integration
JENKINS_SHARED_GROUP=jenkins-share
JENKINS_SHARED_GROUP_GID=61040
JENKINS_SHARED_STORAGE_PATH=/data/jenkins-shared
EOF
chmod 0600 "$HARNESS_RUNTIME_INPUT_DIR"/*.env
cp "$HARNESS_RUNTIME_INPUT_DIR"/*.env "$HARNESS_SOURCE_INPUT_DIR/"
chmod 0600 "$HARNESS_SOURCE_INPUT_DIR"/*.env

helper="$tmp_dir/integration-setup.sh"
cat >"$helper" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$HARNESS_TEST_INTEGRATION_CALLS"
integration_env=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --integration-env) integration_env="$2"; shift 2 ;;
    *) shift ;;
  esac
done
[ -n "$integration_env" ]
printf '%s\n' "$integration_env" >"$HARNESS_TEST_ADAPTER_PATH"
cp "$integration_env" "$HARNESS_TEST_ADAPTER_COPY"
[ "${HARNESS_TEST_INTEGRATION_FAIL:-0}" != 1 ] || exit 23
case "$*" in
  *) printf 'status=pass\n' ;;
esac
SH
chmod +x "$helper"

vm_config_load_runtime() { :; }
vm_state_require_effective_inputs() { :; }
vm_set_verify_run_and_set() { :; }
vm_libvirt_require_running() { :; }
vm_ssh_verify_known_host() { :; }
vm_ssh_role_machine() { printf '%s\n' "$1"; }
vm_ssh_machine_host() {
  case "$1" in
    gerrit) printf '192.0.2.10\n' ;;
    jenkins-controller) printf '192.0.2.11\n' ;;
    jenkins-agent) printf '192.0.2.12\n' ;;
    *) return 1 ;;
  esac
}
vm_path_bounded_log() { bounded_log_path_in_dir "$HARNESS_LOG_DIR" "$1"; }

for role in "${roles[@]}"; do
  vm_state_write_role_checkpoint "$role" validated "boot-$role"
done

if (
  HARNESS_TEST_INTEGRATION_HELPER="$helper"
  HARNESS_TEST_INTEGRATION_CALLS="$calls"
  export HARNESS_TEST_INTEGRATION_HELPER HARNESS_TEST_INTEGRATION_CALLS
  vm_cmd_prove_integration >"$tmp_dir/prove-before-validate.out" 2>&1
); then
  printf 'prove-integration must fail before validate-integration marker exists\n' >&2
  exit 1
fi
[ ! -s "$calls" ] || {
  printf 'prove-integration called helper without validation marker\n' >&2
  exit 1
}

HARNESS_TEST_INTEGRATION_HELPER="$helper" \
  HARNESS_TEST_INTEGRATION_CALLS="$calls" \
  HARNESS_TEST_ADAPTER_PATH="$tmp_dir/adapter.path" \
  HARNESS_TEST_ADAPTER_COPY="$tmp_dir/adapter.env" \
  vm_cmd_configure_integration >"$tmp_dir/configure.out"
grep -Fxq 'configure-integration: ok' "$tmp_dir/configure.out"
grep -Fq -- "--gerrit-env $HARNESS_GERRIT_ENV_FILE" "$calls"
grep -Fq -- "--jenkins-controller-env $HARNESS_JENKINS_CONTROLLER_ENV_FILE" "$calls"
grep -Fq -- "--jenkins-agent-env $HARNESS_JENKINS_AGENT_ENV_FILE" "$calls"
grep -Fq -- '--yes configure-integration' "$calls"
[ -f "$(vm_path_integration_checkpoint_marker configure-integration)" ]

adapter_path="$(cat "$tmp_dir/adapter.path")"
[ ! -e "$adapter_path" ]
grep -Fq 'INTEGRATION_GERRIT_TARGET_SSH_HOST=192.0.2.10' "$tmp_dir/adapter.env"
grep -Fq 'INTEGRATION_JENKINS_CONTROLLER_TARGET_SSH_HOST=192.0.2.11' "$tmp_dir/adapter.env"
grep -Fq 'INTEGRATION_JENKINS_AGENT_TARGET_SSH_HOST=192.0.2.12' "$tmp_dir/adapter.env"
grep -Fq 'JENKINS_SHARED_STORAGE_PATH=/data/jenkins-shared' "$tmp_dir/adapter.env"
grep -Fq 'SENTINEL=runtime-integration' "$tmp_dir/adapter.env"
grep -Fq 'GERRIT_HOST=stale-gerrit' "$HARNESS_RUNTIME_INPUT_DIR/gerrit.env"
[ ! -e "$HARNESS_HOST_DIR/rendered/integration-inputs" ]

HARNESS_TEST_INTEGRATION_HELPER="$helper" \
  HARNESS_TEST_INTEGRATION_CALLS="$calls" \
  HARNESS_TEST_ADAPTER_PATH="$tmp_dir/adapter.path" \
  HARNESS_TEST_ADAPTER_COPY="$tmp_dir/adapter.env" \
  vm_cmd_validate_integration >"$tmp_dir/validate.out"
grep -Fxq 'validate-integration: ok' "$tmp_dir/validate.out"
grep -Fq -- '--yes validate-integration' "$calls"
[ -f "$(vm_path_integration_checkpoint_marker validate-integration)" ]

HARNESS_TEST_INTEGRATION_HELPER="$helper" \
  HARNESS_TEST_INTEGRATION_CALLS="$calls" \
  HARNESS_TEST_ADAPTER_PATH="$tmp_dir/adapter.path" \
  HARNESS_TEST_ADAPTER_COPY="$tmp_dir/adapter.env" \
  vm_cmd_prove_integration >"$tmp_dir/prove.out"
grep -Fxq 'prove-integration: ok' "$tmp_dir/prove.out"
grep -Fq -- '--yes prove-integration' "$calls"

find "$HARNESS_EVIDENCE_DIR" -name 'configure-integration-integration-*.json' | grep -q .
find "$HARNESS_EVIDENCE_DIR" -name 'validate-integration-integration-*.json' | grep -q .
find "$HARNESS_EVIDENCE_DIR" -name 'prove-integration-integration-*.json' | grep -q .

if HARNESS_TEST_INTEGRATION_HELPER="$helper" \
  HARNESS_TEST_INTEGRATION_CALLS="$calls" \
  HARNESS_TEST_ADAPTER_PATH="$tmp_dir/failing-adapter.path" \
  HARNESS_TEST_ADAPTER_COPY="$tmp_dir/failing-adapter.env" \
  HARNESS_TEST_INTEGRATION_FAIL=1 \
  vm_cmd_configure_integration >"$tmp_dir/configure-helper-fail.out" 2>&1; then
  printf 'configure-integration must fail when the helper fails\n' >&2
  exit 1
fi
[ ! -e "$(cat "$tmp_dir/failing-adapter.path")" ] || {
  printf 'Failed integration helper left its private invocation adapter behind\n' >&2
  exit 1
}

vm_set_verify_run_and_set() { die "forced integration phase failure"; }
if HARNESS_TEST_INTEGRATION_HELPER="$helper" \
  HARNESS_TEST_INTEGRATION_CALLS="$calls" \
  vm_cmd_configure_integration >"$tmp_dir/configure-die.out" 2>&1; then
  printf 'configure-integration must report nested die failures\n' >&2
  exit 1
fi
grep -Fq 'configure-integration: fail' "$tmp_dir/configure-die.out"
grep -Eq '^log=.*/configure-integration-[0-9]{8}T[0-9]{6}Z\.log$' \
  "$tmp_dir/configure-die.out"
grep -Eq '^evidence=.*/configure-integration-integration-[0-9]{8}T[0-9]{6}Z\.json$' \
  "$tmp_dir/configure-die.out"
configure_die_log="$(sed -n 's/^log=//p' "$tmp_dir/configure-die.out")"
grep -Fq 'ERROR: forced integration phase failure' "$configure_die_log"
