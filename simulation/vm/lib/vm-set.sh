#!/usr/bin/env bash

__vm_set_load_marker_values() {
  VM_SET_MARKER_SCHEMA_VERSION=6
  VM_SET_MARKER_LIBVIRT_URI="$VM_LIBVIRT_URI"
  VM_SET_MARKER_DOMAIN_PREFIX="$(vm_libvirt_domain_prefix)"
  VM_SET_MARKER_NETWORK_NAME="$(vm_libvirt_network_name)"
  VM_SET_MARKER_STORAGE_POOL_NAME="$(vm_libvirt_storage_pool_name)"
  VM_SET_MARKER_STORAGE_POOL_TARGET="$(vm_path_vm_set_disk_dir)"
  VM_SET_MARKER_DISK_OWNERSHIP="libvirt-managed"
  VM_SET_MARKER_SEED_POOL_NAME="$(vm_libvirt_seed_pool_name)"
  VM_SET_MARKER_BASELINE_SNAPSHOT_NAME="$VM_BASELINE_SNAPSHOT_NAME"
}

vm_set_prepare() {
  vm_set_validate_ownership_readonly || return $?
  vm_libvirt_require_base_image || return $?
  vm_libvirt_select_baked_base_image || return $?
  __vm_set_write_or_verify_marker || return $?
  if vm_libvirt_existing_disks_present; then
    vm_libvirt_require_existing_baked_base_image || return $?
    vm_libvirt_require_existing_storage_pool || return $?
    vm_libvirt_verify_existing_disk_identities || return $?
  else
    vm_libvirt_ensure_ssh_key || return $?
    vm_libvirt_define_network || return $?
    vm_libvirt_ensure_storage_pool || return $?
    vm_libvirt_ensure_baked_base_image || return $?
  fi
}

vm_set_create() {
  local machine
  vm_libvirt_require_base_image || return $?
  mkdir -p "$(vm_path_vm_set_libvirt_dir)" "$(vm_path_vm_set_disk_dir)" \
    "$(vm_path_vm_set_seed_dir)" "$(vm_path_vm_set_machine_dir)" \
    "$(vm_path_vm_set_volume_dir)" || return $?
  vm_libvirt_make_storage_path_searchable "$HARNESS_VM_SET_DIR" "$(vm_path_vm_set_libvirt_dir)" \
    "$(vm_path_vm_set_disk_dir)" "$(vm_path_vm_set_seed_dir)" || return $?
  chmod 0700 "$(vm_path_vm_set_machine_dir)" "$(vm_path_vm_set_volume_dir)" || return $?
  vm_libvirt_ensure_ssh_key || return $?
  vm_libvirt_define_network || return $?
  vm_libvirt_ensure_storage_pool || return $?
  vm_libvirt_ensure_baked_base_image || return $?
  for machine in "${vm_machines[@]}"; do
    vm_libvirt_define_machine "$machine" || return $?
  done
}

__vm_set_verify_selected_domain_names() {
  local actual expected machine
  expected="$(for machine in "${vm_machines[@]}"; do
    printf '%s\n' "$(vm_libvirt_domain_name "$machine")"
  done | sort)"
  actual="$(vm_libvirt_list_selected_domains | sort)"
  [ "$actual" = "$expected" ] || {
    printf 'ERROR: Selected libvirt domain inventory does not match the owned VM set\n' >&2
    printf 'expected-domains=%s\n' "$(printf '%s' "$expected" | paste -sd, -)" >&2
    printf 'actual-domains=%s\n' "$(printf '%s' "$actual" | paste -sd, -)" >&2
    return 1
  }
}

__vm_set_verify_network_identity() {
  local bridge network
  network="$(vm_libvirt_network_name)"
  bridge="$(vm_libvirt_bridge_name)"
  virsh -c "$VM_LIBVIRT_URI" net-dumpxml "$network" | python3 -c '
import sys, xml.etree.ElementTree as ET
root = ET.parse(sys.stdin).getroot()
name, bridge = sys.argv[1:]
bridge_node = root.find("./bridge")
if root.findtext("./name") != name or bridge_node is None or bridge_node.get("name") != bridge:
    raise SystemExit("network identity mismatch")
' "$network" "$bridge"
}

vm_set_verify_selected_ownership() {
  local machine pool
  vm_set_verify_marker || return $?
  __vm_set_verify_selected_domain_names || return $?
  vm_libvirt_selected_network_exists || die "Missing selected VM network: $(vm_libvirt_network_name)"
  __vm_set_verify_network_identity || die "Selected VM network identity mismatch"
  pool="$(vm_libvirt_storage_pool_name)"
  vm_libvirt_require_directory_pool "$pool" "$(vm_path_vm_set_disk_dir)" ||
    die "Selected VM storage pool identity mismatch: $pool"
  for machine in "${vm_machines[@]}"; do
    vm_libvirt_machine_exists "$machine" || die "Missing selected VM domain: $(vm_libvirt_domain_name "$machine")"
    vm_libvirt_verify_existing_disk_identity "$machine" || return $?
    vm_libvirt_verify_domain_attachments "$machine" ||
      die "Selected VM domain attachment identity mismatch: $(vm_libvirt_domain_name "$machine")"
  done
}

__vm_set_verify_teardown_ownership() {
  local domain machine pool schema seed_pool volume
  vm_set_verify_marker_for_teardown || return $?
  schema="$(__vm_set_schema)"
  while IFS= read -r domain; do
    [ -n "$domain" ] || continue
    for machine in "${vm_machines[@]}"; do
      [ "$domain" != "$(vm_libvirt_domain_name "$machine")" ] || continue 2
    done
    die "Unowned domain shares the selected VM-set prefix: $domain"
  done < <(vm_libvirt_list_selected_domains)
  pool="$(vm_libvirt_storage_pool_name)"
  if vm_libvirt_pool_exists "$pool"; then
    [ "$(vm_libvirt_pool_target "$pool")" = "$(vm_path_vm_set_disk_dir)" ] ||
      die "Selected teardown storage pool target mismatch: $pool"
    __vm_set_verify_teardown_pool_volumes "$pool" disk || return $?
  fi
  seed_pool="$(vm_libvirt_seed_pool_name)"
  if vm_libvirt_pool_exists "$seed_pool"; then
    [ "$(vm_libvirt_pool_target "$seed_pool")" = "$(vm_path_vm_set_seed_dir)" ] ||
      die "Selected teardown seed pool target mismatch: $seed_pool"
    __vm_set_verify_teardown_pool_volumes "$seed_pool" seed || return $?
  fi
  if vm_libvirt_selected_network_exists; then
    __vm_set_verify_network_identity || die "Selected teardown network identity mismatch"
  fi
  for machine in "${vm_machines[@]}"; do
    volume="$(vm_libvirt_machine_volume_name "$machine")"
    if [ "$schema" = "$VM_SET_MARKER_SCHEMA_VERSION" ] && vm_libvirt_volume_exists "$pool" "$volume"; then
      __vm_set_verify_teardown_disk_identity "$machine" || return $?
    fi
    vm_libvirt_machine_exists "$machine" || continue
    vm_libvirt_verify_domain_attachments "$machine" ||
      die "Selected teardown domain attachment identity mismatch: $(vm_libvirt_domain_name "$machine")"
  done
}

vm_set_verify_teardown_ownership() {
  __vm_set_verify_teardown_ownership
}

__vm_set_verify_teardown_pool_volumes() {
  local actual allowed kind machine pool volume
  pool="${1:?pool required}"
  kind="${2:?volume kind required}"
  while IFS= read -r actual; do
    [ -n "$actual" ] || continue
    allowed=0
    if [ "$kind" = disk ] && [ "$actual" = "$(vm_libvirt_baked_base_image_volume_name)" ]; then
      allowed=1
    fi
    for machine in "${vm_machines[@]}"; do
      case "$kind" in
        disk) volume="$(vm_libvirt_machine_volume_name "$machine")" ;;
        seed) volume="$machine-seed.iso" ;;
        *) die "Unknown teardown volume kind: $kind" ;;
      esac
      [ "$actual" != "$volume" ] || allowed=1
    done
    [ "$allowed" -eq 1 ] ||
      die "Unowned volume exists in selected teardown pool $pool: $actual"
  done < <(virsh -c "$VM_LIBVIRT_URI" vol-list "$pool" --name)
}

__vm_set_verify_teardown_disk_identity() {
  local actual expected key machine metadata pool volume
  machine="${1:?machine required}"
  metadata="$(vm_libvirt_machine_metadata_path "$machine")"
  pool="$(vm_libvirt_storage_pool_name)"
  volume="$(vm_libvirt_machine_volume_name "$machine")"
  [ -r "$metadata" ] || die "Missing selected VM disk metadata for teardown: $metadata"
  vm_libvirt_volume_exists "$pool" "$volume" ||
    die "Missing selected libvirt volume for teardown: $pool/$volume"
  for key in machine domain disk storage_pool_name volume_name disk_ownership; do
    actual="$(marker_value "$metadata" "$key" 2>/dev/null || true)"
    case "$key" in
      machine) expected="$machine" ;;
      domain) expected="$(vm_libvirt_domain_name "$machine")" ;;
      disk) expected="$(vm_libvirt_disk_path "$machine")" ;;
      storage_pool_name) expected="$pool" ;;
      volume_name) expected="$volume" ;;
      disk_ownership) expected=libvirt-managed ;;
    esac
    [ "$actual" = "$expected" ] ||
      die "Selected VM disk metadata mismatch for teardown: $machine ($key)"
  done
  [ "$(vm_libvirt_volume_path "$pool" "$volume")" = "$(vm_libvirt_disk_path "$machine")" ] ||
    die "Selected VM volume path mismatch for teardown: $machine"
  [ "$(vm_libvirt_volume_value "$pool" "$volume" format)" = qcow2 ] ||
    die "Selected VM volume format mismatch for teardown: $machine"
}

__vm_set_destroy_pool_recovery() {
  local actual pool target volume
  pool="${1:?pool required}"
  target="${2:?target required}"
  [ "${3:?kind required}" = seed ] || [ "$3" = disk ] ||
    die "Unknown recovery pool kind: $3"
  vm_libvirt_pool_exists "$pool" || return 0
  actual="$(vm_libvirt_pool_target "$pool")" ||
    die "Selected recovery storage pool has unreadable target: $pool"
  [ "$actual" = "$target" ] ||
    die "Selected recovery storage pool target mismatch: $pool"
  if [ -d "$target" ]; then
    vm_libvirt_require_directory_pool "$pool" "$target" ||
      die "Selected recovery storage pool is not usable: $pool"
    __vm_set_verify_teardown_pool_volumes "$pool" "$3" || return $?
    while IFS= read -r volume; do
      [ -n "$volume" ] || continue
      virsh -c "$VM_LIBVIRT_URI" vol-delete "$volume" --pool "$pool" >/dev/null || return $?
    done < <(virsh -c "$VM_LIBVIRT_URI" vol-list "$pool" --name)
  else
    printf 'recovery-missing-pool-target pool=%s path=%s\n' "$pool" "$target"
  fi
  vm_libvirt_remove_pool "$pool"
}

vm_set_destroy_recovery() {
  local domain machine network pool seed_pool state
  pool="$(vm_libvirt_storage_pool_name)"
  seed_pool="$(vm_libvirt_seed_pool_name)"
  network="$(vm_libvirt_network_name)"
  for machine in "${vm_machines[@]}"; do
    vm_libvirt_machine_exists "$machine" || continue
    domain="$(vm_libvirt_domain_name "$machine")"
    state="$(vm_libvirt_domain_state "$machine")"
    case "$state" in
      'shut off'|shut*) ;;
      *) virsh -c "$VM_LIBVIRT_URI" destroy "$domain" >/dev/null || return $? ;;
    esac
    virsh -c "$VM_LIBVIRT_URI" undefine "$domain" \
      --snapshots-metadata --nvram >/dev/null 2>&1 ||
      virsh -c "$VM_LIBVIRT_URI" undefine "$domain" \
        --snapshots-metadata >/dev/null 2>&1 ||
      virsh -c "$VM_LIBVIRT_URI" undefine "$domain" >/dev/null || return $?
  done
  __vm_set_destroy_pool_recovery "$pool" "$(vm_path_vm_set_disk_dir)" disk || return $?
  __vm_set_destroy_pool_recovery "$seed_pool" "$(vm_path_vm_set_seed_dir)" seed || return $?
  if vm_libvirt_selected_network_exists; then
    __vm_set_verify_network_identity || die "Selected recovery network identity mismatch"
    if vm_libvirt_network_is_active; then
      virsh -c "$VM_LIBVIRT_URI" net-destroy "$network" >/dev/null || return $?
    fi
    virsh -c "$VM_LIBVIRT_URI" net-undefine "$network" >/dev/null || return $?
  fi
  vm_libvirt_selected_resources_exist &&
    die "Selected VM resources remain after recovery destroy"
  printf 'vm-set-destroy=ready recovery=metadata-missing\n'
}

vm_set_destroy() {
  local domain machine network pool seed_pool state volume
  __vm_libvirt_cleanup_bake_domain || return $?
  if [ ! -f "$HARNESS_VM_SET_MARKER" ]; then
    vm_set_destroy_recovery
    return $?
  fi
  __vm_set_verify_teardown_ownership || return $?
  pool="$(vm_libvirt_storage_pool_name)"
  seed_pool="$(vm_libvirt_seed_pool_name)"
  network="$(vm_libvirt_network_name)"
  for machine in "${vm_machines[@]}"; do
    vm_libvirt_machine_exists "$machine" || continue
    domain="$(vm_libvirt_domain_name "$machine")"
    state="$(vm_libvirt_domain_state "$machine")"
    case "$state" in
      'shut off'|shut*) ;;
      *) virsh -c "$VM_LIBVIRT_URI" destroy "$domain" >/dev/null || return $? ;;
    esac
    virsh -c "$VM_LIBVIRT_URI" undefine "$domain" \
      --snapshots-metadata --nvram >/dev/null 2>&1 ||
      virsh -c "$VM_LIBVIRT_URI" undefine "$domain" \
        --snapshots-metadata >/dev/null 2>&1 ||
      virsh -c "$VM_LIBVIRT_URI" undefine "$domain" >/dev/null || return $?
  done
  if vm_libvirt_pool_exists "$pool"; then
    for machine in "${vm_machines[@]}"; do
      volume="$(vm_libvirt_machine_volume_name "$machine")"
      vm_libvirt_volume_exists "$pool" "$volume" || continue
      virsh -c "$VM_LIBVIRT_URI" vol-delete "$volume" --pool "$pool" >/dev/null || return $?
    done
    volume="$(vm_libvirt_baked_base_image_volume_name)"
    if vm_libvirt_volume_exists "$pool" "$volume"; then
      virsh -c "$VM_LIBVIRT_URI" vol-delete "$volume" --pool "$pool" >/dev/null || return $?
    fi
  fi
  if vm_libvirt_pool_exists "$seed_pool"; then
    for machine in "${vm_machines[@]}"; do
      volume="$machine-seed.iso"
      vm_libvirt_volume_exists "$seed_pool" "$volume" || continue
      virsh -c "$VM_LIBVIRT_URI" vol-delete "$volume" --pool "$seed_pool" >/dev/null || return $?
    done
  fi
  vm_libvirt_remove_pool "$pool" || return $?
  vm_libvirt_remove_pool "$seed_pool" || return $?
  if vm_libvirt_selected_network_exists; then
    if vm_libvirt_network_is_active; then
      virsh -c "$VM_LIBVIRT_URI" net-destroy "$network" >/dev/null || return $?
    fi
    virsh -c "$VM_LIBVIRT_URI" net-undefine "$network" >/dev/null || return $?
  fi
  vm_libvirt_selected_resources_exist &&
    die "Selected VM resources remain after destroy"
  printf 'vm-set-destroy=ready\n'
}

__vm_set_write_marker() {
  local tmp
  mkdir -p "$HARNESS_VM_SET_DIR"
  __vm_set_load_marker_values
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

__vm_set_write_or_verify_marker() {
  if [ -f "$HARNESS_VM_SET_MARKER" ]; then
    vm_set_verify_marker
    __vm_set_verify_base_identity
  else
    __vm_set_write_marker
  fi
}

__vm_set_expected_marker_value() {
  local key
  key="${1:?key required}"
  __vm_set_load_marker_values
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

__vm_set_verify_marker_key() {
  local key expected actual
  key="${1:?key required}"
  expected="$(__vm_set_expected_marker_value "$key")"
  actual="$(marker_value "$HARNESS_VM_SET_MARKER" "$key")" ||
    die "VM-set marker missing $key: $HARNESS_VM_SET_MARKER"
  [ "$actual" = "$expected" ] ||
    die "VM-set marker $key does not match selected runtime config"
}

vm_set_verify_marker() {
  local key schema
  [ -f "$HARNESS_VM_SET_MARKER" ] ||
    die "Missing VM-set marker: $HARNESS_VM_SET_MARKER"
  __vm_set_load_marker_values
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
    __vm_set_verify_marker_key "$key"
  done
}

vm_set_verify_marker_for_teardown() {
  local key
  [ -f "$HARNESS_VM_SET_MARKER" ] ||
    die "Missing VM-set marker: $HARNESS_VM_SET_MARKER"
  __vm_set_load_marker_values
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
    baseline_snapshot_name
  do
    __vm_set_verify_marker_key "$key"
  done
}

__vm_set_schema() {
  marker_value "$HARNESS_VM_SET_MARKER" ownership_schema_version
}

__vm_set_verify_base_identity() {
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

vm_set_validate_ownership_readonly() {
  local resources_status
  resources_status="$(vm_libvirt_selected_resource_status)"
  if [ -f "$HARNESS_VM_SET_MARKER" ]; then
    vm_set_verify_marker
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

vm_set_verify_run_and_set() {
  vm_state_verify_run_marker
  vm_set_verify_marker
}

vm_set_remove_metadata() {
  rm -rf -- "$HARNESS_VM_SET_DIR"
}
