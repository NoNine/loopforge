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

vm_state_expected_vm_set_marker_value() {
  local key
  key="${1:?key required}"
  vm_libvirt_marker_values
  case "$key" in
    mode) printf '%s\n' "$HARNESS_MODE" ;;
    vm_set_id) printf '%s\n' "$LOOPFORGE_VM_SET_ID" ;;
    project_name) printf '%s\n' "$HARNESS_PROJECT_NAME" ;;
    repo_root) printf '%s\n' "$repo_root" ;;
    vm_set_dir) printf '%s\n' "$HARNESS_VM_SET_DIR" ;;
    libvirt_uri) printf '%s\n' "$VM_SET_MARKER_LIBVIRT_URI" ;;
    domain_prefix) printf '%s\n' "$VM_SET_MARKER_DOMAIN_PREFIX" ;;
    network_name) printf '%s\n' "$VM_SET_MARKER_NETWORK_NAME" ;;
    storage_pool_name) printf '%s\n' "$VM_SET_MARKER_STORAGE_POOL_NAME" ;;
    seed_pool_name) printf '%s\n' "$VM_SET_MARKER_SEED_POOL_NAME" ;;
    baseline_snapshot_name) printf '%s\n' "$VM_SET_MARKER_BASELINE_SNAPSHOT_NAME" ;;
    ownership_schema_version) printf '%s\n' "$VM_SET_MARKER_SCHEMA_VERSION" ;;
    *) die "Unknown VM-set marker key: $key" ;;
  esac
}

vm_state_verify_vm_set_marker_key() {
  local key expected actual
  key="${1:?key required}"
  expected="$(vm_state_expected_vm_set_marker_value "$key")"
  actual="$(marker_value "$HARNESS_VM_SET_MARKER" "$key")" ||
    die "VM-set marker missing $key: $HARNESS_VM_SET_MARKER"
  [ "$actual" = "$expected" ] ||
    die "VM-set marker $key does not match selected runtime config"
}

vm_state_verify_vm_set_marker() {
  local key
  [ -f "$HARNESS_VM_SET_MARKER" ] ||
    die "Missing VM-set marker: $HARNESS_VM_SET_MARKER"
  for key in \
    mode \
    vm_set_id \
    project_name \
    repo_root \
    vm_set_dir \
    libvirt_uri \
    domain_prefix \
    network_name \
    storage_pool_name \
    seed_pool_name \
    baseline_snapshot_name \
    ownership_schema_version
  do
    vm_state_verify_vm_set_marker_key "$key"
  done
}

vm_state_validate_vm_set_ownership_readonly() {
  local resources_status
  resources_status="$(vm_libvirt_selected_resource_status)"
  if [ -f "$HARNESS_VM_SET_MARKER" ]; then
    vm_state_verify_vm_set_marker
    printf 'vm-set=owned vm-resources=%s\n' "$resources_status"
    return 0
  fi
  if [ -d "$HARNESS_VM_SET_DIR" ]; then
    die "Inconsistent VM-set state: missing VM-set marker: $HARNESS_VM_SET_MARKER"
  fi
  if [ "$resources_status" = "present" ]; then
    die "Inconsistent VM-set state: selected libvirt resources exist without generated ownership metadata"
  fi
  printf 'vm-set=absent vm-resources=%s\n' "$resources_status"
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
  vm_state_validate_vm_set_ownership_readonly >/dev/null
}
