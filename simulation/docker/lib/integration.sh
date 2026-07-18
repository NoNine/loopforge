#!/usr/bin/env bash

integration_args=()

__docker_integration_refresh_args() {
  local integration_env
  integration_env="${1:?integration invocation env required}"
  integration_args=(
    --gerrit-env "$HARNESS_GERRIT_ENV_FILE"
    --jenkins-controller-env "$HARNESS_JENKINS_CONTROLLER_ENV_FILE"
    --jenkins-agent-env "$HARNESS_JENKINS_AGENT_ENV_FILE"
    --integration-env "$integration_env"
  )
}

__docker_integration_create_invocation_adapter() {
  local file
  file="$(mktemp "$HARNESS_HOST_DIR/.integration-invocation.XXXXXX")" || return $?
  install -m "$LF_MODE_PRIVATE_FILE" "$HARNESS_RUNTIME_INPUT_DIR/integration.env" \
    "$file" || { rm -f -- "$file"; return 1; }
  set_env_file_value "$file" INTEGRATION_GERRIT_TARGET_SSH_HOST 127.0.0.1
  set_env_file_value "$file" INTEGRATION_JENKINS_CONTROLLER_TARGET_SSH_HOST 127.0.0.1
  set_env_file_value "$file" INTEGRATION_JENKINS_AGENT_TARGET_SSH_HOST 127.0.0.1
  printf '%s\n' "$file"
}

__docker_integration_run_helper() {
  local command_name log adapter rc
  command_name="${1:?integration command required}"
  log="${2:?bounded log required}"
  adapter="$(__docker_integration_create_invocation_adapter)" || return $?
  __docker_integration_refresh_args "$adapter"
  rc=0
  "$integration_helper" "${integration_args[@]}" --yes "$command_name" \
    >"$log" 2>&1 || rc=$?
  rm -f -- "$adapter"
  return "$rc"
}

__docker_integration_write_blocked_evidence() {
  local checkpoint log reason
  checkpoint="${1:?checkpoint required}"
  log="${2:?log required}"
  reason="${3:?reason required}"
  write_evidence "$checkpoint" integration blocked "scripts/integration-setup.sh" "$log" "$reason" >/dev/null
}

__docker_integration_validate_marker_path() {
  printf '%s/rendered/integration-validate-pass.env\n' "$HARNESS_HOST_DIR"
}

__docker_integration_write_validate_marker() {
  local marker
  marker="$(__docker_integration_validate_marker_path)"
  write_checkpoint_marker \
    "$marker" \
    "$HARNESS_MODE" \
    docker \
    "$HARNESS_SET_ID" \
    "$HARNESS_RUN_ID" \
    "$HARNESS_PROJECT_NAME" \
    "$HARNESS_RUNTIME_ENV" \
    "$HARNESS_SOURCE_INPUT_DIR" \
    "$HARNESS_RUNTIME_INPUT_DIR"
}

__docker_integration_require_validate_marker() {
  local marker
  marker="$(__docker_integration_validate_marker_path)"
  [ -f "$marker" ] || die "Missing successful validate-integration marker; run validate-integration first"
  verify_checkpoint_marker \
    "$marker" \
    "$HARNESS_MODE" \
    docker \
    "$HARNESS_SET_ID" \
    "$HARNESS_RUN_ID" \
    "$HARNESS_PROJECT_NAME" \
    "$HARNESS_RUNTIME_ENV" \
    "$HARNESS_SOURCE_INPUT_DIR" \
    "$HARNESS_RUNTIME_INPUT_DIR" \
    "Validate-integration marker"
}

docker_integration_configure() {
  local log rc evidence
  bootstrap_harness_env
  docker_set_require_runtime || return $?
  require_docker_effective_inputs

  [ -x "$integration_helper" ] || die "Missing executable integration helper: $integration_helper"
  log="$(bounded_log_path configure-integration)"
  __docker_integration_run_helper configure-integration "$log" || rc=$?
  rc="${rc:-0}"
  if [ "$rc" -eq 0 ]; then
    if ! assert_no_forbidden_success_markers "$log"; then
      evidence="$(write_evidence configure-integration integration fail "simulate.sh configure-integration" "$log" "Forbidden success marker found in integration configuration log")"
      print_command_failure configure-integration "" failed "$log" "$evidence"
      return 1
    fi
    evidence="$(write_evidence configure-integration integration pass "simulate.sh configure-integration" "$log" "Shared integration helper completed cross-role setup/configuration")"
    print_command_summary configure-integration "" ok
    return 0
  fi

  evidence="$(write_evidence configure-integration integration fail "simulate.sh configure-integration" "$log" "Shared integration helper failed cross-role setup/configuration")"
  print_command_failure configure-integration "" failed "$log" "$evidence"
  return "$rc"
}

docker_integration_validate() {
  local log rc evidence
  bootstrap_harness_env
  docker_set_require_runtime || return $?
  require_docker_effective_inputs

  [ -x "$integration_helper" ] || die "Missing executable integration helper: $integration_helper"
  log="$(bounded_log_path validate-integration)"
  __docker_integration_run_helper validate-integration "$log" || rc=$?
  rc="${rc:-0}"
  if [ "$rc" -eq 0 ]; then
    if ! assert_no_forbidden_success_markers "$log"; then
      evidence="$(write_evidence validate-integration integration fail "simulate.sh validate-integration" "$log" "Forbidden success marker found in integration validation log")"
      print_command_failure validate-integration "" failed "$log" "$evidence"
      return 1
    fi
    evidence="$(write_evidence validate-integration integration pass "simulate.sh validate-integration" "$log" "Shared integration helper validated cross-role readiness without end-to-end proof")"
    __docker_integration_write_validate_marker
    print_command_summary validate-integration "" ok
    return 0
  fi

  __docker_integration_write_blocked_evidence jenkins-to-gerrit-ssh "$log" "Blocked: shared integration helper has not implemented real Jenkins-to-Gerrit SSH validation"
  __docker_integration_write_blocked_evidence agent-connection "$log" "Blocked: shared integration helper has not implemented real Jenkins-to-agent readiness validation"
  evidence="$(write_evidence validate-integration integration blocked "simulate.sh validate-integration" "$log" "Shared integration helper reported blocked cross-role validation; Docker simulation cannot claim readiness")"
  print_command_summary validate-integration "" blocked
  return "$rc"
}

docker_integration_prove() {
  local log rc evidence
  bootstrap_harness_env
  docker_set_require_runtime || return $?
  require_docker_effective_inputs
  __docker_integration_require_validate_marker

  [ -x "$integration_helper" ] || die "Missing executable integration helper: $integration_helper"
  log="$(bounded_log_path prove-integration)"
  __docker_integration_run_helper prove-integration "$log" || rc=$?
  rc="${rc:-0}"
  if [ "$rc" -eq 0 ]; then
    if ! assert_no_forbidden_success_markers "$log"; then
      evidence="$(write_evidence prove-integration integration fail "simulate.sh prove-integration" "$log" "Forbidden success marker found in integration proof log")"
      print_command_failure prove-integration "" failed "$log" "$evidence"
      return 1
    fi
    evidence="$(write_evidence prove-integration integration pass "simulate.sh prove-integration" "$log" "Shared integration helper proved disposable change, Gerrit event receipt, Jenkins job scheduling, agent execution, and Verified +1")"
    print_command_summary prove-integration "" ok
    return 0
  fi

  __docker_integration_write_blocked_evidence job-execution "$log" "Blocked: shared integration helper has not implemented real disposable Jenkins job execution proof"
  __docker_integration_write_blocked_evidence verified-vote "$log" "Blocked: shared integration helper has not implemented real Gerrit Verified +1 vote proof"
  evidence="$(write_evidence prove-integration integration blocked "simulate.sh prove-integration" "$log" "Shared integration helper reported blocked proof; Docker simulation cannot claim end-to-end success")"
  print_command_summary prove-integration "" blocked
  return "$rc"
}
