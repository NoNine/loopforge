#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

. "$repo_root/simulation/lib/common.sh"
. "$repo_root/simulation/lib/quote.sh"
. "$repo_root/simulation/lib/roles.sh"
. "$repo_root/simulation/lib/artifacts.sh"
. "$repo_root/simulation/lib/identity.sh"
. "$repo_root/simulation/lib/state.sh"
. "$repo_root/simulation/lib/permissions.sh"
. "$repo_root/simulation/lib/logs.sh"
. "$repo_root/simulation/lib/evidence.sh"
. "$repo_root/simulation/vm/lib/paths.sh"
. "$repo_root/simulation/vm/lib/state.sh"
. "$repo_root/simulation/vm/lib/roles.sh"
. "$repo_root/simulation/vm/lib/lifecycle.sh"

HARNESS_MODE=vm-simulation
HARNESS_RUN_ID=m7-test
HARNESS_SET_ID=m7-set
HARNESS_PROJECT_NAME=loopforge-vm-m7-set
HARNESS_GENERATED_RUN_DIR="$tmp_dir/run"
HARNESS_HOST_DIR="$HARNESS_GENERATED_RUN_DIR/host"
HARNESS_TARGET_DIR="$HARNESS_GENERATED_RUN_DIR/target"
HARNESS_RUNTIME_INPUT_DIR="$HARNESS_HOST_DIR/runtime-inputs"
HARNESS_EVIDENCE_DIR="$HARNESS_HOST_DIR/evidence/harness"
HARNESS_LOG_DIR="$HARNESS_HOST_DIR/logs/harness"
HARNESS_ROLE_STATE_DIR="$HARNESS_HOST_DIR/state/roles"
HARNESS_RUNTIME_ENV="$HARNESS_HOST_DIR/rendered/harness.runtime.env"
HARNESS_PUBLIC_INTERNET_FALLBACK_LABEL=simulation-only
HARNESS_LDAP_DOMAIN=example.test
HARNESS_LDAP_HOST=ldap.example.test
HARNESS_LDAP_PORT=389
HARNESS_UBUNTU_BASELINE_RELEASE=24.04
HARNESS_UBUNTU_BASELINE_CODENAME=noble
HARNESS_JAVA_BASELINE=21
HARNESS_GERRIT_BASELINE=3.13.6
HARNESS_JENKINS_BASELINE=2.555.3
HARNESS_JENKINS_PLUGIN_MANAGER_BASELINE=2.15.0
VM_OPERATOR_USER=ci-operator
HARNESS_LDAP_BIND_PASSWORD='m7-test-secret'
roles=(gerrit jenkins-controller jenkins-agent)
vm_machines=(bundle-factory ldap gerrit jenkins-controller jenkins-agent)
calls="$tmp_dir/calls.log"
mkdir -p "$HARNESS_RUNTIME_INPUT_DIR" "$HARNESS_EVIDENCE_DIR" "$HARNESS_LOG_DIR" \
  "$HARNESS_HOST_DIR/rendered" "$HARNESS_TARGET_DIR/evidence" \
  "$HARNESS_TARGET_DIR/logs"
for role in "${roles[@]}"; do
  mkdir -p "$HARNESS_TARGET_DIR/evidence/$role" "$HARNESS_TARGET_DIR/logs/$role"
done
printf 'runtime=m7\n' >"$HARNESS_RUNTIME_ENV"
for input in harness gerrit jenkins-controller jenkins-agent integration; do
  printf 'input=%s\n' "$input" >"$HARNESS_RUNTIME_INPUT_DIR/$input.env"
done

vm_config_load_runtime() { :; }
vm_set_verify_run_and_set() { :; }
vm_artifacts_stage_role_env() { printf 'stage-env %s %s\n' "$1" "$2" >>"$calls"; }
vm_artifacts_verify_staged_role() {
  if [ -f "$tmp_dir/fail-staged-$1" ]; then
    printf 'missing_staged_artifacts role=%s\n' "$1"
    return 1
  fi
  printf 'staged-ok %s\n' "$1" >>"$calls"
}
vm_artifacts_target_payload() {
  printf '/var/lib/loopforge/staging/%s\n' "$(bundle_payload_dir_for_role "$1")"
}
vm_ssh_role_machine() { printf '%s\n' "$1"; }
vm_path_guest_role_helpers_root() { printf '/home/ci-operator/loopforge\n'; }
vm_path_guest_role_helper() { role_helper_path_for_operator ci-operator "$1"; }
vm_path_guest_input_root() { printf '/home/ci-operator/loopforge-inputs\n'; }
vm_path_guest_role_env() { printf '/home/ci-operator/loopforge-inputs/%s.env\n' "$1"; }
vm_path_bounded_log() { bounded_log_path_in_dir "$HARNESS_LOG_DIR" "$1"; }
vm_ssh_boot_id() { printf 'boot-%s\n' "$1"; }
vm_ssh_run_machine() {
  local machine script
  machine="$1"
  script="$2"
  printf 'ssh machine=%s script=%s\n' "$machine" "$script" >>"$calls"
  case "$script" in
    find\ /var/lib/loopforge/evidence*)
      printf '/var/lib/loopforge/evidence/%s-readiness-20260710T000000Z.json\n' "$machine"
      ;;
  esac
}
vm_ssh_run_machine_with_ldap_password() {
  printf 'ldap machine=%s script=%s\n' "$1" "$2" >>"$calls"
  vm_ssh_run_machine "$1" "$2"
}
vm_ssh_copy_file_from_machine() {
  local machine source dest
  machine="$1"
  source="$2"
  dest="$3"
  mkdir -p "$(dirname "$dest")"
  case "$source" in
    *.json)
      cat >"$dest" <<EOF
{"verification_mode":"vm-simulation","status":"pass","bounded_log_references":"/var/log/loopforge/$machine.log"}
EOF
      ;;
    *) printf 'bounded role log\n' >"$dest" ;;
  esac
  chmod 0600 "$dest"
}
vm_libvirt_require_running() { :; }
vm_ssh_reboot_machine() { printf 'reboot %s\n' "$1" >>"$calls"; }

vm_roles_assert_reboot_recovery gerrit
vm_roles_assert_reboot_recovery jenkins-controller
grep -Fq 'exec 3<>"/dev/tcp/$1/$2"' "$calls"

vm_cmd_configure_role "" >"$tmp_dir/configure.out"
grep -Fxq 'configure-role[gerrit]: ok' "$tmp_dir/configure.out"
grep -Fxq 'configure-role[jenkins-controller]: ok' "$tmp_dir/configure.out"
grep -Fxq 'configure-role[jenkins-agent]: ok' "$tmp_dir/configure.out"
grep -Fq 'gerrit-setup.sh' "$calls"
grep -Fq 'jenkins-controller-setup.sh' "$calls"
grep -Fq 'jenkins-agent-setup.sh' "$calls"
grep -Fq ' configure-service' "$calls"
grep -Fq ' install-plugins' "$calls"
grep -Fq ' configure-jcasc' "$calls"
grep -Fq ' configure-runtime' "$calls"
! grep -Fq 'groupadd --gid' "$calls"
! grep -Fq 'useradd --uid' "$calls"
! grep -Fq 'vm_roles_prepare_runtime_identity' "$repo_root/simulation/vm/lib/roles.sh"
[ "$(grep -c '^ldap machine=' "$calls")" -eq 6 ]
! grep -Fq "$HARNESS_LDAP_BIND_PASSWORD" "$calls"

for role in "${roles[@]}"; do
  marker="$(vm_path_role_checkpoint_marker "$role" configured)"
  [ -f "$marker" ]
  [ "$(marker_value "$marker" boot_id)" = "boot-$role" ]
done

vm_cmd_validate_role "" >"$tmp_dir/validate.out"
for role in "${roles[@]}"; do
  grep -Fxq "validate-role[$role]: ok" "$tmp_dir/validate.out"
  [ -f "$(vm_path_role_checkpoint_marker "$role" validated)" ]
  find "$HARNESS_TARGET_DIR/evidence/$role" -type f -name '*.json' | grep -q .
  find "$HARNESS_TARGET_DIR/logs/$role" -type f | grep -q .
  find "$HARNESS_EVIDENCE_DIR" -type f -name '*.host.json' | grep -q .
done

touch "$tmp_dir/fail-staged-gerrit"
if vm_cmd_configure_role gerrit >"$tmp_dir/blocked.out" 2>&1; then
  printf 'configure-role must fail closed when staged artifacts are missing\n' >&2
  exit 1
fi
grep -Fq 'configure-role[gerrit]: blocked' "$tmp_dir/blocked.out"
rm -f "$tmp_dir/fail-staged-gerrit"

vm_cmd_reboot "" 1 >"$tmp_dir/reboot.out"
grep -Fxq 'reboot[all]: ok' "$tmp_dir/reboot.out"
[ "$(grep -c '^reboot ' "$calls")" -eq 5 ]
for role in "${roles[@]}"; do
  [ ! -e "$(vm_path_role_checkpoint_marker "$role" validated)" ]
  [ -e "$(vm_path_role_checkpoint_marker "$role" configured)" ]
done
reboot_evidence="$(find "$HARNESS_EVIDENCE_DIR" -name 'reboot-harness-*.json' | sort | tail -1)"
grep -Fq '"boot_id_change": "pass"' "$reboot_evidence"
grep -Fq '"selected_vm_targets": "bundle-factory ldap gerrit jenkins-controller jenkins-agent"' "$reboot_evidence"

vm_cmd_validate_role gerrit >"$tmp_dir/post-reboot-validate.out"
grep -Fxq 'validate-role[gerrit]: ok' "$tmp_dir/post-reboot-validate.out"
[ -e "$(vm_path_role_checkpoint_marker gerrit validated)" ]

grep -Fq 'setsid -f $(shell_quote "$GERRIT_SITE_PATH/bin/gerrit.sh") run' \
  "$repo_root/scripts/gerrit-setup.sh"
if grep -Fq 'run_as_gerrit_runtime "$(shell_quote "$GERRIT_SITE_PATH/bin/gerrit.sh") run' \
  "$repo_root/scripts/gerrit-setup.sh"; then
  printf 'Gerrit runtime startup must not leave the helper waiting on a foreground child\n' >&2
  exit 1
fi

vm_set_verify_run_and_set() { die "forced role phase failure"; }
if vm_cmd_configure_role gerrit >"$tmp_dir/configure-die.out" 2>&1; then
  printf 'configure-role must report nested die failures\n' >&2
  exit 1
fi
grep -Fq 'configure-role[gerrit]:' "$tmp_dir/configure-die.out"
grep -Eq '^log=.*/configure-role-gerrit-[0-9]{8}T[0-9]{6}Z\.log$' \
  "$tmp_dir/configure-die.out"
grep -Eq '^evidence=.*/configure-role-gerrit-[0-9]{8}T[0-9]{6}Z\.json$' \
  "$tmp_dir/configure-die.out"
configure_die_log="$(sed -n 's/^log=//p' "$tmp_dir/configure-die.out")"
grep -Fq 'ERROR: forced role phase failure' "$configure_die_log"
