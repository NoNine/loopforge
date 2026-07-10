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

vm_state_write_vm_set_marker() {
  local tmp
  mkdir -p "$HARNESS_VM_SET_DIR"
  vm_libvirt_marker_values
  tmp="$(mktemp "${HARNESS_VM_SET_MARKER}.XXXXXX")"
  cat >"$tmp" <<EOF
mode=$HARNESS_MODE
vm_set_id=$LOOPFORGE_VM_SET_ID
project_name=$HARNESS_PROJECT_NAME
repo_root=$repo_root
vm_set_dir=$HARNESS_VM_SET_DIR
libvirt_uri=$VM_SET_MARKER_LIBVIRT_URI
domain_prefix=$VM_SET_MARKER_DOMAIN_PREFIX
network_name=$VM_SET_MARKER_NETWORK_NAME
storage_pool_name=$VM_SET_MARKER_STORAGE_POOL_NAME
storage_pool_target=$VM_SET_MARKER_STORAGE_POOL_TARGET
disk_ownership=$VM_SET_MARKER_DISK_OWNERSHIP
seed_pool_name=$VM_SET_MARKER_SEED_POOL_NAME
baseline_snapshot_name=$VM_SET_MARKER_BASELINE_SNAPSHOT_NAME
base_image=$(vm_libvirt_baked_base_image_path)
base_image_fingerprint=$VM_BAKED_BASE_IMAGE_FINGERPRINT
base_image_pool_name=$(vm_libvirt_baked_base_image_pool_name)
base_image_volume_name=$(vm_libvirt_baked_base_image_volume_name)
disk_size=$VM_DOMAIN_DISK_SIZE
ownership_schema_version=$VM_SET_MARKER_SCHEMA_VERSION
EOF
  chmod 0600 "$tmp"
  mv -- "$tmp" "$HARNESS_VM_SET_MARKER"
}

vm_state_write_or_verify_vm_set_marker() {
  if [ -f "$HARNESS_VM_SET_MARKER" ]; then
    vm_state_verify_vm_set_marker
    vm_state_verify_vm_set_base_identity
  else
    vm_state_write_vm_set_marker
  fi
}

vm_state_write_baseline_prereqs_marker() {
  local baked_marker baked_sha256 packages runtime_fingerprint tmp
  baked_marker="$(vm_libvirt_baked_base_image_marker_path)"
  baked_sha256="$(marker_value "$baked_marker" baked_sha256)" || return $?
  packages="$(vm_libvirt_base_image_superset_packages_csv)" || return $?
  runtime_fingerprint="$(runtime_env_fingerprint "$HARNESS_RUNTIME_ENV")" || return $?
  mkdir -p "$HARNESS_VM_SET_DIR" || return $?
  tmp="$(mktemp "${HARNESS_VM_BASELINE_PREREQS_MARKER}.XXXXXX")" || return $?
  cat >"$tmp" <<EOF
schema=2
mode=$HARNESS_MODE
vm_set_id=$LOOPFORGE_VM_SET_ID
run_id=$HARNESS_RUN_ID
project_name=$HARNESS_PROJECT_NAME
runtime_env_fingerprint=$runtime_fingerprint
ubuntu_release=$HARNESS_UBUNTU_BASELINE_RELEASE
ubuntu_codename=$HARNESS_UBUNTU_BASELINE_CODENAME
apt_mirror=$HARNESS_UBUNTU_APT_MIRROR
base_image=$(vm_libvirt_baked_base_image_path)
base_image_fingerprint=$VM_BAKED_BASE_IMAGE_FINGERPRINT
base_image_sha256=$baked_sha256
disk_size=$VM_DOMAIN_DISK_SIZE
packages=$packages
ldap_host=$HARNESS_LDAP_HOST
ldap_port=$HARNESS_LDAP_PORT
ldap_base_dn=$HARNESS_LDAP_BASE_DN
ldap_user_base=$HARNESS_LDAP_USER_BASE
ldap_group_base=$HARNESS_LDAP_GROUP_BASE
ldap_bind_dn=$HARNESS_LDAP_BIND_DN
status=ready
EOF
  chmod 0600 "$tmp"
  mv -- "$tmp" "$HARNESS_VM_BASELINE_PREREQS_MARKER"
}

vm_state_invalidate_baseline_prereqs_marker() {
  rm -f "$HARNESS_VM_BASELINE_PREREQS_MARKER"
}

vm_state_baseline_prereqs_marker_valid() {
  local baked_marker fingerprint_file key expected actual
  [ -r "$HARNESS_VM_BASELINE_PREREQS_MARKER" ] || return 1
  fingerprint_file="$(vm_libvirt_baked_base_image_fingerprint_file)"
  [ -r "$fingerprint_file" ] || return 1
  VM_BAKED_BASE_IMAGE_FINGERPRINT="$(cat "$fingerprint_file")"
  baked_marker="$(vm_libvirt_baked_base_image_marker_path)"
  [ -r "$baked_marker" ] || return 1
  for key in schema mode vm_set_id run_id project_name runtime_env_fingerprint \
    ubuntu_release ubuntu_codename apt_mirror base_image base_image_fingerprint \
    base_image_sha256 disk_size packages ldap_host ldap_port ldap_base_dn \
    ldap_user_base ldap_group_base ldap_bind_dn status; do
    case "$key" in
      schema) expected=2 ;;
      mode) expected="$HARNESS_MODE" ;;
      vm_set_id) expected="$LOOPFORGE_VM_SET_ID" ;;
      run_id) expected="$HARNESS_RUN_ID" ;;
      project_name) expected="$HARNESS_PROJECT_NAME" ;;
      runtime_env_fingerprint) expected="$(runtime_env_fingerprint "$HARNESS_RUNTIME_ENV")" ;;
      ubuntu_release) expected="$HARNESS_UBUNTU_BASELINE_RELEASE" ;;
      ubuntu_codename) expected="$HARNESS_UBUNTU_BASELINE_CODENAME" ;;
      apt_mirror) expected="$HARNESS_UBUNTU_APT_MIRROR" ;;
      base_image) expected="$(vm_libvirt_baked_base_image_path)" ;;
      base_image_fingerprint) expected="$VM_BAKED_BASE_IMAGE_FINGERPRINT" ;;
      base_image_sha256) expected="$(marker_value "$baked_marker" baked_sha256 2>/dev/null || true)" ;;
      disk_size) expected="$VM_DOMAIN_DISK_SIZE" ;;
      packages) expected="$(vm_libvirt_base_image_superset_packages_csv)" ;;
      ldap_host) expected="$HARNESS_LDAP_HOST" ;;
      ldap_port) expected="$HARNESS_LDAP_PORT" ;;
      ldap_base_dn) expected="$HARNESS_LDAP_BASE_DN" ;;
      ldap_user_base) expected="$HARNESS_LDAP_USER_BASE" ;;
      ldap_group_base) expected="$HARNESS_LDAP_GROUP_BASE" ;;
      ldap_bind_dn) expected="$HARNESS_LDAP_BIND_DN" ;;
      status) expected=ready ;;
    esac
    actual="$(marker_value "$HARNESS_VM_BASELINE_PREREQS_MARKER" "$key" 2>/dev/null || true)"
    [ "$actual" = "$expected" ] || return 1
  done
  vm_libvirt_baked_base_image_ready || return 1
}

vm_state_require_baseline_prereqs_marker() {
  vm_state_baseline_prereqs_marker_valid ||
    die "Stale VM baseline prerequisite marker: $HARNESS_VM_BASELINE_PREREQS_MARKER"
}

vm_state_baseline_prereqs_status() {
  if [ ! -f "$HARNESS_VM_BASELINE_PREREQS_MARKER" ]; then
    printf 'pending'
  elif vm_state_baseline_prereqs_marker_valid; then
    printf 'ready'
  else
    printf 'stale'
  fi
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
    storage_pool_target) printf '%s\n' "$VM_SET_MARKER_STORAGE_POOL_TARGET" ;;
    disk_ownership) printf '%s\n' "$VM_SET_MARKER_DISK_OWNERSHIP" ;;
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
  local key schema
  [ -f "$HARNESS_VM_SET_MARKER" ] ||
    die "Missing VM-set marker: $HARNESS_VM_SET_MARKER"
  vm_libvirt_marker_values
  schema="$(marker_value "$HARNESS_VM_SET_MARKER" ownership_schema_version 2>/dev/null || true)"
  [ "$schema" = "$VM_SET_MARKER_SCHEMA_VERSION" ] ||
    die "Incompatible legacy VM set $LOOPFORGE_VM_SET_ID. Select a fresh HARNESS_RUN_ID and LOOPFORGE_VM_SET_ID; retain this set for M5 down/destroy cleanup."
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
    storage_pool_target \
    disk_ownership \
    seed_pool_name \
    baseline_snapshot_name \
    ownership_schema_version
  do
    vm_state_verify_vm_set_marker_key "$key"
  done
}

vm_state_verify_vm_set_base_identity() {
  local key expected actual
  for key in base_image base_image_fingerprint base_image_pool_name \
    base_image_volume_name disk_size; do
    case "$key" in
      base_image) expected="$(vm_libvirt_baked_base_image_path)" ;;
      base_image_fingerprint) expected="$VM_BAKED_BASE_IMAGE_FINGERPRINT" ;;
      base_image_pool_name) expected="$(vm_libvirt_baked_base_image_pool_name)" ;;
      base_image_volume_name) expected="$(vm_libvirt_baked_base_image_volume_name)" ;;
      disk_size) expected="$VM_DOMAIN_DISK_SIZE" ;;
    esac
    actual="$(marker_value "$HARNESS_VM_SET_MARKER" "$key" 2>/dev/null || true)"
    [ "$actual" = "$expected" ] ||
      die "Incompatible VM set $LOOPFORGE_VM_SET_ID base-image identity ($key). Select a fresh HARNESS_RUN_ID and LOOPFORGE_VM_SET_ID; retain this set for M5 down/destroy cleanup."
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

vm_state_verify_run_and_vm_set() {
  vm_state_verify_run_marker
  vm_state_verify_vm_set_marker
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
  if [ -f "$HARNESS_VM_BASELINE_PREREQS_MARKER" ]; then
    vm_state_require_baseline_prereqs_marker
    vm_libvirt_baked_base_image_ready ||
      die "VM baked-image cache integrity validation failed during audit-state"
  fi
}
