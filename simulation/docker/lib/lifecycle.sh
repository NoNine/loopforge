#!/usr/bin/env bash

__docker_cmd_test_stub_role() {
  local command_name role
  command_name="${1:?command required}"
  role="${2:?role required}"
  [ -n "${HARNESS_TEST_STUB_ROLE_COMMANDS:-}" ] || return 1
  mkdir -p "$(dirname "$HARNESS_TEST_STUB_ROLE_COMMANDS")" "$HARNESS_LOG_DIR"
  printf '%s %s\n' "$command_name" "$role" >>"$HARNESS_TEST_STUB_ROLE_COMMANDS"
  if [ "${HARNESS_TEST_STUB_ROLE_FAIL:-}" = "$role" ] ||
    [ "${HARNESS_TEST_STUB_ROLE_FAIL:-}" = "$command_name:$role" ]; then
    print_command_failure "$command_name" "$role" failed "$HARNESS_LOG_DIR/test-stub-$command_name-$role.log" test-stub-fail
    return 9
  fi
  print_command_summary "$command_name" "$role" ok
  return 0
}

__docker_cmd_run_role() {
  local command_name role output rc
  command_name="${1:?command required}"
  role="${2:?role required}"

  if [ -n "${HARNESS_TEST_STUB_ROLE_COMMANDS:-}" ]; then
    __docker_cmd_test_stub_role "$command_name" "$role"
    return "$?"
  fi

  case "$command_name" in
    prepare-artifacts) output="$(docker_artifacts_prepare "$role")" || rc=$? ;;
    stage-artifacts) output="$(docker_artifacts_stage "$role")" || rc=$? ;;
    configure-role) output="$(docker_roles_configure "$role")" || rc=$? ;;
    validate-role) output="$(docker_roles_validate "$role")" || rc=$? ;;
    *) die "Unknown role command: $command_name" ;;
  esac
  rc="${rc:-0}"
  printf '%s\n' "$output"
  return "$rc"
}

__docker_cmd_run_all_roles() {
  local command_name role rc first_rc
  command_name="${1:?command required}"
  first_rc=0
  for role in "${roles[@]}"; do
    __docker_cmd_run_role "$command_name" "$role" || rc=$?
    rc="${rc:-0}"
    if [ "$rc" -ne 0 ]; then
      if [ "$first_rc" -eq 0 ]; then
        first_rc="$rc"
      fi
    fi
    unset rc
  done
  return "$first_rc"
}

__docker_cmd_workflow_step() {
  local step
  step="${1:?step required}"
  shift
  printf '==> %s\n' "$step"
  if [ -n "${HARNESS_TEST_WORKFLOW_CALLS:-}" ]; then
    mkdir -p "$(dirname "$HARNESS_TEST_WORKFLOW_CALLS")"
    printf '%s\n' "$step" >>"$HARNESS_TEST_WORKFLOW_CALLS"
    return 0
  fi
  "$@"
}

docker_cmd_with_lock() {
  local mode
  mode="${1:?lock mode required}"
  shift
  bootstrap_harness_env
  simulation_with_set_lock "$mode" "$HARNESS_SET_LOCK" "$HARNESS_SET_ID" "$@"
}

__docker_cmd_workflow_downstream() {
  __docker_cmd_workflow_step create docker_cmd_with_lock exclusive docker_cmd_create
  __docker_cmd_workflow_step start docker_cmd_with_lock exclusive docker_cmd_start
  __docker_cmd_workflow_step status docker_cmd_with_lock shared docker_cmd_status
  __docker_cmd_workflow_step prepare-artifacts docker_cmd_with_lock exclusive docker_cmd_prepare_artifacts ""
  __docker_cmd_workflow_step stage-artifacts docker_cmd_with_lock exclusive docker_cmd_stage_artifacts ""
  __docker_cmd_workflow_step configure-role docker_cmd_with_lock exclusive docker_cmd_configure_role ""
  __docker_cmd_workflow_step validate-role docker_cmd_with_lock exclusive docker_cmd_validate_role ""
  __docker_cmd_workflow_step configure-integration docker_cmd_with_lock exclusive docker_cmd_configure_integration
  __docker_cmd_workflow_step validate-integration docker_cmd_with_lock exclusive docker_cmd_validate_integration
  __docker_cmd_workflow_step prove-integration docker_cmd_with_lock exclusive docker_cmd_prove_integration
}

docker_cmd_run() {
  bootstrap_harness_env
  if docker_set_runtime_config_valid; then
    printf 'run: mode=resume run-id=%s\n' "$HARNESS_RUN_ID"
    __docker_cmd_workflow_downstream
    return
  fi
  if selected_containers_exist; then
    die "Docker generated state is missing or invalid while selected containers exist; use explicit recovery before running workflow"
  fi
  printf 'run: mode=fresh run-id=%s\n' "$HARNESS_RUN_ID"
  __docker_cmd_workflow_step preflight docker_cmd_with_lock shared docker_cmd_preflight
  __docker_cmd_workflow_step init-run docker_cmd_init_run
  __docker_cmd_workflow_downstream
}

docker_cmd_preflight() {
  bootstrap_harness_env
  validate_harness_inputs
  require_command docker
  require_command python3
  require_command cmp
  require_command sha256sum
  require_command tar
  require_command awk
  require_command ssh-keygen
  require_command ssh-keyscan
  detect_compose
  require_baseline_label
  [ -x "$integration_helper" ] || die "Missing executable integration helper: $integration_helper"
  [ -f "$compose_file" ] || die "Missing Compose file: $compose_file"
  [ -f "$docker_dir/ldap/50-harness-seed.ldif" ] || die "Missing LDAP seed LDIF"
  [ -f "$docker_dir/target/Dockerfile" ] || die "Missing harness target Dockerfile"
  [ -f "$docker_dir/scripts/harness-sleep.sh" ] || die "Missing harness container entrypoint"
  print_command_summary preflight "" "ok mode=$HARNESS_MODE compose=$compose_kind"
}

docker_cmd_init_run() {
  bootstrap_harness_env
  simulation_with_set_lock exclusive "$HARNESS_SET_LOCK" "$HARNESS_SET_ID" \
    __docker_cmd_init_run_locked || return $?
}

__docker_cmd_init_run_locked() {
  require_baseline_label
  [ ! -e "$HARNESS_ACTIVE_RUN_FILE" ] ||
    die "Selected Docker simulation set already has active-run state"
  [ ! -e "$HARNESS_GENERATED_RUN_DIR" ] ||
    die "HARNESS_RUN_ID already exists: $HARNESS_RUN_ID"
  if selected_containers_exist; then
    die "Selected Docker simulation containers already exist; stop and restore the selected set before init-run"
  fi
  write_rendered_env || return $?
  write_evidence init-run harness pass "simulate.sh init-run" "not-applicable" "Rendered redacted harness configuration with Version Baseline values" >/dev/null
  printf 'init-run: ok set-id=%s run-id=%s\n' "$HARNESS_SET_ID" "$HARNESS_RUN_ID"
}

docker_cmd_create() {
  docker_set_create "$@"
}

docker_cmd_start() {
  docker_set_start "$@"
}

docker_cmd_status() {
  docker_set_status "$@"
}

docker_cmd_ssh() {
  docker_ssh_interactive "$@"
}

docker_cmd_prepare_artifacts() {
  local role
  role="${1-}"
  if [ -z "$role" ]; then
    __docker_cmd_run_all_roles prepare-artifacts
  else
    __docker_cmd_run_role prepare-artifacts "$role"
  fi
}

docker_cmd_stage_artifacts() {
  local role
  role="${1-}"
  if [ -z "$role" ]; then
    __docker_cmd_run_all_roles stage-artifacts
  else
    __docker_cmd_run_role stage-artifacts "$role"
  fi
}

docker_cmd_configure_role() {
  local role
  role="${1-}"
  if [ -z "$role" ]; then
    __docker_cmd_run_all_roles configure-role
  else
    __docker_cmd_run_role configure-role "$role"
  fi
}

docker_cmd_validate_role() {
  local role
  role="${1-}"
  if [ -z "$role" ]; then
    __docker_cmd_run_all_roles validate-role
  else
    __docker_cmd_run_role validate-role "$role"
  fi
}

docker_cmd_configure_integration() {
  docker_integration_configure "$@"
}

docker_cmd_validate_integration() {
  docker_integration_validate "$@"
}

docker_cmd_prove_integration() {
  docker_integration_prove "$@"
}

docker_cmd_audit_state() {
  docker_set_audit "$@"
}

docker_cmd_stop() {
  docker_set_stop "$@"
}

docker_cmd_restore_baseline() {
  docker_baseline_restore "$@"
}

docker_cmd_clean() {
  docker_set_clean "$@"
}

docker_cmd_destroy() {
  docker_set_destroy "$@"
}
