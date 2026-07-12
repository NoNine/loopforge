#!/usr/bin/env bash

vm_integration_helper() {
  printf '%s\n' "${HARNESS_TEST_INTEGRATION_HELPER:-$repo_root/scripts/integration-setup.sh}"
}

vm_integration_target_prefix() {
  case "${1:?role required}" in
    gerrit) printf 'INTEGRATION_GERRIT_TARGET\n' ;;
    jenkins-controller) printf 'INTEGRATION_JENKINS_CONTROLLER_TARGET\n' ;;
    jenkins-agent) printf 'INTEGRATION_JENKINS_AGENT_TARGET\n' ;;
    *) die "Unknown integration role: $1" ;;
  esac
}

vm_integration_render_role_envs() {
  set_env_file_value "$HARNESS_GERRIT_ENV_FILE" HARNESS_ENVIRONMENT gerrit
  set_env_file_value "$HARNESS_GERRIT_ENV_FILE" GERRIT_HOST "gerrit.$HARNESS_LDAP_DOMAIN"
  set_env_file_value "$HARNESS_GERRIT_ENV_FILE" GERRIT_CANONICAL_WEB_URL "http://gerrit.$HARNESS_LDAP_DOMAIN:8080/"
  set_env_file_value "$HARNESS_GERRIT_ENV_FILE" LDAP_URL "ldap://$HARNESS_LDAP_HOST:$HARNESS_LDAP_PORT"

  set_env_file_value "$HARNESS_JENKINS_CONTROLLER_ENV_FILE" HARNESS_ENVIRONMENT jenkins-controller
  set_env_file_value "$HARNESS_JENKINS_CONTROLLER_ENV_FILE" JENKINS_HOST "jenkins-controller.$HARNESS_LDAP_DOMAIN"
  set_env_file_value "$HARNESS_JENKINS_CONTROLLER_ENV_FILE" JENKINS_URL "http://jenkins-controller.$HARNESS_LDAP_DOMAIN:8080/"
  set_env_file_value "$HARNESS_JENKINS_CONTROLLER_ENV_FILE" LDAP_URL "ldap://$HARNESS_LDAP_HOST:$HARNESS_LDAP_PORT"

  set_env_file_value "$HARNESS_JENKINS_AGENT_ENV_FILE" HARNESS_ENVIRONMENT jenkins-agent
  set_env_file_value "$HARNESS_JENKINS_AGENT_ENV_FILE" JENKINS_AGENT_HOST "jenkins-agent.$HARNESS_LDAP_DOMAIN"
}

vm_integration_render_target_inventory() {
  local role machine host prefix
  for role in "${roles[@]}"; do
    machine="$(vm_ssh_role_machine "$role")"
    vm_libvirt_require_running "$machine" || return $?
    vm_ssh_verify_known_host "$machine" || return $?
    host="$(vm_ssh_machine_host "$machine")" || return $?
    prefix="$(vm_integration_target_prefix "$role")"
    set_env_file_value "$HARNESS_INTEGRATION_ENV_FILE" "${prefix}_SSH_HOST" "$host"
    set_env_file_value "$HARNESS_INTEGRATION_ENV_FILE" "${prefix}_SSH_PORT" 22
    set_env_file_value "$HARNESS_INTEGRATION_ENV_FILE" "${prefix}_SSH_USER" "$VM_OPERATOR_USER"
    set_env_file_value "$HARNESS_INTEGRATION_ENV_FILE" "${prefix}_SSH_IDENTITY_FILE" "$HARNESS_TARGET_SSH_IDENTITY_FILE"
    set_env_file_value "$HARNESS_INTEGRATION_ENV_FILE" "${prefix}_SSH_KNOWN_HOSTS_FILE" "$HARNESS_TARGET_SSH_KNOWN_HOSTS_FILE"
  done
}

vm_integration_render_inputs() {
  vm_integration_render_role_envs || return $?
  set_env_file_value "$HARNESS_INTEGRATION_ENV_FILE" INTEGRATION_MODE "$HARNESS_MODE"
  set_env_file_value "$HARNESS_INTEGRATION_ENV_FILE" INTEGRATION_STATE_DIR "$HARNESS_HOST_DIR/state/integration"
  set_env_file_value "$HARNESS_INTEGRATION_ENV_FILE" INTEGRATION_LOG_DIR "$HARNESS_INTEGRATION_LOG_DIR"
  set_env_file_value "$HARNESS_INTEGRATION_ENV_FILE" INTEGRATION_EVIDENCE_DIR "$HARNESS_INTEGRATION_EVIDENCE_DIR"
  if [ "$HARNESS_MODE" = vm-simulation ]; then
    set_env_file_value "$HARNESS_INTEGRATION_ENV_FILE" JENKINS_SHARED_STORAGE_PATH /data/jenkins-shared
    set_env_file_value "$HARNESS_INTEGRATION_ENV_FILE" INTEGRATION_GERRIT_ACL_MODE apply-direct
    set_env_file_value "$HARNESS_INTEGRATION_ENV_FILE" INTEGRATION_ALLOW_SIMULATION_DIRECT_ACL_APPLY 1
  fi
  vm_integration_render_target_inventory
}

vm_integration_require_roles_validated() {
  local role
  vm_set_verify_run_and_set || return $?
  for role in "${roles[@]}"; do
    vm_state_verify_role_checkpoint "$role" validated || return $?
  done
}

vm_integration_args() {
  printf '%s\n' \
    --gerrit-env "$HARNESS_GERRIT_ENV_FILE" \
    --jenkins-controller-env "$HARNESS_JENKINS_CONTROLLER_ENV_FILE" \
    --jenkins-agent-env "$HARNESS_JENKINS_AGENT_ENV_FILE" \
    --integration-env "$HARNESS_INTEGRATION_ENV_FILE"
}

vm_integration_run_helper() {
  local command_name helper
  local -a args
  command_name="${1:?command required}"
  helper="$(vm_integration_helper)"
  [ -x "$helper" ] || die "Missing executable integration helper: $helper"
  mapfile -t args < <(vm_integration_args)
  "$helper" "${args[@]}" --yes "$command_name"
}

vm_integration_assert_no_placeholder_success() {
  local log
  log="${1:?log required}"
  ! grep -Eiq \
    'dummy success|operation-plan-only|planned-checks-only|placeholder success|would validate|would run|target-local observable|proof[[:space:]]*=[[:space:]]*modeled|real_execution[[:space:]]*=[[:space:]]*false' \
    "$log"
}

vm_integration_assert_no_contradictory_failure() {
  local log
  log="${1:?log required}"
  ! grep -Eiq \
    '(^|[[:space:]])(ERROR|FAILED|Timed out|Traceback|Exception)(:|[[:space:]])|BLOCKED:' \
    "$log"
}

vm_integration_failure_status() {
  local log
  log="${1:?log required}"
  if grep -Eiq 'Missing .* marker|Stale .* marker|BLOCKED:' "$log"; then
    printf 'blocked\n'
  else
    printf 'fail\n'
  fi
}

vm_integration_configure() {
  vm_integration_require_roles_validated || return $?
  vm_integration_render_inputs || return $?
  vm_state_invalidate_integration_validation
  vm_integration_run_helper configure-integration || return $?
  vm_state_write_integration_checkpoint configure-integration
}

vm_integration_validate() {
  vm_integration_require_roles_validated || return $?
  vm_state_verify_integration_checkpoint configure-integration || return $?
  vm_integration_render_inputs || return $?
  vm_integration_run_helper validate-integration || return $?
  vm_state_write_integration_checkpoint validate-integration
}

vm_integration_prove() {
  vm_integration_require_roles_validated || return $?
  vm_state_verify_integration_checkpoint validate-integration || return $?
  vm_integration_render_inputs || return $?
  vm_integration_run_helper prove-integration
}

vm_write_integration_evidence() {
  local checkpoint status log_ref message file
  checkpoint="${1:?checkpoint required}"
  status="${2:?status required}"
  log_ref="${3:?bounded log required}"
  message="${4:-}"
  mkdir -p "$HARNESS_EVIDENCE_DIR"
  file="$(evidence_record_path "$HARNESS_EVIDENCE_DIR" "$checkpoint" integration)"
  cat >"$file" <<EOF
{
  "verification_mode": "vm-simulation",
  "timestamp": $(json_quote "$(iso_timestamp_utc)"),
  "package_version": "gerrit-jenkins-setup",
  "helper_command_version": "simulation/vm/simulate.sh",
  "role_or_environment": "integration",
  "checkpoint": $(json_quote "$checkpoint"),
  "command": $(json_quote "$checkpoint"),
  "status": $(json_quote "$status"),
  "run_id": $(json_quote "$HARNESS_RUN_ID"),
  "vm_set_id": $(json_quote "$LOOPFORGE_VM_SET_ID"),
  "gerrit_target": $(json_quote "gerrit.$HARNESS_LDAP_DOMAIN"),
  "jenkins_controller_target": $(json_quote "jenkins-controller.$HARNESS_LDAP_DOMAIN"),
  "jenkins_agent_target": $(json_quote "jenkins-agent.$HARNESS_LDAP_DOMAIN"),
  "integration_evidence_dir": $(json_quote "$HARNESS_INTEGRATION_EVIDENCE_DIR"),
  "bounded_log": $(json_quote "$log_ref"),
  "message": $(json_quote "$message"),
  "redaction": "secrets-not-recorded"
}
EOF
  chmod 0600 "$file"
  printf '%s\n' "$file"
}
