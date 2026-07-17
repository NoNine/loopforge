#!/usr/bin/env bash

vm_state_write_run_marker() {
  write_runtime_marker \
    "$HARNESS_RUN_MARKER" \
    "$HARNESS_MODE" \
    vm \
    "$HARNESS_SET_ID" \
    "$HARNESS_RUN_ID" \
    "$HARNESS_PROJECT_NAME" \
    "$repo_root" \
    "$HARNESS_GENERATED_RUN_DIR" \
    "$HARNESS_RUNTIME_ENV" \
    "$HARNESS_SOURCE_INPUT_DIR"
}

vm_state_verify_run_marker() {
  verify_runtime_marker \
    "$HARNESS_RUN_MARKER" \
    "$HARNESS_MODE" \
    vm \
    "$HARNESS_SET_ID" \
    "$HARNESS_RUN_ID" \
    "$HARNESS_PROJECT_NAME" \
    "$repo_root" \
    "$HARNESS_GENERATED_RUN_DIR" \
    "$HARNESS_RUNTIME_ENV" \
    "$HARNESS_SOURCE_INPUT_DIR" \
    "VM harness run marker"
}

vm_state_write_initial_lifecycle_records() {
  local source_fingerprint
  source_fingerprint="$(simulation_input_bundle_fingerprint "$HARNESS_SOURCE_INPUT_DIR")" || return $?
  write_initial_workflow_state \
    "$HARNESS_WORKFLOW_STATE_FILE" vm "$HARNESS_SET_ID" "$HARNESS_RUN_ID" \
    "$HARNESS_RUN_MARKER" none "$source_fingerprint" || return $?
  write_active_run_record \
    "$HARNESS_ACTIVE_RUN_FILE" vm "$HARNESS_SET_ID" "$HARNESS_RUN_ID" \
    "$HARNESS_PROJECT_NAME" "$HARNESS_RUN_MARKER" none active none
}

vm_state_verify_active_run_binding() {
  lifecycle_records_are_bound \
    "$HARNESS_ACTIVE_RUN_FILE" "$HARNESS_RUN_MARKER" \
    "$HARNESS_WORKFLOW_STATE_FILE" vm "$HARNESS_SET_ID" "$HARNESS_RUN_ID" \
    "$HARNESS_PROJECT_NAME" "$(simulation_input_bundle_fingerprint "$HARNESS_SOURCE_INPUT_DIR")" ||
    die "VM active-run, run marker, and workflow state do not agree"
  simulation_input_state_is_bound "$HARNESS_WORKFLOW_STATE_FILE" "$HARNESS_RUN_MARKER" \
    vm "$HARNESS_SET_ID" "$HARNESS_RUN_ID" "$HARNESS_SOURCE_INPUT_DIR" \
    "$HARNESS_EFFECTIVE_INPUT_RECORD" "$HARNESS_RUNTIME_INPUT_DIR" ||
    die "VM source/effective input state does not agree"
}

vm_state_require_effective_inputs() {
  require_effective_inputs_ready "$HARNESS_WORKFLOW_STATE_FILE" "$HARNESS_RUN_MARKER" \
    vm "$HARNESS_SET_ID" "$HARNESS_RUN_ID" "$HARNESS_SOURCE_INPUT_DIR" \
    "$HARNESS_EFFECTIVE_INPUT_RECORD" "$HARNESS_RUNTIME_INPUT_DIR"
}

vm_state_validate_core() {
  local state_name role
  state_name="VM generated state"
  require_generated_state_dir "$state_name" "run root" "$HARNESS_GENERATED_RUN_DIR"
  require_generated_state_dir "$state_name" "host output directory" "$HARNESS_HOST_DIR"
  require_generated_state_dir "$state_name" "target output directory" "$HARNESS_TARGET_DIR"
  require_generated_state_dir "$state_name" "rendered directory" "$HARNESS_RENDERED_DIR"
  require_generated_state_file "$state_name" "rendered harness env" "$HARNESS_RENDERED_ENV"
  require_generated_state_file "$state_name" "runtime harness env" "$HARNESS_RUNTIME_ENV"
  require_generated_state_file "$state_name" "VM inventory expectations" "$HARNESS_VM_INVENTORY_FILE"
  require_generated_state_file "$state_name" "artifact manifest contract" "$HARNESS_MANIFEST_CONTRACT"
  require_generated_state_file "$state_name" "run marker" "$HARNESS_RUN_MARKER"
  require_generated_state_file "$state_name" "active-run pointer" "$HARNESS_ACTIVE_RUN_FILE"
  require_generated_state_file "$state_name" "workflow state" "$HARNESS_WORKFLOW_STATE_FILE"
  require_generated_state_dir "$state_name" "source input directory" "$HARNESS_SOURCE_INPUT_DIR"
  require_generated_state_file "$state_name" "source harness env" "$HARNESS_SOURCE_INPUT_DIR/harness.env"
  require_generated_state_file "$state_name" "source Gerrit env" "$HARNESS_SOURCE_INPUT_DIR/gerrit.env"
  require_generated_state_file "$state_name" "source Jenkins controller env" "$HARNESS_SOURCE_INPUT_DIR/jenkins-controller.env"
  require_generated_state_file "$state_name" "source Jenkins agent env" "$HARNESS_SOURCE_INPUT_DIR/jenkins-agent.env"
  require_generated_state_file "$state_name" "source integration env" "$HARNESS_SOURCE_INPUT_DIR/integration.env"
  require_generated_state_dir "$state_name" "harness evidence directory" "$HARNESS_EVIDENCE_DIR"
  require_generated_state_dir "$state_name" "harness log directory" "$HARNESS_LOG_DIR"
  require_generated_state_dir "$state_name" "integration evidence directory" "$HARNESS_INTEGRATION_EVIDENCE_DIR"
  require_generated_state_dir "$state_name" "integration log directory" "$HARNESS_INTEGRATION_LOG_DIR"
  require_generated_state_dir "$state_name" "exported artifact review directory" "$HARNESS_EXPORTED_ARTIFACT_DIR"
  require_generated_state_dir "$state_name" "target SSH directory" "$HARNESS_TARGET_SSH_DIR"
  for role in "${roles[@]}"; do
    require_generated_state_dir "$state_name" "$role evidence directory" "$HARNESS_TARGET_DIR/evidence/$role"
    require_generated_state_dir "$state_name" "$role log directory" "$HARNESS_TARGET_DIR/logs/$role"
  done
  vm_state_verify_active_run_binding
  if [ "$(strict_record_value "$HARNESS_WORKFLOW_STATE_FILE" input_state)" = ready ]; then
    require_generated_state_file "$state_name" "effective-input binding" "$HARNESS_EFFECTIVE_INPUT_RECORD"
    require_generated_state_dir "$state_name" "effective input directory" "$HARNESS_RUNTIME_INPUT_DIR"
    for role in harness gerrit jenkins-controller jenkins-agent integration; do
      require_generated_state_file "$state_name" "effective $role env" "$HARNESS_RUNTIME_INPUT_DIR/$role.env"
    done
  fi
}

vm_state_read_summary() {
  local vm_set_marker_status
  vm_set_marker_status="absent"
  [ -f "$HARNESS_VM_SET_MARKER" ] && vm_set_marker_status="present"
  printf 'run-id=%s set-id=%s run-marker=present vm-set-marker=%s\n' \
    "$HARNESS_RUN_ID" "$HARNESS_SET_ID" "$vm_set_marker_status"
}

vm_state_audit_readonly() {
  vm_state_validate_core
  vm_state_verify_run_marker
}

vm_state_clean_mutable_run_state() {
  local path
  for path in \
    "$HARNESS_RENDERED_DIR" \
    "$HARNESS_SOURCE_INPUT_DIR" \
    "$HARNESS_RUNTIME_INPUT_DIR" \
    "$HARNESS_EFFECTIVE_INPUT_RECORD" \
    "$HARNESS_TARGET_SSH_DIR" \
    "$HARNESS_WORKFLOW_STATE_FILE"; do
    [ -e "$path" ] || continue
    rm -rf -- "$path" || return 1
  done
}

vm_state_write_role_checkpoint() {
  local role checkpoint boot_id marker
  role="${1:?role required}"
  checkpoint="${2:?checkpoint required}"
  boot_id="${3:?boot ID required}"
  marker="$(vm_path_role_checkpoint_marker "$role" "$checkpoint")"
  atomic_write_record "$marker" "$LF_MODE_PUBLIC_FILE" \
    "schema_version=1" \
    "mode=$HARNESS_MODE" \
    "backend=vm" \
    "set_id=$HARNESS_SET_ID" \
    "run_id=$HARNESS_RUN_ID" \
    "resource_namespace=$HARNESS_PROJECT_NAME" \
    "runtime_env_fingerprint=$(runtime_env_fingerprint "$HARNESS_RUNTIME_ENV")" \
    "source_inputs_fingerprint=$(simulation_input_bundle_fingerprint "$HARNESS_SOURCE_INPUT_DIR")" \
    "effective_inputs_fingerprint=$(simulation_input_bundle_fingerprint "$HARNESS_RUNTIME_INPUT_DIR")" \
    "boot_id=$boot_id"
}

vm_state_verify_role_checkpoint() {
  local role checkpoint marker
  role="${1:?role required}"
  checkpoint="${2:?checkpoint required}"
  marker="$(vm_path_role_checkpoint_marker "$role" "$checkpoint")"
  strict_record_keys "$marker" schema_version mode backend set_id run_id \
    resource_namespace runtime_env_fingerprint source_inputs_fingerprint \
    effective_inputs_fingerprint boot_id ||
    die "$role $checkpoint checkpoint has malformed fields"
  [ "$(strict_record_value "$marker" backend)" = vm ] || die "$role $checkpoint backend mismatch"
  [ "$(strict_record_value "$marker" set_id)" = "$HARNESS_SET_ID" ] || die "$role $checkpoint set ID mismatch"
  [ "$(strict_record_value "$marker" run_id)" = "$HARNESS_RUN_ID" ] || die "$role $checkpoint run ID mismatch"
  [ "$(strict_record_value "$marker" resource_namespace)" = "$HARNESS_PROJECT_NAME" ] || die "$role $checkpoint namespace mismatch"
  [ "$(strict_record_value "$marker" runtime_env_fingerprint)" = "$(runtime_env_fingerprint "$HARNESS_RUNTIME_ENV")" ] || die "$role $checkpoint runtime fingerprint mismatch"
  [ "$(strict_record_value "$marker" source_inputs_fingerprint)" = "$(simulation_input_bundle_fingerprint "$HARNESS_SOURCE_INPUT_DIR")" ] || die "$role $checkpoint source input fingerprint mismatch"
  [ "$(strict_record_value "$marker" effective_inputs_fingerprint)" = "$(simulation_input_bundle_fingerprint "$HARNESS_RUNTIME_INPUT_DIR")" ] || die "$role $checkpoint effective input fingerprint mismatch"
}

vm_state_invalidate_role_validation() {
  rm -f -- "$(vm_path_role_checkpoint_marker "${1:?role required}" validated)"
}

vm_state_write_integration_checkpoint() {
  local checkpoint marker
  checkpoint="${1:?checkpoint required}"
  marker="$(vm_path_integration_checkpoint_marker "$checkpoint")"
  mkdir -p "$(dirname "$marker")"
  write_checkpoint_marker \
    "$marker" \
    "$HARNESS_MODE" \
    vm \
    "$HARNESS_SET_ID" \
    "$HARNESS_RUN_ID" \
    "$HARNESS_PROJECT_NAME" \
    "$HARNESS_RUNTIME_ENV" \
    "$HARNESS_SOURCE_INPUT_DIR" \
    "$HARNESS_RUNTIME_INPUT_DIR"
}

vm_state_verify_integration_checkpoint() {
  local checkpoint marker
  checkpoint="${1:?checkpoint required}"
  marker="$(vm_path_integration_checkpoint_marker "$checkpoint")"
  verify_checkpoint_marker \
    "$marker" \
    "$HARNESS_MODE" \
    vm \
    "$HARNESS_SET_ID" \
    "$HARNESS_RUN_ID" \
    "$HARNESS_PROJECT_NAME" \
    "$HARNESS_RUNTIME_ENV" \
    "$HARNESS_SOURCE_INPUT_DIR" \
    "$HARNESS_RUNTIME_INPUT_DIR" \
    "$checkpoint checkpoint"
}

vm_state_invalidate_integration_validation() {
  rm -f -- "$(vm_path_integration_checkpoint_marker validate-integration)"
}
