#!/usr/bin/env bash

vm_libvirt_domain_prefix() {
  printf '%s-' "$HARNESS_PROJECT_NAME"
}

vm_libvirt_domain_name() {
  printf '%s%s' "$(vm_libvirt_domain_prefix)" "${1:?machine required}"
}

__vm_libvirt_bake_domain_name() {
  printf '%sbase-image-bake\n' "$(vm_libvirt_domain_prefix)"
}

__vm_libvirt_bake_machine_mac() {
  local digest
  digest="$(printf '%s:%s:%s\n' "$HARNESS_PROJECT_NAME" "$LOOPFORGE_VM_SET_ID" base-image-bake |
    sha256sum | awk '{print $1}')"
  printf '52:54:00:%s:%s:%s\n' \
    "${digest:0:2}" "${digest:2:2}" "${digest:4:2}"
}

vm_libvirt_network_name() {
  printf '%s-net' "$HARNESS_PROJECT_NAME"
}

vm_libvirt_bridge_name() {
  local digest
  digest="$(printf '%s:%s\n' "$HARNESS_PROJECT_NAME" "$LOOPFORGE_VM_SET_ID" |
    sha256sum | awk '{print $1}')"
  printf 'lf-%s\n' "${digest:0:8}"
}

__vm_libvirt_network_gateway() {
  python3 - "$VM_NETWORK_CIDR" <<'PY'
import ipaddress
import sys
network = ipaddress.ip_network(sys.argv[1], strict=False)
hosts = list(network.hosts())
if not hosts:
    raise SystemExit(f"VM_NETWORK_CIDR has no usable gateway address: {sys.argv[1]}")
print(hosts[0])
PY
}

vm_libvirt_storage_pool_name() {
  printf '%s-images' "$HARNESS_PROJECT_NAME"
}

vm_libvirt_baked_base_image_pool_name_for_fingerprint() {
  local digest fingerprint target
  fingerprint="${1:?fingerprint required}"
  target="$(vm_path_baked_base_image_volume_dir "$fingerprint")"
  digest="$(printf '%s\n' "$target" | sha256sum | awk '{print $1}')"
  printf 'loopforge-vm-base-%s\n' "${digest:0:16}"
}

vm_libvirt_baked_base_image_pool_name() {
  vm_libvirt_baked_base_image_pool_name_for_fingerprint \
    "${VM_BAKED_BASE_IMAGE_FINGERPRINT:?baked base image fingerprint required}"
}

vm_libvirt_baked_base_image_volume_name() {
  printf 'base.qcow2\n'
}

vm_libvirt_machine_volume_name() {
  printf '%s.qcow2\n' "${1:?machine required}"
}

vm_libvirt_seed_pool_name() {
  printf '%s-seed' "$HARNESS_PROJECT_NAME"
}

__vm_libvirt_machine_mac() {
  local machine digest
  machine="${1:?machine required}"
  digest="$(printf '%s:%s:%s\n' "$HARNESS_PROJECT_NAME" "$LOOPFORGE_VM_SET_ID" "$machine" |
    sha256sum | awk '{print $1}')"
  printf '52:54:00:%s:%s:%s\n' \
    "${digest:0:2}" "${digest:2:2}" "${digest:4:2}"
}

vm_libvirt_preflight_readonly() {
  local kvm_status
  require_command virsh
  require_command ssh
  require_command ssh-keygen
  require_command sha256sum
  require_command python3
  require_command awk
  require_command qemu-img
  require_command virt-install
  __vm_libvirt_require_seed_media_tool

  if [ -e /dev/kvm ]; then
    kvm_status="present"
  else
    kvm_status="missing"
  fi

  virsh -c "$VM_LIBVIRT_URI" uri >/dev/null ||
    die "Unable to query libvirt URI: $VM_LIBVIRT_URI"
  virsh -c "$VM_LIBVIRT_URI" list --all >/dev/null ||
    die "Unable to list libvirt domains read-only: $VM_LIBVIRT_URI"
  virsh -c "$VM_LIBVIRT_URI" net-list --all >/dev/null ||
    die "Unable to list libvirt networks read-only: $VM_LIBVIRT_URI"
  virsh -c "$VM_LIBVIRT_URI" pool-list --all >/dev/null ||
    die "Unable to list libvirt storage pools read-only: $VM_LIBVIRT_URI"
  printf 'libvirt=ok uri=%s kvm=%s\n' "$VM_LIBVIRT_URI" "$kvm_status"
}

vm_libvirt_machine_exists() {
  virsh -c "$VM_LIBVIRT_URI" dominfo "$(vm_libvirt_domain_name "$1")" >/dev/null 2>&1
}

vm_libvirt_domain_uuid() {
  virsh -c "$VM_LIBVIRT_URI" domuuid "$(vm_libvirt_domain_name "${1:?machine required}")"
}

vm_libvirt_network_is_active() {
  local network
  network="$(vm_libvirt_network_name)"
  virsh -c "$VM_LIBVIRT_URI" net-info "$network" 2>/dev/null |
    awk -F: '$1 == "Active" { gsub(/[[:space:]]/, "", $2); if ($2 == "yes") found = 1 } END { exit !found }'
}

vm_libvirt_domain_state() {
  local machine
  machine="${1:?machine required}"
  virsh -c "$VM_LIBVIRT_URI" domstate "$(vm_libvirt_domain_name "$machine")" 2>/dev/null ||
    printf 'missing\n'
}

__vm_libvirt_start_machine() {
  local machine state
  machine="${1:?machine required}"
  vm_libvirt_machine_exists "$machine" ||
    die "Missing VM domain for $machine: $(vm_libvirt_domain_name "$machine")"
  state="$(vm_libvirt_domain_state "$machine")"
  case "$state" in
    running) ;;
    'shut off'|shut*)
      virsh -c "$VM_LIBVIRT_URI" start "$(vm_libvirt_domain_name "$machine")" >/dev/null
      ;;
    *)
      die "VM domain $machine is not startable from state: $state"
      ;;
  esac
}

vm_libvirt_start_set() {
  local machine
  vm_libvirt_define_network
  for machine in "${vm_machines[@]}"; do
    __vm_libvirt_start_machine "$machine"
  done
}

vm_libvirt_shutdown_set() {
  local machine domain state deadline stopped forced
  local -a requested pending next_pending
  requested=()
  pending=()
  stopped=0
  forced=0

  for machine in "${vm_machines[@]}"; do
    domain="$(vm_libvirt_domain_name "$machine")"
    vm_libvirt_machine_exists "$machine" || {
      printf 'shutdown-skip machine=%s domain=%s state=missing\n' "$machine" "$domain"
      continue
    }
    state="$(vm_libvirt_domain_state "$machine")"
    case "$state" in
      running)
        printf 'shutdown-request machine=%s domain=%s method=graceful\n' "$machine" "$domain"
        virsh -c "$VM_LIBVIRT_URI" shutdown "$domain" >/dev/null || true
        requested+=("$machine")
        ;;
      'shut off'|shut*)
        printf 'shutdown-skip machine=%s domain=%s state=shut-off\n' "$machine" "$domain"
        ;;
      missing)
        printf 'shutdown-skip machine=%s domain=%s state=missing\n' "$machine" "$domain"
        ;;
      *)
        die "VM domain $machine is in unexpected state for down: $state"
        ;;
    esac
  done

  [ "${#requested[@]}" -gt 0 ] || {
    printf 'shutdown=ready stopped=0 forced=0\n'
    return 0
  }

  pending=("${requested[@]}")
  deadline=$((SECONDS + VM_OPERATOR_SSH_TIMEOUT_SECONDS))
  while [ "${#pending[@]}" -gt 0 ] && [ "$SECONDS" -lt "$deadline" ]; do
    next_pending=()
    for machine in "${pending[@]}"; do
      domain="$(vm_libvirt_domain_name "$machine")"
      state="$(vm_libvirt_domain_state "$machine")"
      printf 'shutdown-state machine=%s domain=%s state=%s\n' "$machine" "$domain" "$state"
      case "$state" in
        'shut off'|shut*|missing)
          stopped=$((stopped + 1))
          ;;
        running)
          next_pending+=("$machine")
          ;;
        *)
          die "VM domain $machine is in unexpected state for down: $state"
          ;;
      esac
    done
    pending=("${next_pending[@]}")
    [ "${#pending[@]}" -eq 0 ] && break
    sleep "$VM_OPERATOR_SSH_POLL_SECONDS"
  done

  for machine in "${pending[@]}"; do
    domain="$(vm_libvirt_domain_name "$machine")"
    state="$(vm_libvirt_domain_state "$machine")"
    case "$state" in
      running)
        printf 'shutdown-force machine=%s domain=%s method=destroy\n' "$machine" "$domain"
        virsh -c "$VM_LIBVIRT_URI" destroy "$domain" >/dev/null || return $?
        forced=$((forced + 1))
        ;;
      'shut off'|shut*|missing)
        ;;
      *)
        die "VM domain $machine is in unexpected state for down: $state"
        ;;
    esac
  done

  for machine in "${pending[@]}"; do
    domain="$(vm_libvirt_domain_name "$machine")"
    state="$(vm_libvirt_domain_state "$machine")"
    case "$state" in
      'shut off'|shut*|missing) stopped=$((stopped + 1)) ;;
      *) die "Failed to stop VM domain during down: $domain state=$state" ;;
    esac
  done
  printf 'shutdown=ready stopped=%s forced=%s\n' "$stopped" "$forced"
}

vm_libvirt_machine_ip() {
  local machine mac network
  machine="${1:?machine required}"
  mac="$(__vm_libvirt_machine_mac "$machine")"
  network="$(vm_libvirt_network_name)"
  virsh -c "$VM_LIBVIRT_URI" net-dhcp-leases "$network" --mac "$mac" 2>/dev/null |
    awk '$0 ~ /ipv4/ { split($5, address, "/"); print address[1]; found = 1; exit } END { exit !found }'
}

vm_libvirt_require_running() {
  local machine state
  machine="${1:?machine required}"
  state="$(vm_libvirt_domain_state "$machine")"
  [ "$state" = "running" ] ||
    die "VM domain is not running for $machine: $state"
}

vm_libvirt_status_readonly() {
  local resource_status
  resource_status="$(vm_libvirt_selected_resource_status)"
  printf 'libvirt-uri=%s vm-resources=%s\n' "$VM_LIBVIRT_URI" "$resource_status"
}

vm_libvirt_status_table() {
  local machine state ip
  for machine in "${vm_machines[@]}"; do
    state="$(vm_libvirt_domain_state "$machine")"
    ip="$(vm_libvirt_machine_ip "$machine" 2>/dev/null || true)"
    [ -n "$ip" ] || ip="pending-up"
    printf '%s domain=%s state=%s ssh=%s\n' \
      "$machine" "$(vm_libvirt_domain_name "$machine")" "$state" "$ip"
  done
}

vm_libvirt_list_selected_domains() {
  local prefix
  prefix="$(vm_libvirt_domain_prefix)"
  virsh -c "$VM_LIBVIRT_URI" list --all --name 2>/dev/null |
    awk -v prefix="$prefix" 'index($0, prefix) == 1 { print }'
}

vm_libvirt_selected_network_exists() {
  local name
  name="$(vm_libvirt_network_name)"
  virsh -c "$VM_LIBVIRT_URI" net-list --all --name 2>/dev/null |
    awk -v name="$name" '$0 == name { found = 1 } END { exit !found }'
}

__vm_libvirt_selected_pool_exists() {
  local name
  name="${1:?pool name required}"
  virsh -c "$VM_LIBVIRT_URI" pool-list --all --name 2>/dev/null |
    awk -v name="$name" '$0 == name { found = 1 } END { exit !found }'
}

vm_libvirt_selected_resources_exist() {
  local storage_pool seed_pool
  storage_pool="$(vm_libvirt_storage_pool_name)"
  seed_pool="$(vm_libvirt_seed_pool_name)"
  [ -n "$(vm_libvirt_list_selected_domains)" ] && return 0
  vm_libvirt_selected_network_exists && return 0
  __vm_libvirt_selected_pool_exists "$storage_pool" && return 0
  __vm_libvirt_selected_pool_exists "$seed_pool" && return 0
  return 1
}

vm_libvirt_selected_resource_status() {
  if ! command -v virsh >/dev/null 2>&1; then
    printf 'unavailable'
    return 0
  fi
  if ! virsh -c "$VM_LIBVIRT_URI" uri >/dev/null 2>&1; then
    printf 'unavailable'
    return 0
  fi
  if vm_libvirt_selected_resources_exist; then
    printf 'present'
  else
    printf 'absent'
  fi
}
