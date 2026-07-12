#!/usr/bin/env bash

__vm_libvirt_require_seed_media_tool() {
  command -v cloud-localds >/dev/null 2>&1 && return 0
  command -v genisoimage >/dev/null 2>&1 && return 0
  command -v mkisofs >/dev/null 2>&1 && return 0
  die "Missing required VM seed media tool: cloud-localds, genisoimage, or mkisofs"
}

__vm_libvirt_network_xml_path() {
  printf '%s/network.xml\n' "$(vm_path_vm_set_libvirt_dir)"
}

__vm_libvirt_domain_xml_path() {
  printf '%s/%s.xml\n' "$(vm_path_vm_set_machine_dir)" "${1:?machine required}"
}

__vm_libvirt_seed_iso_path() {
  printf '%s/%s-seed.iso\n' "$(vm_path_vm_set_seed_dir)" "${1:?machine required}"
}

__vm_libvirt_seed_work_dir() {
  printf '%s/%s\n' "$(vm_path_vm_set_seed_dir)" "${1:?machine required}"
}

vm_libvirt_verify_domain_attachments() {
  local disk domain machine mac network seed
  machine="${1:?machine required}"
  domain="$(vm_libvirt_domain_name "$machine")"
  disk="$(vm_libvirt_disk_path "$machine")"
  seed="$(__vm_libvirt_seed_iso_path "$machine")"
  network="$(vm_libvirt_network_name)"
  mac="$(__vm_libvirt_machine_mac "$machine")"
  virsh -c "$VM_LIBVIRT_URI" dumpxml "$domain" | python3 -c '
import os, sys, xml.etree.ElementTree as ET
root = ET.parse(sys.stdin).getroot()
expected_disk, expected_seed, expected_network, expected_mac = sys.argv[1:]
nodes = root.findall("./devices/disk")
disks = [os.path.abspath(n.find("./source").get("file")) for n in nodes
         if n.get("device") == "disk" and n.find("./source") is not None]
seeds = [os.path.abspath(n.find("./source").get("file")) for n in nodes
         if n.get("device") == "cdrom" and n.find("./source") is not None]
interfaces = root.findall("./devices/interface")
networks = [n.find("./source").get("network") for n in interfaces
            if n.find("./source") is not None]
macs = [n.find("./mac").get("address") for n in interfaces
        if n.find("./mac") is not None]
if disks != [os.path.abspath(expected_disk)]:
    raise SystemExit("domain disk attachment does not match selected volume")
if os.path.abspath(expected_seed) not in seeds:
    raise SystemExit("domain seed attachment does not match selected VM set")
if networks != [expected_network] or macs != [expected_mac]:
    raise SystemExit("domain network attachment does not match selected VM set")
' "$disk" "$seed" "$network" "$mac"
}

__vm_libvirt_render_network_xml() {
  local machine machine_args xml
  xml="$(__vm_libvirt_network_xml_path)"
  machine_args=()
  for machine in "${vm_machines[@]}"; do
    machine_args+=("$machine=$(__vm_libvirt_machine_mac "$machine")")
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

__vm_libvirt_render_domain_xml() {
  local machine domain pool volume disk seed mac xml
  machine="${1:?machine required}"
  domain="$(vm_libvirt_domain_name "$machine")"
  pool="$(vm_libvirt_storage_pool_name)"
  volume="$(vm_libvirt_machine_volume_name "$machine")"
  disk="$(vm_libvirt_volume_path "$pool" "$volume")" || return $?
  seed="$(__vm_libvirt_seed_iso_path "$machine")"
  mac="$(__vm_libvirt_machine_mac "$machine")"
  xml="$(__vm_libvirt_domain_xml_path "$machine")"
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

__vm_libvirt_render_bake_domain_xml() {
  local domain disk seed mac xml
  domain="$(__vm_libvirt_bake_domain_name)"
  disk="$(__vm_libvirt_bake_disk_path)"
  seed="$(__vm_libvirt_bake_seed_iso_path)"
  mac="$(__vm_libvirt_bake_machine_mac)"
  xml="$(__vm_libvirt_bake_domain_xml_path)"
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

__vm_libvirt_render_seed_media() {
  local machine work_dir user_data meta_data network_config seed_iso mac public_key dns_gateway
  machine="${1:?machine required}"
  work_dir="$(__vm_libvirt_seed_work_dir "$machine")"
  user_data="$work_dir/user-data"
  meta_data="$work_dir/meta-data"
  network_config="$work_dir/network-config"
  seed_iso="$(__vm_libvirt_seed_iso_path "$machine")"
  mac="$(__vm_libvirt_machine_mac "$machine")"
  public_key="$(cat "$HARNESS_TARGET_SSH_IDENTITY_FILE.pub")"
  dns_gateway="$(__vm_libvirt_network_gateway)"
  mkdir -p "$work_dir"
  chmod 0700 "$work_dir"
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
  chmod 0600 "$user_data" "$meta_data" "$network_config"
  chmod 0644 "$seed_iso"
}

__vm_libvirt_render_bake_seed_media() {
  local work_dir user_data meta_data network_config seed_iso mac public_key dns_gateway
  work_dir="$(__vm_libvirt_bake_seed_work_dir)"
  user_data="$work_dir/user-data"
  meta_data="$work_dir/meta-data"
  network_config="$work_dir/network-config"
  seed_iso="$(__vm_libvirt_bake_seed_iso_path)"
  mac="$(__vm_libvirt_bake_machine_mac)"
  public_key="$(cat "$HARNESS_TARGET_SSH_IDENTITY_FILE.pub")"
  dns_gateway="$(__vm_libvirt_network_gateway)"
  mkdir -p "$work_dir"
  chmod 0700 "$work_dir"
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
  chmod 0600 "$user_data" "$meta_data" "$network_config"
  chmod 0644 "$seed_iso"
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

vm_libvirt_define_network() {
  local network xml
  network="$(vm_libvirt_network_name)"
  xml="$(__vm_libvirt_network_xml_path)"
  if ! vm_libvirt_selected_network_exists; then
    __vm_libvirt_render_network_xml || return $?
    virsh -c "$VM_LIBVIRT_URI" net-define "$xml" >/dev/null || return $?
  fi
  if ! vm_libvirt_network_is_active; then
    virsh -c "$VM_LIBVIRT_URI" net-start "$network" >/dev/null || return $?
  fi
}

vm_libvirt_define_machine() {
  local machine xml
  machine="${1:?machine required}"
  xml="$(__vm_libvirt_domain_xml_path "$machine")"
  __vm_libvirt_create_disk "$machine" || return $?
  __vm_libvirt_render_seed_media "$machine" || return $?
  __vm_libvirt_render_domain_xml "$machine" || return $?
  if ! vm_libvirt_machine_exists "$machine"; then
    virsh -c "$VM_LIBVIRT_URI" define "$xml" >/dev/null || return $?
  fi
  __vm_libvirt_write_machine_metadata "$machine" || return $?
}
