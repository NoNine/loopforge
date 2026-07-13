#!/usr/bin/env bash

vm_state_write_run_marker() {
  write_runtime_marker \
    "$HARNESS_RUN_MARKER" \
    "$HARNESS_MODE" \
    "$HARNESS_RUN_ID" \
    "$HARNESS_PROJECT_NAME" \
    "$repo_root" \
    "$HARNESS_GENERATED_RUN_DIR" \
    "$HARNESS_RUNTIME_ENV"
}

vm_state_verify_run_marker() {
  verify_runtime_marker \
    "$HARNESS_RUN_MARKER" \
    "$HARNESS_MODE" \
    "$HARNESS_RUN_ID" \
    "$HARNESS_PROJECT_NAME" \
    "$repo_root" \
    "$HARNESS_GENERATED_RUN_DIR" \
    "$HARNESS_RUNTIME_ENV" \
    "VM harness run marker"
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
  require_generated_state_dir "$state_name" "runtime input directory" "$HARNESS_RUNTIME_INPUT_DIR"
  require_generated_state_file "$state_name" "runtime input harness env" "$HARNESS_RUNTIME_INPUT_DIR/harness.env"
  require_generated_state_file "$state_name" "runtime input Gerrit env" "$HARNESS_RUNTIME_INPUT_DIR/gerrit.env"
  require_generated_state_file "$state_name" "runtime input Jenkins controller env" "$HARNESS_RUNTIME_INPUT_DIR/jenkins-controller.env"
  require_generated_state_file "$state_name" "runtime input Jenkins agent env" "$HARNESS_RUNTIME_INPUT_DIR/jenkins-agent.env"
  require_generated_state_file "$state_name" "runtime input integration env" "$HARNESS_RUNTIME_INPUT_DIR/integration.env"
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
}

vm_state_read_summary() {
  local vm_set_marker_status
  vm_set_marker_status="absent"
  [ -f "$HARNESS_VM_SET_MARKER" ] && vm_set_marker_status="present"
  printf 'run-id=%s vm-set=%s run-marker=present vm-set-marker=%s\n' \
    "$HARNESS_RUN_ID" "$LOOPFORGE_VM_SET_ID" "$vm_set_marker_status"
}

vm_state_audit_readonly() {
  vm_state_validate_core
  vm_state_verify_run_marker
}

vm_state_clean_mutable_run_state() {
  local path
  for path in \
    "$HARNESS_RUN_MARKER" \
    "$HARNESS_RENDERED_DIR" \
    "$HARNESS_RUNTIME_INPUT_DIR" \
    "$HARNESS_TARGET_SSH_DIR" \
    "$HARNESS_HOST_DIR/state"; do
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
  write_checkpoint_marker \
    "$marker" \
    "$HARNESS_MODE" \
    "$HARNESS_RUN_ID" \
    "$HARNESS_PROJECT_NAME" \
    "$HARNESS_RUNTIME_ENV"
  printf 'boot_id=%s\n' "$boot_id" >>"$marker"
}

vm_state_verify_role_checkpoint() {
  local role checkpoint marker
  role="${1:?role required}"
  checkpoint="${2:?checkpoint required}"
  marker="$(vm_path_role_checkpoint_marker "$role" "$checkpoint")"
  verify_checkpoint_marker \
    "$marker" \
    "$HARNESS_MODE" \
    "$HARNESS_RUN_ID" \
    "$HARNESS_PROJECT_NAME" \
    "$HARNESS_RUNTIME_ENV" \
    "$role $checkpoint checkpoint"
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
    "$HARNESS_RUN_ID" \
    "$HARNESS_PROJECT_NAME" \
    "$HARNESS_RUNTIME_ENV"
}

vm_state_verify_integration_checkpoint() {
  local checkpoint marker
  checkpoint="${1:?checkpoint required}"
  marker="$(vm_path_integration_checkpoint_marker "$checkpoint")"
  verify_checkpoint_marker \
    "$marker" \
    "$HARNESS_MODE" \
    "$HARNESS_RUN_ID" \
    "$HARNESS_PROJECT_NAME" \
    "$HARNESS_RUNTIME_ENV" \
    "$checkpoint checkpoint"
}

vm_state_invalidate_integration_validation() {
  rm -f -- "$(vm_path_integration_checkpoint_marker validate-integration)"
}
