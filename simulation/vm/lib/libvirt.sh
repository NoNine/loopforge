#!/usr/bin/env bash

VM_LIBVIRT_URI="${VM_LIBVIRT_URI:-qemu:///system}"
VM_BASELINE_SNAPSHOT_NAME="${VM_BASELINE_SNAPSHOT_NAME:-loopforge-clean-baseline}"
VM_BASE_IMAGE_BAKE_SCHEMA_VERSION=3
vm_machines=(bundle-factory ldap gerrit jenkins-controller jenkins-agent)

vm_libvirt_domain_prefix() {
  printf '%s-' "$HARNESS_PROJECT_NAME"
}

vm_libvirt_domain_name() {
  printf '%s%s' "$(vm_libvirt_domain_prefix)" "${1:?machine required}"
}

vm_libvirt_bake_domain_name() {
  printf '%sbase-image-bake\n' "$(vm_libvirt_domain_prefix)"
}

vm_libvirt_bake_machine_mac() {
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

vm_libvirt_network_gateway() {
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

vm_libvirt_seed_pool_name() {
  printf '%s-seed' "$HARNESS_PROJECT_NAME"
}

vm_libvirt_machine_mac() {
  local machine digest
  machine="${1:?machine required}"
  digest="$(printf '%s:%s:%s\n' "$HARNESS_PROJECT_NAME" "$LOOPFORGE_VM_SET_ID" "$machine" |
    sha256sum | awk '{print $1}')"
  printf '52:54:00:%s:%s:%s\n' \
    "${digest:0:2}" "${digest:2:2}" "${digest:4:2}"
}

vm_libvirt_marker_values() {
  VM_SET_MARKER_SCHEMA_VERSION=2
  VM_SET_MARKER_LIBVIRT_URI="$VM_LIBVIRT_URI"
  VM_SET_MARKER_DOMAIN_PREFIX="$(vm_libvirt_domain_prefix)"
  VM_SET_MARKER_NETWORK_NAME="$(vm_libvirt_network_name)"
  VM_SET_MARKER_STORAGE_POOL_NAME="$(vm_libvirt_storage_pool_name)"
  VM_SET_MARKER_SEED_POOL_NAME="$(vm_libvirt_seed_pool_name)"
  VM_SET_MARKER_BASELINE_SNAPSHOT_NAME="$VM_BASELINE_SNAPSHOT_NAME"
}

vm_libvirt_require_seed_media_tool() {
  command -v cloud-localds >/dev/null 2>&1 && return 0
  command -v genisoimage >/dev/null 2>&1 && return 0
  command -v mkisofs >/dev/null 2>&1 && return 0
  die "Missing required VM seed media tool: cloud-localds, genisoimage, or mkisofs"
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
  vm_libvirt_require_seed_media_tool

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

vm_libvirt_require_base_image() {
  require_readable_file "VM_BASE_IMAGE_PATH" "$VM_BASE_IMAGE_PATH"
}

vm_libvirt_network_xml_path() {
  printf '%s/network.xml\n' "$(vm_path_vm_set_libvirt_dir)"
}

vm_libvirt_domain_xml_path() {
  printf '%s/%s.xml\n' "$(vm_path_vm_set_machine_dir)" "${1:?machine required}"
}

vm_libvirt_disk_path() {
  printf '%s/%s.qcow2\n' "$(vm_path_vm_set_disk_dir)" "${1:?machine required}"
}

vm_libvirt_bake_work_dir() {
  printf '%s/bake-work-%s-%s\n' \
    "$(vm_path_baked_base_image_dir "${VM_BAKED_BASE_IMAGE_FINGERPRINT:?baked base image fingerprint required}")" \
    "$HARNESS_PROJECT_NAME" "$$"
}

vm_libvirt_bake_disk_path() {
  printf '%s/base-build.qcow2\n' "$(vm_libvirt_bake_work_dir)"
}

vm_libvirt_bake_domain_xml_path() {
  printf '%s/base-image-bake.xml\n' "$(vm_libvirt_bake_work_dir)"
}

vm_libvirt_bake_seed_iso_path() {
  printf '%s/base-image-bake-seed.iso\n' "$(vm_libvirt_bake_work_dir)"
}

vm_libvirt_bake_seed_work_dir() {
  printf '%s/seed\n' "$(vm_libvirt_bake_work_dir)"
}

vm_libvirt_seed_iso_path() {
  printf '%s/%s-seed.iso\n' "$(vm_path_vm_set_seed_dir)" "${1:?machine required}"
}

vm_libvirt_seed_work_dir() {
  printf '%s/%s\n' "$(vm_path_vm_set_seed_dir)" "${1:?machine required}"
}

vm_libvirt_machine_metadata_path() {
  vm_path_vm_machine_file "${1:?machine required}"
}

vm_libvirt_baked_base_image_fingerprint_file() {
  printf '%s/base-image-fingerprint.txt\n' "$HARNESS_RENDERED_DIR"
}

vm_libvirt_baked_base_image_fingerprint() {
  local machine
  {
    printf 'schema=%s\n' "$VM_BASE_IMAGE_BAKE_SCHEMA_VERSION"
    printf 'source_sha256=%s\n' "$(sha256sum "$VM_BASE_IMAGE_PATH" | awk '{print $1}')"
    printf 'ubuntu_release=%s\n' "$HARNESS_UBUNTU_BASELINE_RELEASE"
    printf 'ubuntu_codename=%s\n' "$HARNESS_UBUNTU_BASELINE_CODENAME"
    printf 'apt_mirror=%s\n' "$HARNESS_UBUNTU_APT_MIRROR"
    printf 'source_boundary=%s\n' "$HARNESS_PUBLIC_INTERNET_FALLBACK_LABEL"
    printf 'disk_size=%s\n' "$VM_DOMAIN_DISK_SIZE"
    for machine in "${vm_machines[@]}"; do
      printf 'packages.%s=%s\n' "$machine" "$(vm_libvirt_package_list_csv "$machine")"
    done
  } | sha256sum | awk '{print $1}'
}

vm_libvirt_select_baked_base_image() {
  local fingerprint_file
  VM_BAKED_BASE_IMAGE_FINGERPRINT="$(vm_libvirt_baked_base_image_fingerprint)" || return $?
  fingerprint_file="$(vm_libvirt_baked_base_image_fingerprint_file)"
  mkdir -p "$(dirname "$fingerprint_file")" || return $?
  printf '%s\n' "$VM_BAKED_BASE_IMAGE_FINGERPRINT" >"$fingerprint_file" || return $?
  chmod 0600 "$fingerprint_file" || return $?
}

vm_libvirt_baked_base_image_path() {
  vm_path_baked_base_image "${VM_BAKED_BASE_IMAGE_FINGERPRINT:?baked base image fingerprint required}"
}

vm_libvirt_baked_base_image_marker_path() {
  vm_path_baked_base_image_marker "${VM_BAKED_BASE_IMAGE_FINGERPRINT:?baked base image fingerprint required}"
}

vm_libvirt_machine_exists() {
  virsh -c "$VM_LIBVIRT_URI" dominfo "$(vm_libvirt_domain_name "$1")" >/dev/null 2>&1
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

vm_libvirt_render_network_xml() {
  local machine machine_args xml
  xml="$(vm_libvirt_network_xml_path)"
  machine_args=()
  for machine in "${vm_machines[@]}"; do
    machine_args+=("$machine=$(vm_libvirt_machine_mac "$machine")")
  done
  mkdir -p "$(dirname "$xml")"
  python3 - "$VM_NETWORK_CIDR" "$(vm_libvirt_network_name)" "$(vm_libvirt_bridge_name)" \
    "$HARNESS_LDAP_DOMAIN" "${machine_args[@]}" >"$xml" <<'PY'
import ipaddress
import sys
cidr = sys.argv[1]
name = sys.argv[2]
bridge_name = sys.argv[3]
dns_domain = sys.argv[4].strip(".")
machines = []
for spec in sys.argv[5:]:
    machine, mac = spec.split("=", 1)
    machines.append((machine, mac))
network = ipaddress.ip_network(cidr, strict=False)
hosts = list(network.hosts())
if len(hosts) < len(machines) + 4:
    raise SystemExit(f"VM_NETWORK_CIDR too small for VM harness network: {cidr}")
gateway = hosts[0]
dhcp_start = hosts[2]
dhcp_end = hosts[-2]
reserved = hosts[2:2 + len(machines)]
dns_hosts = "\n".join(
    "\n".join([
        f"    <host ip='{ip}'>",
        f"      <hostname>{machine}.{dns_domain}</hostname>",
        "    </host>",
    ])
    for (machine, _), ip in zip(machines, reserved)
)
dhcp_hosts = "\n".join(
    f"      <host mac='{mac}' ip='{ip}'/>"
    for (machine, mac), ip in zip(machines, reserved)
)
print(f"""<network>
  <name>{name}</name>
  <forward mode='nat'/>
  <bridge name='{bridge_name}' stp='on' delay='0'/>
  <dns>
{dns_hosts}
  </dns>
  <ip address='{gateway}' netmask='{network.netmask}'>
    <dhcp>
      <range start='{dhcp_start}' end='{dhcp_end}'/>
{dhcp_hosts}
    </dhcp>
  </ip>
</network>""")
PY
  chmod 0600 "$xml"
}

vm_libvirt_render_domain_xml() {
  local machine domain disk seed mac xml
  machine="${1:?machine required}"
  domain="$(vm_libvirt_domain_name "$machine")"
  disk="$(vm_libvirt_disk_path "$machine")"
  seed="$(vm_libvirt_seed_iso_path "$machine")"
  mac="$(vm_libvirt_machine_mac "$machine")"
  xml="$(vm_libvirt_domain_xml_path "$machine")"
  mkdir -p "$(dirname "$xml")"
  cat >"$xml" <<EOF
<domain type='kvm'>
  <name>$domain</name>
  <memory unit='MiB'>$VM_DOMAIN_MEMORY_MIB</memory>
  <currentMemory unit='MiB'>$VM_DOMAIN_MEMORY_MIB</currentMemory>
  <vcpu placement='static'>$VM_DOMAIN_VCPUS</vcpu>
  <os>
    <type arch='x86_64'>hvm</type>
    <boot dev='hd'/>
  </os>
  <features>
    <acpi/>
    <apic/>
  </features>
  <cpu mode='host-model' check='partial'/>
  <devices>
    <emulator>/usr/bin/qemu-system-x86_64</emulator>
    <disk type='file' device='disk'>
      <driver name='qemu' type='qcow2'/>
      <source file='$disk'/>
      <target dev='vda' bus='virtio'/>
    </disk>
    <disk type='file' device='cdrom'>
      <driver name='qemu' type='raw'/>
      <source file='$seed'/>
      <target dev='sda' bus='sata'/>
      <readonly/>
    </disk>
    <interface type='network'>
      <mac address='$mac'/>
      <source network='$(vm_libvirt_network_name)'/>
      <model type='virtio'/>
    </interface>
    <serial type='pty'>
      <target port='0'/>
    </serial>
    <console type='pty'>
      <target type='serial' port='0'/>
    </console>
    <graphics type='vnc' listen='127.0.0.1' autoport='yes'/>
  </devices>
</domain>
EOF
  chmod 0600 "$xml"
}

vm_libvirt_render_bake_domain_xml() {
  local domain disk seed mac xml
  domain="$(vm_libvirt_bake_domain_name)"
  disk="$(vm_libvirt_bake_disk_path)"
  seed="$(vm_libvirt_bake_seed_iso_path)"
  mac="$(vm_libvirt_bake_machine_mac)"
  xml="$(vm_libvirt_bake_domain_xml_path)"
  mkdir -p "$(dirname "$xml")"
  cat >"$xml" <<EOF
<domain type='kvm'>
  <name>$domain</name>
  <memory unit='MiB'>$VM_DOMAIN_MEMORY_MIB</memory>
  <currentMemory unit='MiB'>$VM_DOMAIN_MEMORY_MIB</currentMemory>
  <vcpu placement='static'>$VM_DOMAIN_VCPUS</vcpu>
  <os>
    <type arch='x86_64'>hvm</type>
    <boot dev='hd'/>
  </os>
  <features>
    <acpi/>
    <apic/>
  </features>
  <cpu mode='host-model' check='partial'/>
  <devices>
    <emulator>/usr/bin/qemu-system-x86_64</emulator>
    <disk type='file' device='disk'>
      <driver name='qemu' type='qcow2'/>
      <source file='$disk'/>
      <target dev='vda' bus='virtio'/>
    </disk>
    <disk type='file' device='cdrom'>
      <driver name='qemu' type='raw'/>
      <source file='$seed'/>
      <target dev='sda' bus='sata'/>
      <readonly/>
    </disk>
    <interface type='network'>
      <mac address='$mac'/>
      <source network='$(vm_libvirt_network_name)'/>
      <model type='virtio'/>
    </interface>
    <serial type='pty'>
      <target port='0'/>
    </serial>
    <console type='pty'>
      <target type='serial' port='0'/>
    </console>
    <graphics type='vnc' listen='127.0.0.1' autoport='yes'/>
  </devices>
</domain>
EOF
  chmod 0600 "$xml"
}

vm_libvirt_render_seed_media() {
  local machine work_dir user_data meta_data network_config seed_iso mac public_key dns_gateway
  machine="${1:?machine required}"
  work_dir="$(vm_libvirt_seed_work_dir "$machine")"
  user_data="$work_dir/user-data"
  meta_data="$work_dir/meta-data"
  network_config="$work_dir/network-config"
  seed_iso="$(vm_libvirt_seed_iso_path "$machine")"
  mac="$(vm_libvirt_machine_mac "$machine")"
  public_key="$(cat "$HARNESS_TARGET_SSH_IDENTITY_FILE.pub")"
  dns_gateway="$(vm_libvirt_network_gateway)"
  mkdir -p "$work_dir"
  cat >"$user_data" <<EOF
#cloud-config
users:
  - default
  - name: $VM_OPERATOR_USER
    gecos: Loopforge simulation operator
    groups: sudo
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    lock_passwd: true
    ssh_authorized_keys:
      - $public_key
ssh_pwauth: false
disable_root: true
package_update: false
runcmd:
  - [ cloud-init-per, once, loopforge-ssh-enable, systemctl, enable, --now, ssh ]
EOF
  cat >"$meta_data" <<EOF
instance-id: $HARNESS_PROJECT_NAME-$machine
local-hostname: $machine
EOF
  cat >"$network_config" <<EOF
version: 2
ethernets:
  harness0:
    match:
      macaddress: "$mac"
    set-name: ens3
    dhcp4: true
    nameservers:
      addresses:
        - $dns_gateway
      search:
        - $HARNESS_LDAP_DOMAIN
EOF
  if command -v cloud-localds >/dev/null 2>&1; then
    cloud-localds --network-config="$network_config" "$seed_iso" "$user_data" "$meta_data"
  elif command -v genisoimage >/dev/null 2>&1; then
    (cd "$work_dir" && genisoimage -quiet -output "$seed_iso" -volid cidata -joliet -rock \
      user-data meta-data network-config)
  else
    (cd "$work_dir" && mkisofs -quiet -output "$seed_iso" -volid cidata -joliet -rock \
      user-data meta-data network-config)
  fi
  chmod 0600 "$user_data" "$meta_data" "$network_config" "$seed_iso"
}

vm_libvirt_render_bake_seed_media() {
  local work_dir user_data meta_data network_config seed_iso mac public_key dns_gateway
  work_dir="$(vm_libvirt_bake_seed_work_dir)"
  user_data="$work_dir/user-data"
  meta_data="$work_dir/meta-data"
  network_config="$work_dir/network-config"
  seed_iso="$(vm_libvirt_bake_seed_iso_path)"
  mac="$(vm_libvirt_bake_machine_mac)"
  public_key="$(cat "$HARNESS_TARGET_SSH_IDENTITY_FILE.pub")"
  dns_gateway="$(vm_libvirt_network_gateway)"
  mkdir -p "$work_dir"
  cat >"$user_data" <<EOF
#cloud-config
users:
  - default
  - name: $VM_OPERATOR_USER
    gecos: Loopforge simulation operator
    groups: sudo
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    lock_passwd: true
    ssh_authorized_keys:
      - $public_key
ssh_pwauth: false
disable_root: true
package_update: false
runcmd:
  - [ cloud-init-per, once, loopforge-ssh-enable, systemctl, enable, --now, ssh ]
EOF
  cat >"$meta_data" <<EOF
instance-id: $HARNESS_PROJECT_NAME-base-image-bake
local-hostname: base-image-bake
EOF
  cat >"$network_config" <<EOF
version: 2
ethernets:
  harness0:
    match:
      macaddress: "$mac"
    set-name: ens3
    dhcp4: true
    nameservers:
      addresses:
        - $dns_gateway
      search:
        - $HARNESS_LDAP_DOMAIN
EOF
  if command -v cloud-localds >/dev/null 2>&1; then
    cloud-localds --network-config="$network_config" "$seed_iso" "$user_data" "$meta_data"
  elif command -v genisoimage >/dev/null 2>&1; then
    (cd "$work_dir" && genisoimage -quiet -output "$seed_iso" -volid cidata -joliet -rock \
      user-data meta-data network-config)
  else
    (cd "$work_dir" && mkisofs -quiet -output "$seed_iso" -volid cidata -joliet -rock \
      user-data meta-data network-config)
  fi
  chmod 0600 "$user_data" "$meta_data" "$network_config" "$seed_iso"
}

vm_libvirt_write_machine_metadata() {
  local machine file disk baked_image baked_sha256 disk_virtual_size_bytes
  machine="${1:?machine required}"
  file="$(vm_libvirt_machine_metadata_path "$machine")"
  disk="$(vm_libvirt_disk_path "$machine")"
  baked_image="$(vm_libvirt_baked_base_image_path)"
  baked_sha256="$(marker_value "$(vm_libvirt_baked_base_image_marker_path)" baked_sha256)"
  disk_virtual_size_bytes="$(vm_libvirt_disk_virtual_size_bytes "$disk")" || return $?
  mkdir -p "$(dirname "$file")"
  cat >"$file" <<EOF
machine=$machine
domain=$(vm_libvirt_domain_name "$machine")
mac=$(vm_libvirt_machine_mac "$machine")
disk=$disk
disk_size=$VM_DOMAIN_DISK_SIZE
disk_virtual_size_bytes=$disk_virtual_size_bytes
base_image=$baked_image
base_image_fingerprint=$VM_BAKED_BASE_IMAGE_FINGERPRINT
base_image_sha256=$baked_sha256
seed_iso=$(vm_libvirt_seed_iso_path "$machine")
ssh_user=$VM_OPERATOR_USER
ssh_host=pending-up
ssh_port=22
EOF
  chmod 0600 "$file"
}

vm_libvirt_disk_backing_image() {
  local disk
  disk="${1:?disk required}"
  qemu-img info --output=json "$disk" |
    python3 -c '
import json
import os
import sys

disk = os.path.abspath(sys.argv[1])
data = json.load(sys.stdin)
backing = data.get("full-backing-filename") or data.get("backing-filename")
if not backing:
    raise SystemExit(f"VM disk has no qcow2 backing image: {disk}")
if not os.path.isabs(backing):
    backing = os.path.join(os.path.dirname(disk), backing)
print(os.path.abspath(backing))
' "$disk"
}

vm_libvirt_disk_virtual_size_bytes() {
  local disk
  disk="${1:?disk required}"
  qemu-img info --output=json "$disk" |
    python3 -c '
import json
import sys

value = json.load(sys.stdin).get("virtual-size")
if not isinstance(value, int) or value <= 0:
    raise SystemExit("VM disk has no valid virtual-size")
print(value)
'
}

vm_libvirt_verify_existing_disk_identity() {
  local machine disk metadata expected_image expected_sha actual_backing key expected actual
  local recorded_virtual_size actual_virtual_size
  machine="${1:?machine required}"
  disk="$(vm_libvirt_disk_path "$machine")"
  metadata="$(vm_libvirt_machine_metadata_path "$machine")"
  expected_image="$(vm_libvirt_baked_base_image_path)"
  expected_sha="$(marker_value "$(vm_libvirt_baked_base_image_marker_path)" baked_sha256)"
  [ -r "$metadata" ] || {
    printf 'ERROR: Existing VM disk metadata is incompatible for %s: %s. %s\n' \
      "$machine" "$metadata" "Select a fresh HARNESS_RUN_ID and LOOPFORGE_VM_SET_ID; retain this set for M5 down/destroy cleanup." >&2
    return 1
  }
  for key in disk disk_size base_image base_image_fingerprint base_image_sha256; do
    case "$key" in
      disk) expected="$disk" ;;
      disk_size) expected="$VM_DOMAIN_DISK_SIZE" ;;
      base_image) expected="$expected_image" ;;
      base_image_fingerprint) expected="$VM_BAKED_BASE_IMAGE_FINGERPRINT" ;;
      base_image_sha256) expected="$expected_sha" ;;
    esac
    actual="$(marker_value "$metadata" "$key" 2>/dev/null || true)"
    [ "$actual" = "$expected" ] || {
      printf 'ERROR: Existing VM disk identity mismatch for %s (%s). %s\n' \
        "$machine" "$key" "Select a fresh HARNESS_RUN_ID and LOOPFORGE_VM_SET_ID; retain this set for M5 down/destroy cleanup." >&2
      return 1
    }
  done
  actual_backing="$(vm_libvirt_disk_backing_image "$disk")" || return $?
  [ "$actual_backing" = "$expected_image" ] || {
    printf 'ERROR: Existing VM disk backing image mismatch for %s. %s\n' \
      "$machine" "Select a fresh HARNESS_RUN_ID and LOOPFORGE_VM_SET_ID; retain this set for M5 down/destroy cleanup." >&2
    return 1
  }
  recorded_virtual_size="$(marker_value "$metadata" disk_virtual_size_bytes 2>/dev/null || true)"
  actual_virtual_size="$(vm_libvirt_disk_virtual_size_bytes "$disk")" || return $?
  if [ -z "$recorded_virtual_size" ] || [ "$actual_virtual_size" != "$recorded_virtual_size" ]; then
    printf 'ERROR: Existing VM disk virtual size mismatch for %s. %s\n' \
      "$machine" "Select a fresh HARNESS_RUN_ID and LOOPFORGE_VM_SET_ID; retain this set for M5 down/destroy cleanup." >&2
    return 1
  fi
}

vm_libvirt_verify_existing_disk_identities() {
  local machine disk
  for machine in "${vm_machines[@]}"; do
    disk="$(vm_libvirt_disk_path "$machine")"
    [ ! -e "$disk" ] || vm_libvirt_verify_existing_disk_identity "$machine" || return $?
  done
}

vm_libvirt_existing_disks_present() {
  local machine
  for machine in "${vm_machines[@]}"; do
    [ ! -e "$(vm_libvirt_disk_path "$machine")" ] || return 0
  done
  return 1
}

vm_libvirt_require_existing_baked_base_image() {
  if vm_libvirt_baked_base_image_ready; then
    printf 'base-image-cache=hit fingerprint=%s image=%s marker=%s\n' \
      "$VM_BAKED_BASE_IMAGE_FINGERPRINT" \
      "$(vm_libvirt_baked_base_image_path)" \
      "$(vm_libvirt_baked_base_image_marker_path)"
    return 0
  fi
  printf 'ERROR: Existing VM disks require their original valid baked-image cache entry. %s\n' \
    "Select a fresh HARNESS_RUN_ID and LOOPFORGE_VM_SET_ID; retain this set for M5 down/destroy cleanup." >&2
  return 1
}

vm_libvirt_ensure_ssh_key() {
  mkdir -p "$HARNESS_TARGET_SSH_DIR"
  chmod 0700 "$HARNESS_TARGET_SSH_DIR"
  if [ ! -f "$HARNESS_TARGET_SSH_IDENTITY_FILE" ]; then
    ssh-keygen -q -t ed25519 -N '' -f "$HARNESS_TARGET_SSH_IDENTITY_FILE"
  fi
  chmod 0600 "$HARNESS_TARGET_SSH_IDENTITY_FILE"
  chmod 0644 "$HARNESS_TARGET_SSH_IDENTITY_FILE.pub"
}

vm_libvirt_create_disk() {
  local backing_image machine disk
  machine="${1:?machine required}"
  disk="$(vm_libvirt_disk_path "$machine")"
  if [ -f "$disk" ]; then
    vm_libvirt_verify_existing_disk_identity "$machine"
    return $?
  fi
  backing_image="$(vm_libvirt_baked_base_image_path)"
  require_readable_file "VM baked base image" "$backing_image" || return $?
  qemu-img create -f qcow2 -F qcow2 -b "$backing_image" "$disk" >/dev/null || return $?
  qemu-img resize "$disk" "$VM_DOMAIN_DISK_SIZE" >/dev/null || return $?
  chmod 0600 "$disk" || return $?
}

vm_libvirt_base_image_superset_packages_csv() {
  local machine package packages_file
  packages_file="$(mktemp)"
  for machine in "${vm_machines[@]}"; do
    vm_libvirt_service_packages_for_machine "$machine" >>"$packages_file"
  done
  sort -u "$packages_file" | paste -sd, -
  rm -f "$packages_file"
}

vm_libvirt_os_baseline_install_script() {
  local machine packages
  machine="${1:?machine required}"
  packages="${2:?packages required}"
  cat <<EOF
set -euo pipefail
machine=$(shell_quote "$machine")
mirror=$(shell_quote "$HARNESS_UBUNTU_APT_MIRROR")
packages_csv=$(shell_quote "$packages")
ldap_domain=$(shell_quote "$HARNESS_LDAP_DOMAIN")
ldap_package_password=loopforge-bake-password
mirror_no_slash="\${mirror%/}"
for sources_file in /etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
  [ -e "\$sources_file" ] || continue
  sudo sed -i \
    -e "s|http://archive.ubuntu.com/ubuntu/|\$mirror|g" \
    -e "s|http://archive.ubuntu.com/ubuntu|\$mirror_no_slash|g" \
    -e "s|http://security.ubuntu.com/ubuntu/|\$mirror|g" \
    -e "s|http://security.ubuntu.com/ubuntu|\$mirror_no_slash|g" \
    "\$sources_file"
done
printf 'public_internet_fallback=%s\n' $(shell_quote "$HARNESS_PUBLIC_INTERNET_FALLBACK_LABEL") | sudo tee /etc/loopforge-source-boundary >/dev/null
if printf ',%s,' "\$packages_csv" | grep -Fq ',slapd,'; then
  sudo debconf-set-selections <<DEBCONF
slapd slapd/no_configuration boolean false
slapd slapd/domain string \$ldap_domain
slapd shared/organization string Gerrit Jenkins Harness
slapd slapd/password1 password \$ldap_package_password
slapd slapd/password2 password \$ldap_package_password
slapd slapd/move_old_database boolean true
slapd slapd/purge_database boolean true
DEBCONF
fi
sudo apt-get update
IFS=, read -r -a packages <<<"\$packages_csv"
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "\${packages[@]}"
EOF
}

vm_libvirt_os_baseline_verify_script() {
  local packages
  packages="${1:?packages required}"
  cat <<EOF
set -euo pipefail
packages_csv=$(shell_quote "$packages")
IFS=, read -r -a packages <<<"\$packages_csv"
check_package_command() {
  case "\$1" in
    ca-certificates) command -v update-ca-certificates >/dev/null ;;
    curl) command -v curl >/dev/null ;;
    fontconfig) command -v fc-cache >/dev/null ;;
    git) command -v git >/dev/null ;;
    ldap-utils) command -v ldapsearch >/dev/null ;;
    openjdk-21-jre|openjdk-21-jre-headless) command -v java >/dev/null ;;
    openssh-client) command -v ssh >/dev/null ;;
    openssh-server) command -v sshd >/dev/null ;;
    rsync) command -v rsync >/dev/null ;;
    slapd) command -v slapd >/dev/null ;;
    tar) command -v tar >/dev/null ;;
    unzip) command -v unzip >/dev/null ;;
    wget) command -v wget >/dev/null ;;
    *) return 0 ;;
  esac
}
for package in "\${packages[@]}"; do
  dpkg-query -W -f='\${Status}' "\$package" | grep -Fxq 'install ok installed'
  check_package_command "\$package"
done
EOF
}

vm_libvirt_bake_domain_exists() {
  virsh -c "$VM_LIBVIRT_URI" dominfo "$(vm_libvirt_bake_domain_name)" >/dev/null 2>&1
}

vm_libvirt_bake_domain_state() {
  virsh -c "$VM_LIBVIRT_URI" domstate "$(vm_libvirt_bake_domain_name)" 2>/dev/null ||
    printf 'missing\n'
}

vm_libvirt_bake_machine_ip() {
  local mac network
  mac="$(vm_libvirt_bake_machine_mac)"
  network="$(vm_libvirt_network_name)"
  virsh -c "$VM_LIBVIRT_URI" net-dhcp-leases "$network" --mac "$mac" 2>/dev/null |
    awk '$0 ~ /ipv4/ { split($5, address, "/"); print address[1]; found = 1; exit } END { exit !found }'
}

vm_libvirt_bake_wait_host() {
  local deadline host
  deadline=$((SECONDS + VM_OPERATOR_SSH_TIMEOUT_SECONDS))
  while [ "$SECONDS" -lt "$deadline" ]; do
    host="$(vm_libvirt_bake_machine_ip 2>/dev/null || true)"
    if [ -n "$host" ]; then
      printf '%s\n' "$host"
      return 0
    fi
    sleep "$VM_OPERATOR_SSH_POLL_SECONDS"
  done
  die "Timed out waiting for DHCP lease for VM base-image bake"
}

vm_libvirt_bake_ssh_options() {
  printf '%s\n' \
    -i "$HARNESS_TARGET_SSH_IDENTITY_FILE" \
    -o UserKnownHostsFile=/dev/null \
    -o StrictHostKeyChecking=no \
    -o BatchMode=yes \
    -o ConnectTimeout=10 \
    -o LogLevel=ERROR
}

vm_libvirt_bake_wait_ready() {
  local deadline host
  host="$(vm_libvirt_bake_wait_host)"
  deadline=$((SECONDS + VM_OPERATOR_SSH_TIMEOUT_SECONDS))
  while [ "$SECONDS" -lt "$deadline" ]; do
    if ssh $(vm_libvirt_bake_ssh_options) "$VM_OPERATOR_USER@$host" 'printf ready' >/dev/null 2>&1; then
      return 0
    fi
    sleep "$VM_OPERATOR_SSH_POLL_SECONDS"
  done
  die "Timed out waiting for target OS SSH on VM base-image bake ($host)"
}

vm_libvirt_bake_run() {
  local host script
  script="${1:?script required}"
  host="$(vm_libvirt_bake_machine_ip)"
  printf '%s\n' "$script" |
    ssh $(vm_libvirt_bake_ssh_options) "$VM_OPERATOR_USER@$host" bash -s ||
    return $?
}

vm_libvirt_shutdown_bake_domain() {
  local deadline domain state
  domain="$(vm_libvirt_bake_domain_name)"
  vm_libvirt_bake_domain_exists || return 0
  state="$(vm_libvirt_bake_domain_state)"
  case "$state" in
    running)
      virsh -c "$VM_LIBVIRT_URI" shutdown "$domain" >/dev/null || true
      deadline=$((SECONDS + VM_OPERATOR_SSH_TIMEOUT_SECONDS))
      while [ "$SECONDS" -lt "$deadline" ]; do
        state="$(vm_libvirt_bake_domain_state)"
        case "$state" in
          'shut off'|shut*) return 0 ;;
        esac
        sleep "$VM_OPERATOR_SSH_POLL_SECONDS"
      done
      die "Timed out waiting for VM base-image bake shutdown: $domain"
      ;;
    'shut off'|shut*|missing) ;;
    *)
      die "VM base-image bake domain is in unexpected state: $state"
      ;;
  esac
}

vm_libvirt_cleanup_bake_domain() {
  local domain state
  domain="$(vm_libvirt_bake_domain_name)"
  vm_libvirt_bake_domain_exists || return 0
  state="$(vm_libvirt_bake_domain_state)"
  if [ "$state" = running ]; then
    virsh -c "$VM_LIBVIRT_URI" destroy "$domain" >/dev/null || return $?
  fi
  virsh -c "$VM_LIBVIRT_URI" undefine "$domain" --nvram >/dev/null 2>&1 ||
    virsh -c "$VM_LIBVIRT_URI" undefine "$domain" >/dev/null 2>&1 || return $?
  vm_libvirt_bake_domain_exists && return 1
  return 0
}

vm_libvirt_write_baked_base_image_marker() {
  local image marker packages tmp
  image="$(vm_libvirt_baked_base_image_path)"
  marker="$(vm_libvirt_baked_base_image_marker_path)"
  packages="$(vm_libvirt_base_image_superset_packages_csv)"
  tmp="$(mktemp "${marker}.XXXXXX")" || return $?
  if ! cat >"$tmp" <<EOF
schema=$VM_BASE_IMAGE_BAKE_SCHEMA_VERSION
fingerprint=$VM_BAKED_BASE_IMAGE_FINGERPRINT
source_image=$VM_BASE_IMAGE_PATH
source_sha256=$(sha256sum "$VM_BASE_IMAGE_PATH" | awk '{print $1}')
baked_image=$image
baked_sha256=$(sha256sum "$image" | awk '{print $1}')
ubuntu_release=$HARNESS_UBUNTU_BASELINE_RELEASE
ubuntu_codename=$HARNESS_UBUNTU_BASELINE_CODENAME
apt_mirror=$HARNESS_UBUNTU_APT_MIRROR
source_boundary=$HARNESS_PUBLIC_INTERNET_FALLBACK_LABEL
disk_size=$VM_DOMAIN_DISK_SIZE
packages=$packages
status=ready
EOF
  then
    rm -f "$tmp"
    return 1
  fi
  chmod 0600 "$tmp" || {
    rm -f "$tmp"
    return 1
  }
  mv -- "$tmp" "$marker"
}

vm_libvirt_baked_base_image_ready() {
  local image marker status expected_sha actual_sha
  image="$(vm_libvirt_baked_base_image_path)"
  marker="$(vm_libvirt_baked_base_image_marker_path)"
  vm_libvirt_baked_base_image_file_ready "$image" || return 1
  [ -r "$marker" ] || return 1
  status="$(marker_value "$marker" status 2>/dev/null || true)"
  [ "$status" = ready ] || return 1
  [ "$(marker_value "$marker" schema 2>/dev/null || true)" = "$VM_BASE_IMAGE_BAKE_SCHEMA_VERSION" ] || return 1
  [ "$(marker_value "$marker" fingerprint 2>/dev/null || true)" = "$VM_BAKED_BASE_IMAGE_FINGERPRINT" ] || return 1
  [ "$(marker_value "$marker" baked_image 2>/dev/null || true)" = "$image" ] || return 1
  expected_sha="$(marker_value "$marker" baked_sha256 2>/dev/null || true)"
  [ -n "$expected_sha" ] || return 1
  actual_sha="$(sha256_file "$image")" || return 1
  [ "$actual_sha" = "$expected_sha" ]
}

vm_libvirt_baked_base_image_file_ready() {
  local image
  image="${1:?image required}"
  [ -s "$image" ] || return 1
  [ -r "$image" ] || return 1
  qemu-img info --output=json "$image" 2>/dev/null |
    python3 -c 'import json, sys; raise SystemExit(0 if json.load(sys.stdin).get("format") == "qcow2" else 1)' || return 1
}

vm_libvirt_require_baked_base_image_file() {
  local image
  image="${1:?image required}"
  if [ ! -s "$image" ]; then
    printf 'ERROR: Missing or empty VM baked base image: %s\n' "$image" >&2
    return 1
  fi
  if [ ! -r "$image" ]; then
    printf 'ERROR: VM baked base image is not readable: %s\n' "$image" >&2
    return 1
  fi
  if ! vm_libvirt_baked_base_image_file_ready "$image"; then
    printf 'ERROR: VM baked base image is not a readable qcow2 image: %s\n' "$image" >&2
    return 1
  fi
}

vm_libvirt_bake_base_image() {
  local final_image packages script tmp_image
  final_image="$(vm_libvirt_baked_base_image_path)"
  tmp_image="$(vm_libvirt_bake_disk_path)"
  packages="$(vm_libvirt_base_image_superset_packages_csv)"
  if [ -e "$final_image" ] || [ -e "$(vm_libvirt_baked_base_image_marker_path)" ]; then
    printf 'ERROR: Refusing to replace an existing invalid VM baked-image cache entry: %s\n' \
      "$(dirname "$final_image")" >&2
    return 1
  fi
  mkdir -p "$(dirname "$final_image")" "$(vm_libvirt_bake_work_dir)" || return $?
  vm_libvirt_cleanup_bake_domain || return $?
  rm -f "$tmp_image" || return $?
  qemu-img create -f qcow2 -F qcow2 -b "$VM_BASE_IMAGE_PATH" "$tmp_image" >/dev/null || return $?
  qemu-img resize "$tmp_image" "$VM_DOMAIN_DISK_SIZE" >/dev/null || return $?
  vm_libvirt_render_bake_seed_media || return $?
  vm_libvirt_render_bake_domain_xml || return $?
  script="$(vm_libvirt_os_baseline_install_script base-image-bake "$packages")
$(vm_libvirt_os_baseline_verify_script "$packages")
sudo rm -f /etc/ssh/ssh_host_* || true
sudo rm -rf /var/lib/cloud/instances /var/lib/cloud/instance /var/lib/cloud/data || true
sudo cloud-init clean --logs --machine-id || true
sudo truncate -s 0 /etc/machine-id || true
sudo rm -f /var/lib/dbus/machine-id || true
sudo apt-get clean || true
sudo rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* || true
"
  if ! {
    virsh -c "$VM_LIBVIRT_URI" define "$(vm_libvirt_bake_domain_xml_path)" >/dev/null &&
      virsh -c "$VM_LIBVIRT_URI" start "$(vm_libvirt_bake_domain_name)" >/dev/null &&
      vm_libvirt_bake_wait_ready &&
      vm_libvirt_bake_run 'command -v cloud-init >/dev/null 2>&1 && sudo cloud-init status --wait >/dev/null || true' &&
      vm_libvirt_bake_run "$script" &&
      vm_libvirt_shutdown_bake_domain
  }; then
    vm_libvirt_cleanup_bake_domain || true
    rm -rf "$(vm_libvirt_bake_work_dir)" || true
    return 1
  fi
  vm_libvirt_cleanup_bake_domain || return $?
  vm_libvirt_require_baked_base_image_file "$tmp_image" || return $?
  mv "$tmp_image" "$final_image" || return $?
  vm_libvirt_require_baked_base_image_file "$final_image" || return $?
  vm_libvirt_write_baked_base_image_marker || return $?
  rm -rf "$(vm_libvirt_bake_work_dir)" || return $?
  printf 'base-image-permissions=ready image=%s\n' "$final_image"
  printf 'base-image-bake=ready fingerprint=%s image=%s packages=%s apt-mirror=%s\n' \
    "$VM_BAKED_BASE_IMAGE_FINGERPRINT" "$final_image" "$packages" "$HARNESS_UBUNTU_APT_MIRROR"
}

vm_libvirt_ensure_baked_base_image() {
  local image marker lock lock_fd rc
  [ -n "${VM_BAKED_BASE_IMAGE_FINGERPRINT:-}" ] || vm_libvirt_select_baked_base_image
  image="$(vm_libvirt_baked_base_image_path)"
  marker="$(vm_libvirt_baked_base_image_marker_path)"
  lock="$(vm_path_baked_base_image_lock "$VM_BAKED_BASE_IMAGE_FINGERPRINT")"
  mkdir -p "$(dirname "$lock")" || return $?
  exec {lock_fd}>"$lock" || return $?
  flock "$lock_fd" || {
    exec {lock_fd}>&-
    return 1
  }
  if vm_libvirt_baked_base_image_ready; then
    printf 'base-image-cache=hit fingerprint=%s image=%s marker=%s\n' \
      "$VM_BAKED_BASE_IMAGE_FINGERPRINT" "$image" "$marker"
    exec {lock_fd}>&-
    return 0
  fi
  if [ -e "$image" ] || [ -e "$marker" ]; then
    printf 'ERROR: Existing VM baked-image cache entry failed integrity validation: %s. %s\n' \
      "$(dirname "$image")" \
      "Do not remove it while VM disks may depend on it; preserve affected sets for M5 down/destroy cleanup." >&2
    exec {lock_fd}>&-
    return 1
  fi
  printf 'base-image-cache=miss fingerprint=%s image=%s marker=%s\n' \
    "$VM_BAKED_BASE_IMAGE_FINGERPRINT" "$image" "$marker"
  vm_libvirt_bake_base_image
  rc=$?
  exec {lock_fd}>&-
  return "$rc"
}

vm_libvirt_define_network() {
  local network xml
  network="$(vm_libvirt_network_name)"
  xml="$(vm_libvirt_network_xml_path)"
  if ! vm_libvirt_selected_network_exists; then
    vm_libvirt_render_network_xml || return $?
    virsh -c "$VM_LIBVIRT_URI" net-define "$xml" >/dev/null || return $?
  fi
  if ! vm_libvirt_network_is_active; then
    virsh -c "$VM_LIBVIRT_URI" net-start "$network" >/dev/null || return $?
  fi
}

vm_libvirt_define_machine() {
  local machine xml
  machine="${1:?machine required}"
  xml="$(vm_libvirt_domain_xml_path "$machine")"
  vm_libvirt_create_disk "$machine" || return $?
  vm_libvirt_render_seed_media "$machine" || return $?
  vm_libvirt_render_domain_xml "$machine" || return $?
  if ! vm_libvirt_machine_exists "$machine"; then
    virsh -c "$VM_LIBVIRT_URI" define "$xml" >/dev/null || return $?
  fi
  vm_libvirt_write_machine_metadata "$machine" || return $?
}

vm_libvirt_create_set() {
  local machine
  vm_libvirt_require_base_image || return $?
  mkdir -p "$(vm_path_vm_set_libvirt_dir)" "$(vm_path_vm_set_disk_dir)" \
    "$(vm_path_vm_set_seed_dir)" "$(vm_path_vm_set_machine_dir)" || return $?
  vm_libvirt_ensure_ssh_key || return $?
  vm_libvirt_define_network || return $?
  vm_libvirt_ensure_baked_base_image || return $?
  for machine in "${vm_machines[@]}"; do
    vm_libvirt_define_machine "$machine" || return $?
  done
}

vm_libvirt_seed_ldif_path() {
  printf '%s/ldap/50-harness-seed.ldif\n' "$vm_dir"
}

vm_libvirt_service_packages_for_machine() {
  case "${1:?machine required}" in
    bundle-factory)
      printf '%s\n' ca-certificates openjdk-21-jre-headless tar unzip wget
      ;;
    ldap)
      printf '%s\n' slapd ldap-utils ca-certificates
      ;;
    gerrit)
      printf '%s\n' ca-certificates curl openjdk-21-jre-headless openssh-client rsync tar ldap-utils
      ;;
    jenkins-controller)
      printf '%s\n' ca-certificates curl fontconfig openjdk-21-jre openssh-client rsync tar unzip wget ldap-utils
      ;;
    jenkins-agent)
      printf '%s\n' ca-certificates curl openjdk-21-jre-headless openssh-server rsync tar wget git unzip
      ;;
    *)
      die "Unknown VM machine for package baseline: $1"
      ;;
  esac
}

vm_libvirt_package_list_csv() {
  local machine package first
  machine="${1:?machine required}"
  first=1
  while IFS= read -r package; do
    [ -n "$package" ] || continue
    if [ "$first" -eq 1 ]; then
      first=0
    else
      printf ','
    fi
    printf '%s' "$package"
  done <<EOF
$(vm_libvirt_service_packages_for_machine "$machine")
EOF
}

vm_libvirt_install_os_baseline() {
  local machine packages script
  machine="${1:?machine required}"
  packages="$(vm_libvirt_package_list_csv "$machine")"
  script="$(vm_libvirt_os_baseline_verify_script "$packages")"
  vm_ssh_run_machine "$machine" "$script" || return $?
  printf 'os-baseline machine=%s packages=%s source=base-image fingerprint=%s apt-mirror=%s\n' \
    "$machine" "$packages" "$VM_BAKED_BASE_IMAGE_FINGERPRINT" "$HARNESS_UBUNTU_APT_MIRROR"
}

vm_libvirt_install_os_baselines() {
  local machine
  for machine in "${vm_machines[@]}"; do
    vm_libvirt_install_os_baseline "$machine" || return $?
  done
}

vm_libvirt_configure_ldap_service() {
  local ldif_file seed_b64 script output expected
  ldif_file="$(vm_libvirt_seed_ldif_path)"
  require_readable_file "VM LDAP seed LDIF" "$ldif_file" || return $?
  seed_b64="$(base64 <"$ldif_file" | tr -d '\n')" || return $?
script=$(cat <<EOF
set -euo pipefail
export LDAP_BIND_PASSWORD="\${LDAP_BIND_PASSWORD:?LDAP_BIND_PASSWORD required}"
readonly_dn=$(shell_quote "$HARNESS_LDAP_BIND_DN")
readonly_cn=$(shell_quote "$HARNESS_LDAP_BIND_USER")
ldap_domain=$(shell_quote "$HARNESS_LDAP_DOMAIN")
ldap_host=$(shell_quote "$HARNESS_LDAP_HOST")
ldap_port=$(shell_quote "$HARNESS_LDAP_PORT")
ldap_timeout=$(shell_quote "$VM_OPERATOR_SSH_TIMEOUT_SECONDS")
ldap_poll=$(shell_quote "$VM_OPERATOR_SSH_POLL_SECONDS")
ldap_user_base=$(shell_quote "$HARNESS_LDAP_USER_BASE")
ldap_group_base=$(shell_quote "$HARNESS_LDAP_GROUP_BASE")
sudo debconf-set-selections <<DEBCONF
slapd slapd/no_configuration boolean false
slapd slapd/domain string \$ldap_domain
slapd shared/organization string Gerrit Jenkins Harness
slapd slapd/password1 password \$LDAP_BIND_PASSWORD
slapd slapd/password2 password \$LDAP_BIND_PASSWORD
slapd slapd/move_old_database boolean true
slapd slapd/purge_database boolean true
DEBCONF
sudo DEBIAN_FRONTEND=noninteractive dpkg-reconfigure slapd
sudo systemctl enable --now slapd
readonly_ldif="\$(mktemp)"
tmp_ldif="\$(mktemp)"
cleanup_ldap_seed_files() {
  rm -f "\$readonly_ldif" "\$tmp_ldif"
}
trap cleanup_ldap_seed_files EXIT
cat >"\$readonly_ldif" <<LDIF
dn: \$readonly_dn
objectClass: simpleSecurityObject
objectClass: organizationalRole
cn: \$readonly_cn
description: Simulation-owned read-only bind account
userPassword: \$LDAP_BIND_PASSWORD
LDIF
printf '%s' $(shell_quote "$seed_b64") | base64 -d >"\$tmp_ldif"
apply_ldif() {
  apply_output="\$(mktemp)"
  if ldapadd -x -c -H ldap://127.0.0.1:389 \
    -D $(shell_quote "cn=admin,$HARNESS_LDAP_BASE_DN") -w "\$LDAP_BIND_PASSWORD" \
    -f "\$1" >"\$apply_output" 2>&1; then
    rm -f "\$apply_output"
    return 0
  fi
  if grep -Fq 'Already exists (68)' "\$apply_output" &&
    ! grep '^ldap_add:' "\$apply_output" | grep -Fv 'Already exists (68)' >/dev/null; then
    rm -f "\$apply_output"
    return 0
  fi
  cat "\$apply_output" >&2
  rm -f "\$apply_output"
  return 1
}
apply_ldif "\$readonly_ldif"
apply_ldif "\$tmp_ldif"
rm -f "\$readonly_ldif" "\$tmp_ldif"
trap - EXIT
systemctl is-active --quiet slapd
retry_ldapsearch_dn() {
  entry_type="\$1"
  entry_id="\$2"
  expected_dn="\$3"
  shift 3
  deadline=\$((SECONDS + ldap_timeout))
  output="\$(mktemp)"
  while [ "\$SECONDS" -lt "\$deadline" ]; do
    if ldapsearch "\$@" >"\$output" 2>&1 &&
      grep -Fxi "dn: \$expected_dn" "\$output" >/dev/null; then
      rm -f "\$output"
      printf 'ldap-seed-entry=ready type=%s id=%s dn=%s\n' \
        "\$entry_type" "\$entry_id" "\$expected_dn"
      return 0
    fi
    sleep "\$ldap_poll"
  done
  cat "\$output" >&2
  rm -f "\$output"
  return 1
}
retry_ldapsearch_dn user gerrit-admin "uid=gerrit-admin,\$ldap_user_base" -x -H ldap://127.0.0.1:389 -D $(shell_quote "$HARNESS_LDAP_BIND_DN") -w "\$LDAP_BIND_PASSWORD" -b "\$ldap_user_base" uid=gerrit-admin dn
retry_ldapsearch_dn user jenkins-admin "uid=jenkins-admin,\$ldap_user_base" -x -H ldap://127.0.0.1:389 -D $(shell_quote "$HARNESS_LDAP_BIND_DN") -w "\$LDAP_BIND_PASSWORD" -b "\$ldap_user_base" uid=jenkins-admin dn
retry_ldapsearch_dn user test-user "uid=test-user,\$ldap_user_base" -x -H ldap://127.0.0.1:389 -D $(shell_quote "$HARNESS_LDAP_BIND_DN") -w "\$LDAP_BIND_PASSWORD" -b "\$ldap_user_base" uid=test-user dn
retry_ldapsearch_dn group gerrit-admins "cn=gerrit-admins,\$ldap_group_base" -x -H ldap://127.0.0.1:389 -D $(shell_quote "$HARNESS_LDAP_BIND_DN") -w "\$LDAP_BIND_PASSWORD" -b "\$ldap_group_base" cn=gerrit-admins dn
retry_ldapsearch_dn group jenkins-admins "cn=jenkins-admins,\$ldap_group_base" -x -H ldap://127.0.0.1:389 -D $(shell_quote "$HARNESS_LDAP_BIND_DN") -w "\$LDAP_BIND_PASSWORD" -b "\$ldap_group_base" cn=jenkins-admins dn
retry_ldapsearch_dn endpoint test-user "uid=test-user,\$ldap_user_base" -x -H ldap://\$ldap_host:\$ldap_port -D $(shell_quote "$HARNESS_LDAP_BIND_DN") -w "\$LDAP_BIND_PASSWORD" -b "\$ldap_user_base" uid=test-user dn
EOF
)
  output="$(vm_ssh_run_machine_with_ldap_password ldap "$script")" || return $?
  printf '%s\n' "$output"
  for expected in \
    "ldap-seed-entry=ready type=user id=gerrit-admin dn=uid=gerrit-admin,$HARNESS_LDAP_USER_BASE" \
    "ldap-seed-entry=ready type=user id=jenkins-admin dn=uid=jenkins-admin,$HARNESS_LDAP_USER_BASE" \
    "ldap-seed-entry=ready type=user id=test-user dn=uid=test-user,$HARNESS_LDAP_USER_BASE" \
    "ldap-seed-entry=ready type=group id=gerrit-admins dn=cn=gerrit-admins,$HARNESS_LDAP_GROUP_BASE" \
    "ldap-seed-entry=ready type=group id=jenkins-admins dn=cn=jenkins-admins,$HARNESS_LDAP_GROUP_BASE" \
    "ldap-seed-entry=ready type=endpoint id=test-user dn=uid=test-user,$HARNESS_LDAP_USER_BASE"; do
    printf '%s\n' "$output" | grep -Fxq "$expected" || {
      printf 'ERROR: Missing exact VM LDAP seed proof: %s\n' "$expected" >&2
      return 1
    }
  done
  printf 'ldap-service=ready host=%s port=%s seed=%s\n' \
    "$HARNESS_LDAP_HOST" "$HARNESS_LDAP_PORT" "$ldif_file"
}

vm_libvirt_verify_ldap_consumer_reachability() {
  local machine script output expected_dn expected_marker
  machine="${1:?machine required}"
  expected_dn="uid=test-user,$HARNESS_LDAP_USER_BASE"
  script=$(cat <<EOF
set -euo pipefail
export LDAP_BIND_PASSWORD="\${LDAP_BIND_PASSWORD:?LDAP_BIND_PASSWORD required}"
ldap_host=$(shell_quote "$HARNESS_LDAP_HOST")
ldap_port=$(shell_quote "$HARNESS_LDAP_PORT")
consumer_machine=$(shell_quote "$machine")
output="\$(mktemp)"
hosts_output="\$(mktemp)"
cleanup() {
  rm -f "\$output" "\$hosts_output"
}
trap cleanup EXIT
if ! getent hosts "\$ldap_host" >"\$hosts_output" 2>&1; then
  printf 'LDAP consumer diagnostics for %s:%s\n' "\$ldap_host" "\$ldap_port" >&2
  cat "\$hosts_output" >&2
  exit 1
fi
if ! timeout 3 bash -c "</dev/tcp/\$ldap_host/\$ldap_port" >"\$output" 2>&1; then
  printf 'LDAP consumer diagnostics for %s:%s\n' "\$ldap_host" "\$ldap_port" >&2
  cat "\$hosts_output" >&2
  printf 'tcp-connect=failed host=%s port=%s\n' "\$ldap_host" "\$ldap_port" >&2
  cat "\$output" >&2
  exit 1
fi
if ! ldapsearch -x -H ldap://\$ldap_host:\$ldap_port \
  -D $(shell_quote "$HARNESS_LDAP_BIND_DN") -w "\$LDAP_BIND_PASSWORD" \
  -b $(shell_quote "$HARNESS_LDAP_USER_BASE") uid=test-user dn >"\$output" 2>&1; then
  printf 'LDAP consumer diagnostics for %s:%s\n' "\$ldap_host" "\$ldap_port" >&2
  cat "\$hosts_output" >&2
  printf 'tcp-connect=ready host=%s port=%s\n' "\$ldap_host" "\$ldap_port" >&2
  cat "\$output" >&2
  exit 1
fi
if ! grep -Fxi $(shell_quote "dn: $expected_dn") "\$output" >/dev/null; then
  printf 'LDAP consumer search returned no exact test-user DN for %s:%s\n' "\$ldap_host" "\$ldap_port" >&2
  cat "\$output" >&2
  exit 1
fi
printf 'ldap-consumer-bind-search=ready machine=%s id=test-user dn=%s\n' \
  "\$consumer_machine" $(shell_quote "$expected_dn")
EOF
)
  output="$(vm_ssh_run_machine_with_ldap_password "$machine" "$script")" || return $?
  printf '%s\n' "$output"
  expected_marker="ldap-consumer-bind-search=ready machine=$machine id=test-user dn=$expected_dn"
  printf '%s\n' "$output" | grep -Fxq "$expected_marker" || {
    printf 'ERROR: Missing exact VM LDAP consumer proof: %s\n' "$expected_marker" >&2
    return 1
  }
  printf 'ldap-consumer=%s reachable host=%s port=%s\n' \
    "$machine" "$HARNESS_LDAP_HOST" "$HARNESS_LDAP_PORT"
}

vm_libvirt_verify_baseline_prereqs() {
  vm_libvirt_install_os_baselines || return $?
  vm_libvirt_configure_ldap_service || return $?
  vm_libvirt_verify_ldap_consumer_reachability gerrit || return $?
  vm_libvirt_verify_ldap_consumer_reachability jenkins-controller || return $?
  vm_state_write_baseline_prereqs_marker || return $?
  printf 'baseline-prereqs=ready marker=%s\n' \
    "$HARNESS_VM_BASELINE_PREREQS_MARKER"
}

vm_libvirt_start_machine() {
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
    vm_libvirt_start_machine "$machine"
  done
}

vm_libvirt_shutdown_machine() {
  local machine domain deadline state
  machine="${1:?machine required}"
  domain="$(vm_libvirt_domain_name "$machine")"
  vm_libvirt_machine_exists "$machine" || return 0
  state="$(vm_libvirt_domain_state "$machine")"
  case "$state" in
    running)
      virsh -c "$VM_LIBVIRT_URI" shutdown "$domain" >/dev/null || true
      deadline=$((SECONDS + VM_OPERATOR_SSH_TIMEOUT_SECONDS))
      while [ "$SECONDS" -lt "$deadline" ]; do
        state="$(vm_libvirt_domain_state "$machine")"
        case "$state" in
          'shut off'|shut*) return 0 ;;
        esac
        sleep "$VM_OPERATOR_SSH_POLL_SECONDS"
      done
      die "Timed out waiting for VM domain shutdown: $domain"
      ;;
    'shut off'|shut*|missing) ;;
    *)
      die "VM domain $machine is in unexpected state for down: $state"
      ;;
  esac
}

vm_libvirt_shutdown_set() {
  local machine
  for machine in "${vm_machines[@]}"; do
    vm_libvirt_shutdown_machine "$machine"
  done
}

vm_libvirt_machine_ip() {
  local machine mac network
  machine="${1:?machine required}"
  mac="$(vm_libvirt_machine_mac "$machine")"
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

vm_libvirt_selected_pool_exists() {
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
  vm_libvirt_selected_pool_exists "$storage_pool" && return 0
  vm_libvirt_selected_pool_exists "$seed_pool" && return 0
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

vm_libvirt_audit_readonly() {
  vm_libvirt_preflight_readonly >/dev/null
  vm_state_validate_vm_set_ownership_readonly
}
