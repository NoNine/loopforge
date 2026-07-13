#!/usr/bin/env bash

vm_generated_root() {
  printf '%s/generated/simulation/vm\n' "$repo_root"
}

vm_path_run_dir() {
  printf '%s/%s\n' "$(vm_generated_root)" "$HARNESS_RUN_ID"
}

vm_path_set_dir() {
  printf '%s/vm-sets/%s\n' "$(vm_generated_root)" "$LOOPFORGE_VM_SET_ID"
}

vm_paths_apply_canonical() {
  HARNESS_GENERATED_RUN_DIR="$(vm_path_run_dir)"
  HARNESS_VM_SET_DIR="$(vm_path_set_dir)"
  HARNESS_HOST_DIR="$HARNESS_GENERATED_RUN_DIR/host"
  HARNESS_TARGET_DIR="$HARNESS_GENERATED_RUN_DIR/target"
  HARNESS_RENDERED_DIR="$HARNESS_HOST_DIR/rendered"
  HARNESS_RUNTIME_INPUT_DIR="$HARNESS_HOST_DIR/runtime-inputs"
  HARNESS_RENDERED_ENV="$HARNESS_RENDERED_DIR/harness.env"
  HARNESS_RUNTIME_ENV="$HARNESS_RENDERED_DIR/harness.runtime.env"
  HARNESS_VM_INVENTORY_FILE="$HARNESS_RENDERED_DIR/vm-inventory.env"
  HARNESS_MANIFEST_CONTRACT="$HARNESS_RENDERED_DIR/artifact-manifest-contract.txt"
  HARNESS_RUN_MARKER="$HARNESS_GENERATED_RUN_DIR/.loopforge-vm-run.env"
  HARNESS_VM_SET_MARKER="$HARNESS_VM_SET_DIR/.loopforge-vm-set.env"
  HARNESS_VM_BASELINE_PREREQS_MARKER="$HARNESS_VM_SET_DIR/.loopforge-vm-baseline-prereqs.env"
  HARNESS_VM_SNAPSHOT_DIR="$HARNESS_VM_SET_DIR/snapshots"
  HARNESS_VM_SET_TARGET_SSH_DIR="$HARNESS_VM_SET_DIR/target-ssh"
  HARNESS_EVIDENCE_DIR="$HARNESS_HOST_DIR/evidence/harness"
  HARNESS_LOG_DIR="$HARNESS_HOST_DIR/logs/harness"
  HARNESS_INTEGRATION_EVIDENCE_DIR="$HARNESS_HOST_DIR/evidence/integration"
  HARNESS_INTEGRATION_LOG_DIR="$HARNESS_HOST_DIR/logs/integration"
  HARNESS_EXPORTED_ARTIFACT_DIR="$HARNESS_HOST_DIR/artifacts/exported"
  HARNESS_RETAINED_OUTPUT_BACKUP_DIR="$HARNESS_HOST_DIR/retained-output-backups"
  HARNESS_TARGET_SSH_DIR="$HARNESS_HOST_DIR/target-ssh"
  HARNESS_TARGET_SSH_IDENTITY_FILE="$HARNESS_VM_SET_TARGET_SSH_DIR/ci-operator"
  HARNESS_TARGET_SSH_KNOWN_HOSTS_FILE="$HARNESS_TARGET_SSH_DIR/known_hosts"
  HARNESS_ROLE_STATE_DIR="$HARNESS_HOST_DIR/state/roles"
  HARNESS_GERRIT_EVIDENCE_DIR="$HARNESS_TARGET_DIR/evidence/gerrit"
  HARNESS_GERRIT_LOG_DIR="$HARNESS_TARGET_DIR/logs/gerrit"
  HARNESS_JENKINS_CONTROLLER_EVIDENCE_DIR="$HARNESS_TARGET_DIR/evidence/jenkins-controller"
  HARNESS_JENKINS_CONTROLLER_LOG_DIR="$HARNESS_TARGET_DIR/logs/jenkins-controller"
  HARNESS_JENKINS_AGENT_EVIDENCE_DIR="$HARNESS_TARGET_DIR/evidence/jenkins-agent"
  HARNESS_JENKINS_AGENT_LOG_DIR="$HARNESS_TARGET_DIR/logs/jenkins-agent"
  VM_OUTPUT_PATHS_CANONICAL_APPLIED=1

  export HARNESS_GENERATED_RUN_DIR HARNESS_VM_SET_DIR HARNESS_HOST_DIR
  export HARNESS_TARGET_DIR HARNESS_RENDERED_DIR HARNESS_RUNTIME_INPUT_DIR
  export HARNESS_RENDERED_ENV HARNESS_RUNTIME_ENV HARNESS_VM_INVENTORY_FILE
  export HARNESS_MANIFEST_CONTRACT HARNESS_RUN_MARKER HARNESS_VM_SET_MARKER
  export HARNESS_VM_BASELINE_PREREQS_MARKER HARNESS_VM_SNAPSHOT_DIR
  export HARNESS_VM_SET_TARGET_SSH_DIR
  export HARNESS_EVIDENCE_DIR HARNESS_LOG_DIR
  export HARNESS_INTEGRATION_EVIDENCE_DIR HARNESS_INTEGRATION_LOG_DIR
  export HARNESS_EXPORTED_ARTIFACT_DIR HARNESS_RETAINED_OUTPUT_BACKUP_DIR
  export HARNESS_TARGET_SSH_DIR HARNESS_TARGET_SSH_IDENTITY_FILE
  export HARNESS_TARGET_SSH_KNOWN_HOSTS_FILE
  export HARNESS_ROLE_STATE_DIR
  export HARNESS_GERRIT_EVIDENCE_DIR HARNESS_GERRIT_LOG_DIR
  export HARNESS_JENKINS_CONTROLLER_EVIDENCE_DIR
  export HARNESS_JENKINS_CONTROLLER_LOG_DIR
  export HARNESS_JENKINS_AGENT_EVIDENCE_DIR HARNESS_JENKINS_AGENT_LOG_DIR
}

vm_path_role_checkpoint_marker() {
  local role checkpoint
  role="${1:?role required}"
  checkpoint="${2:?checkpoint required}"
  printf '%s/%s/%s.env\n' "$HARNESS_ROLE_STATE_DIR" "$role" "$checkpoint"
}

vm_path_integration_checkpoint_marker() {
  local checkpoint
  checkpoint="${1:?checkpoint required}"
  printf '%s/integration/%s.env\n' "$HARNESS_HOST_DIR/state" "$checkpoint"
}

vm_path_runtime_inputs() {
  printf '%s\n' "$HARNESS_RUNTIME_INPUT_DIR"
}

vm_path_bounded_log() {
  bounded_log_path_in_dir "$HARNESS_LOG_DIR" "${1:?log name required}"
}

vm_path_guest_input_root() {
  printf '/home/%s/loopforge-inputs\n' "$VM_OPERATOR_USER"
}

vm_path_guest_role_env() {
  printf '%s/%s.env\n' \
    "$(vm_path_guest_input_root)" \
    "${1:?role required}"
}

vm_path_guest_role_helpers_root() {
  role_helpers_root_for_operator "$VM_OPERATOR_USER"
}

vm_path_guest_role_helper() {
  role_helper_path_for_operator "$VM_OPERATOR_USER" "${1:?role required}"
}

vm_path_vm_set_libvirt_dir() {
  printf '%s/libvirt\n' "$HARNESS_VM_SET_DIR"
}

vm_path_vm_snapshot_record() {
  printf '%s/%s.env\n' "$HARNESS_VM_SNAPSHOT_DIR" "${1:?machine required}"
}

vm_path_vm_set_disk_dir() {
  printf '%s/disks\n' "$(vm_path_vm_set_libvirt_dir)"
}

vm_path_vm_set_base_image() {
  printf '%s/base.qcow2\n' "$(vm_path_vm_set_disk_dir)"
}

vm_path_vm_set_base_image_marker() {
  printf '%s/base-image.env\n' "$(vm_path_vm_set_libvirt_dir)"
}

vm_path_vm_set_base_image_lock() {
  printf '%s/.locks/base-image.lock\n' "$HARNESS_VM_SET_DIR"
}

vm_path_vm_set_bake_work_dir() {
  printf '%s/bake-work-%s\n' "$(vm_path_vm_set_libvirt_dir)" "$$"
}

vm_path_vm_set_seed_dir() {
  printf '%s/seeds\n' "$(vm_path_vm_set_libvirt_dir)"
}

vm_path_vm_set_machine_dir() {
  printf '%s/machines\n' "$(vm_path_vm_set_libvirt_dir)"
}

vm_path_vm_set_volume_dir() {
  printf '%s/volumes\n' "$(vm_path_vm_set_libvirt_dir)"
}

vm_path_vm_set_storage_pool_xml() {
  printf '%s/storage-pool.xml\n' "$(vm_path_vm_set_libvirt_dir)"
}

vm_path_vm_volume_xml() {
  printf '%s/%s.xml\n' "$(vm_path_vm_set_volume_dir)" "${1:?machine required}"
}

vm_path_vm_base_volume_xml() {
  printf '%s/base.xml\n' "$(vm_path_vm_set_volume_dir)"
}

vm_path_vm_machine_file() {
  printf '%s/%s.env\n' "$(vm_path_vm_set_machine_dir)" "${1:?machine required}"
}
