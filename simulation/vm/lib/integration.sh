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

vm_integration_create_invocation_adapter() {
  local file role machine host prefix
  file="$(mktemp "$HARNESS_HOST_DIR/.integration-invocation.XXXXXX")" || return $?
  if ! install -m "$LF_MODE_PRIVATE_FILE" \
    "$HARNESS_RUNTIME_INPUT_DIR/integration.env" "$file"; then
    rm -f -- "$file"
    return 1
  fi
  for role in "${roles[@]}"; do
    machine="$(vm_ssh_role_machine "$role")"
    vm_libvirt_require_running "$machine" || { rm -f -- "$file"; return 1; }
    vm_ssh_verify_known_host "$machine" || { rm -f -- "$file"; return 1; }
    host="$(vm_ssh_machine_host "$machine")" || { rm -f -- "$file"; return 1; }
    prefix="$(vm_integration_target_prefix "$role")"
    set_env_file_value "$file" "${prefix}_SSH_HOST" "$host" || {
      rm -f -- "$file"
      return 1
    }
  done
  printf '%s\n' "$file"
}

vm_integration_require_roles_validated() {
  local role
  vm_set_verify_run_and_set || return $?
  for role in "${roles[@]}"; do
    vm_state_verify_role_checkpoint "$role" validated || return $?
  done
}

vm_integration_args() {
  local integration_env
  integration_env="${1:?integration invocation env required}"
  printf '%s\n' \
    --gerrit-env "$HARNESS_GERRIT_ENV_FILE" \
    --jenkins-controller-env "$HARNESS_JENKINS_CONTROLLER_ENV_FILE" \
    --jenkins-agent-env "$HARNESS_JENKINS_AGENT_ENV_FILE" \
    --integration-env "$integration_env"
}

vm_integration_run_helper() {
  local command_name helper adapter rc
  local -a args
  command_name="${1:?command required}"
  helper="$(vm_integration_helper)"
  [ -x "$helper" ] || die "Missing executable integration helper: $helper"
  adapter="$(vm_integration_create_invocation_adapter)" || return $?
  mapfile -t args < <(vm_integration_args "$adapter")
  rc=0
  "$helper" "${args[@]}" --yes "$command_name" || rc=$?
  rm -f -- "$adapter"
  return "$rc"
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
  vm_state_invalidate_integration_validation
  vm_integration_run_helper configure-integration || return $?
  vm_state_write_integration_checkpoint configure-integration
}

vm_integration_validate() {
  vm_integration_require_roles_validated || return $?
  vm_state_verify_integration_checkpoint configure-integration || return $?
  vm_integration_run_helper validate-integration || return $?
  vm_state_write_integration_checkpoint validate-integration
}

vm_integration_prove() {
  vm_integration_require_roles_validated || return $?
  vm_state_verify_integration_checkpoint validate-integration || return $?
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
  "set_id": $(json_quote "$HARNESS_SET_ID"),
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
