#!/usr/bin/env bash

__vm_snapshots_exists() {
  local domain
  domain="$(vm_libvirt_domain_name "${1:?machine required}")"
  virsh -c "$VM_LIBVIRT_URI" snapshot-info "$domain" \
    --snapshotname "$VM_BASELINE_SNAPSHOT_NAME" >/dev/null 2>&1
}

__vm_snapshots_write_record() {
  local machine record tmp
  machine="${1:?machine required}"
  record="$(vm_path_vm_snapshot_record "$machine")"
  mkdir -p "$HARNESS_VM_SNAPSHOT_DIR"
  tmp="$(mktemp "${record}.XXXXXX")"
  cat >"$tmp" <<EOF
schema=1
mode=$HARNESS_MODE
set_id=$HARNESS_SET_ID
resource_namespace=$HARNESS_PROJECT_NAME
machine=$machine
domain=$(vm_libvirt_domain_name "$machine")
domain_uuid=$(vm_libvirt_domain_uuid "$machine")
storage_pool_name=$(vm_libvirt_storage_pool_name)
volume_name=$(vm_libvirt_machine_volume_name "$machine")
disk=$(vm_libvirt_volume_path "$(vm_libvirt_storage_pool_name)" "$(vm_libvirt_machine_volume_name "$machine")")
snapshot_name=$VM_BASELINE_SNAPSHOT_NAME
vm_set_marker_sha256=$(sha256sum "$HARNESS_VM_SET_MARKER" | awk '{print $1}')
baseline_prereqs_sha256=$(sha256sum "$HARNESS_VM_BASELINE_PREREQS_MARKER" | awk '{print $1}')
capture_run_id=$HARNESS_RUN_ID
captured_at=$(timestamp_utc)
EOF
  chmod 0600 "$tmp"
  mv -- "$tmp" "$record"
}

__vm_snapshots_verify_record() {
  local actual expected key machine record
  machine="${1:?machine required}"
  record="$(vm_path_vm_snapshot_record "$machine")"
  [ -r "$record" ] || die "Missing VM baseline snapshot record: $record"
  for key in schema mode set_id resource_namespace machine domain domain_uuid \
    storage_pool_name volume_name disk snapshot_name vm_set_marker_sha256 \
    baseline_prereqs_sha256 capture_run_id captured_at; do
    actual="$(marker_value "$record" "$key" 2>/dev/null || true)"
    case "$key" in
      schema) expected=1 ;;
      mode) expected="$HARNESS_MODE" ;;
      set_id) expected="$HARNESS_SET_ID" ;;
      resource_namespace) expected="$HARNESS_PROJECT_NAME" ;;
      machine) expected="$machine" ;;
      domain) expected="$(vm_libvirt_domain_name "$machine")" ;;
      domain_uuid) expected="$(vm_libvirt_domain_uuid "$machine")" ;;
      storage_pool_name) expected="$(vm_libvirt_storage_pool_name)" ;;
      volume_name) expected="$(vm_libvirt_machine_volume_name "$machine")" ;;
      disk) expected="$(vm_libvirt_volume_path "$(vm_libvirt_storage_pool_name)" "$(vm_libvirt_machine_volume_name "$machine")")" ;;
      snapshot_name) expected="$VM_BASELINE_SNAPSHOT_NAME" ;;
      vm_set_marker_sha256) expected="$(sha256sum "$HARNESS_VM_SET_MARKER" | awk '{print $1}')" ;;
      baseline_prereqs_sha256) expected="$(sha256sum "$HARNESS_VM_BASELINE_PREREQS_MARKER" | awk '{print $1}')" ;;
      capture_run_id|captured_at) expected="$actual" ;;
    esac
    [ -n "$actual" ] && [ "$actual" = "$expected" ] ||
      die "VM baseline snapshot record mismatch for $machine ($key)"
  done
  __vm_snapshots_exists "$machine" ||
    die "Missing libvirt baseline snapshot for $machine: $VM_BASELINE_SNAPSHOT_NAME"
}

vm_snapshots_verify() {
  local machine
  for machine in "${vm_machines[@]}"; do
    __vm_snapshots_verify_record "$machine" || return $?
  done
}

vm_snapshots_capture() {
  local created domain machine status
  status="$(vm_snapshots_status)"
  case "$status" in
    ready)
      printf 'baseline-snapshot=ready source=existing\n'
      return 0
      ;;
    stale)
      die "Incomplete or mismatched VM baseline snapshot state; destroy the selected VM set before retrying create"
      ;;
  esac
  vm_baseline_require_ready
  created=""
  for machine in "${vm_machines[@]}"; do
    domain="$(vm_libvirt_domain_name "$machine")"
    case "$(vm_libvirt_domain_state "$machine")" in
      'shut off'|shut*) ;;
      *) die "VM domain must be shut off before baseline snapshot capture: $domain" ;;
    esac
    if ! virsh -c "$VM_LIBVIRT_URI" snapshot-create-as "$domain" \
      --name "$VM_BASELINE_SNAPSHOT_NAME" \
      --description "Loopforge clean baseline for $HARNESS_SET_ID" \
      --atomic >/dev/null; then
      for domain in $created; do
        virsh -c "$VM_LIBVIRT_URI" snapshot-delete "$domain" \
          "$VM_BASELINE_SNAPSHOT_NAME" >/dev/null 2>&1 || true
      done
      rm -rf -- "$HARNESS_VM_SNAPSHOT_DIR"
      return 1
    fi
    created="$created $domain"
    if ! __vm_snapshots_write_record "$machine"; then
      for domain in $created; do
        virsh -c "$VM_LIBVIRT_URI" snapshot-delete "$domain" \
          "$VM_BASELINE_SNAPSHOT_NAME" >/dev/null 2>&1 || true
      done
      rm -rf -- "$HARNESS_VM_SNAPSHOT_DIR"
      return 1
    fi
  done
  vm_snapshots_verify || return $?
  printf 'baseline-snapshot=ready source=captured\n'
}

vm_snapshots_restore() {
  local machine
  vm_baseline_require_ready || return $?
  vm_set_verify_selected_ownership || return $?
  vm_snapshots_verify || return $?
  vm_libvirt_require_set_shut_off restore-baseline || return $?
  for machine in "${vm_machines[@]}"; do
    virsh -c "$VM_LIBVIRT_URI" snapshot-revert \
      "$(vm_libvirt_domain_name "$machine")" \
      "$VM_BASELINE_SNAPSHOT_NAME" >/dev/null || return $?
    case "$(vm_libvirt_domain_state "$machine")" in
      'shut off'|shut*) ;;
      *) die "Baseline restore did not leave VM domain shut off: $(vm_libvirt_domain_name "$machine")" ;;
    esac
  done
  vm_set_verify_selected_ownership || return $?
  vm_snapshots_verify || return $?
  printf 'baseline-restore=ready\n'
}

vm_snapshots_status() {
  local machine present
  present=0
  for machine in "${vm_machines[@]}"; do
    [ -f "$(vm_path_vm_snapshot_record "$machine")" ] && present=$((present + 1))
  done
  if [ "$present" -eq 0 ]; then
    printf 'pending'
  elif [ "$present" -ne "${#vm_machines[@]}" ]; then
    printf 'stale'
  elif vm_snapshots_verify >/dev/null 2>&1; then
    printf 'ready'
  else
    printf 'stale'
  fi
}

vm_snapshots_audit_readonly() {
  [ ! -d "$HARNESS_VM_SNAPSHOT_DIR" ] || {
    vm_set_verify_selected_ownership || return $?
    vm_snapshots_verify
  }
}
