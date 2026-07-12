#!/usr/bin/env bash

vm_libvirt_disk_path() {
  printf '%s/%s.qcow2\n' "$(vm_path_vm_set_disk_dir)" "${1:?machine required}"
}

vm_libvirt_machine_metadata_path() {
  vm_path_vm_machine_file "${1:?machine required}"
}

vm_libvirt_pool_exists() {
  virsh -c "$VM_LIBVIRT_URI" pool-info "${1:?pool name required}" >/dev/null 2>&1
}

__vm_libvirt_pool_is_active() {
  virsh -c "$VM_LIBVIRT_URI" pool-info "${1:?pool name required}" 2>/dev/null |
    awk -F: '$1 == "State" { gsub(/[[:space:]]/, "", $2); if ($2 == "running") found = 1 } END { exit !found }'
}

vm_libvirt_pool_target() {
  virsh -c "$VM_LIBVIRT_URI" pool-dumpxml "${1:?pool name required}" |
    python3 -c '
import os
import sys
import xml.etree.ElementTree as ET

path = ET.parse(sys.stdin).getroot().findtext("./target/path")
if not path:
    raise SystemExit("libvirt storage pool has no target path")
print(os.path.abspath(path))
'
}

__vm_libvirt_qemu_conf_value() {
  local key conf
  key="${1:?key required}"
  conf="${VM_LIBVIRT_QEMU_CONF:-/etc/libvirt/qemu.conf}"
  [ -r "$conf" ] || return 1
  awk -v key="$key" '
    $0 !~ /^[[:space:]]*#/ && $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
      sub(/^[^=]*=[[:space:]]*/, "")
      sub(/[[:space:]]*#.*/, "")
      gsub(/^[[:space:]]+|[[:space:]]+$/, "")
      gsub(/^"|"$/, "")
      print
      found = 1
      exit
    }
    END { exit !found }
  ' "$conf"
}

__vm_libvirt_user_uid() {
  local value
  value="${1:?user required}"
  case "$value" in
    *[!0-9]*|'') getent passwd "$value" | awk -F: 'NR == 1 { print $3; found = 1 } END { exit !found }' ;;
    *) printf '%s\n' "$value" ;;
  esac
}

__vm_libvirt_user_gid() {
  local value
  value="${1:?user required}"
  getent passwd "$value" | awk -F: 'NR == 1 { print $4; found = 1 } END { exit !found }'
}

__vm_libvirt_group_gid() {
  local value
  value="${1:?group required}"
  case "$value" in
    *[!0-9]*|'') getent group "$value" | awk -F: 'NR == 1 { print $3; found = 1 } END { exit !found }' ;;
    *) printf '%s\n' "$value" ;;
  esac
}

__vm_libvirt_try_qemu_identity() {
  local user group uid gid
  user="${1:?user required}"
  group="${2:-}"
  uid="$(__vm_libvirt_user_uid "$user")" || return 1
  if [ -n "$group" ]; then
    gid="$(__vm_libvirt_group_gid "$group")" || return 1
  else
    gid="$(__vm_libvirt_user_gid "$user")" || return 1
  fi
  printf '%s %s\n' "$uid" "$gid"
}

vm_libvirt_qemu_identity() {
  local configured_user configured_group identity
  configured_user="$(__vm_libvirt_qemu_conf_value user 2>/dev/null || true)"
  configured_group="$(__vm_libvirt_qemu_conf_value group 2>/dev/null || true)"
  if [ -n "$configured_user" ] || [ -n "$configured_group" ]; then
    if [ -n "$configured_user" ]; then
      identity="$(__vm_libvirt_try_qemu_identity "$configured_user" "$configured_group")" ||
        die "Unable to resolve configured libvirt QEMU identity from ${VM_LIBVIRT_QEMU_CONF:-/etc/libvirt/qemu.conf}"
      printf '%s\n' "$identity"
      return 0
    fi
    identity="$(__vm_libvirt_try_qemu_identity libvirt-qemu "$configured_group" 2>/dev/null ||
      __vm_libvirt_try_qemu_identity qemu "$configured_group" 2>/dev/null)" ||
      die "Unable to resolve configured libvirt QEMU group from ${VM_LIBVIRT_QEMU_CONF:-/etc/libvirt/qemu.conf}"
    printf '%s\n' "$identity"
    return 0
  fi
  identity="$(__vm_libvirt_try_qemu_identity libvirt-qemu kvm 2>/dev/null ||
    __vm_libvirt_try_qemu_identity qemu qemu 2>/dev/null)" ||
    die "Unable to resolve libvirt QEMU identity; configure user/group in /etc/libvirt/qemu.conf or provide libvirt-qemu:kvm/qemu:qemu accounts"
  printf '%s\n' "$identity"
}

vm_libvirt_make_storage_path_searchable() {
  chmod 0711 "$@" || return $?
}

__vm_libvirt_render_directory_pool_xml() {
  local name target xml
  name="${1:?pool name required}"
  target="${2:?pool target required}"
  xml="${3:?pool XML path required}"
  mkdir -p "$target" "$(dirname "$xml")" || return $?
  python3 - "$name" "$target" >"$xml" <<'PY'
import sys
import xml.etree.ElementTree as ET

pool = ET.Element("pool", {"type": "dir"})
ET.SubElement(pool, "name").text = sys.argv[1]
target = ET.SubElement(pool, "target")
ET.SubElement(target, "path").text = sys.argv[2]
permissions = ET.SubElement(target, "permissions")
ET.SubElement(permissions, "mode").text = "0711"
ET.ElementTree(pool).write(sys.stdout, encoding="unicode")
print()
PY
  chmod 0600 "$xml"
}

vm_libvirt_require_directory_pool() {
  local name target actual_target
  name="${1:?pool name required}"
  target="${2:?pool target required}"
  vm_libvirt_pool_exists "$name" || return 1
  actual_target="$(vm_libvirt_pool_target "$name")" || return $?
  [ "$actual_target" = "$target" ] || return 1
  if ! __vm_libvirt_pool_is_active "$name"; then
    virsh -c "$VM_LIBVIRT_URI" pool-start "$name" >/dev/null || return $?
  fi
  virsh -c "$VM_LIBVIRT_URI" pool-refresh "$name" >/dev/null
}

__vm_libvirt_ensure_directory_pool() {
  local name target xml
  name="${1:?pool name required}"
  target="${2:?pool target required}"
  xml="${3:?pool XML path required}"
  if vm_libvirt_pool_exists "$name"; then
    vm_libvirt_require_directory_pool "$name" "$target" || {
      printf 'ERROR: Libvirt storage pool identity mismatch: %s\n' "$name" >&2
      return 1
    }
    return 0
  fi
  __vm_libvirt_render_directory_pool_xml "$name" "$target" "$xml" || return $?
  virsh -c "$VM_LIBVIRT_URI" pool-define "$xml" >/dev/null || return $?
  vm_libvirt_require_directory_pool "$name" "$target"
}

vm_libvirt_ensure_storage_pool() {
  __vm_libvirt_ensure_directory_pool \
    "$(vm_libvirt_storage_pool_name)" \
    "$(vm_path_vm_set_disk_dir)" \
    "$(vm_path_vm_set_storage_pool_xml)"
}

vm_libvirt_require_existing_storage_pool() {
  vm_libvirt_require_directory_pool \
    "$(vm_libvirt_storage_pool_name)" \
    "$(vm_path_vm_set_disk_dir)" || {
    printf 'ERROR: Existing VM disks require their original libvirt storage pool. %s\n' \
      "Select a fresh HARNESS_RUN_ID and LOOPFORGE_VM_SET_ID; retain this set for M5 down/destroy cleanup." >&2
    return 1
  }
}

__vm_libvirt_ensure_baked_base_image_pool() {
  __vm_libvirt_ensure_directory_pool \
    "$(vm_libvirt_baked_base_image_pool_name)" \
    "$(vm_path_baked_base_image_volume_dir "$VM_BAKED_BASE_IMAGE_FINGERPRINT")" \
    "$(vm_path_baked_base_image_pool_xml "$VM_BAKED_BASE_IMAGE_FINGERPRINT")"
}

vm_libvirt_volume_exists() {
  local pool volume
  pool="${1:?pool name required}"
  volume="${2:?volume name required}"
  virsh -c "$VM_LIBVIRT_URI" vol-info "$volume" --pool "$pool" >/dev/null 2>&1
}

vm_libvirt_volume_value() {
  local pool volume key
  pool="${1:?pool name required}"
  volume="${2:?volume name required}"
  key="${3:?volume value key required}"
  virsh -c "$VM_LIBVIRT_URI" vol-dumpxml "$volume" --pool "$pool" |
    python3 -c '
import os
import sys
import xml.etree.ElementTree as ET

key = sys.argv[1]
root = ET.parse(sys.stdin).getroot()
if key == "capacity_bytes":
    node = root.find("./capacity")
    if node is None or not node.text:
        raise SystemExit("libvirt volume has no capacity")
    units = {"bytes": 1, "B": 1, "KiB": 1024, "MiB": 1024**2,
             "GiB": 1024**3, "TiB": 1024**4}
    unit = node.get("unit", "bytes")
    if unit not in units:
        raise SystemExit(f"unsupported libvirt capacity unit: {unit}")
    print(int(node.text) * units[unit])
elif key == "format":
    node = root.find("./target/format")
    if node is None or not node.get("type"):
        raise SystemExit("libvirt volume has no target format")
    print(node.get("type"))
elif key == "backing_path":
    path = root.findtext("./backingStore/path")
    if not path:
        raise SystemExit("libvirt volume has no backing path")
    print(os.path.abspath(path))
elif key == "backing_format":
    node = root.find("./backingStore/format")
    if node is None or not node.get("type"):
        raise SystemExit("libvirt volume has no backing format")
    print(node.get("type"))
else:
    raise SystemExit(f"unknown libvirt volume value: {key}")
' "$key"
}

vm_libvirt_volume_path() {
  virsh -c "$VM_LIBVIRT_URI" vol-path \
    "${2:?volume name required}" --pool "${1:?pool name required}"
}

__vm_libvirt_volume_sha256() {
  local pool volume tmp sha rc
  pool="${1:?pool name required}"
  volume="${2:?volume name required}"
  tmp="$(mktemp "$(vm_path_baked_base_image_dir "$VM_BAKED_BASE_IMAGE_FINGERPRINT")/.volume-download.XXXXXX")" || return $?
  if virsh -c "$VM_LIBVIRT_URI" vol-download "$volume" "$tmp" \
    --pool "$pool" --sparse >/dev/null; then
    sha="$(sha256sum "$tmp" | awk '{print $1}')"
    rc=$?
  else
    sha=""
    rc=1
  fi
  rm -f "$tmp"
  [ "$rc" -eq 0 ] || return "$rc"
  printf '%s\n' "$sha"
}

__vm_libvirt_disk_size_bytes() {
  python3 - "$VM_DOMAIN_DISK_SIZE" <<'PY'
import re
import sys

match = re.fullmatch(r"([1-9][0-9]*)([KMGTPE]?)", sys.argv[1])
if not match:
    raise SystemExit(f"Unsupported VM_DOMAIN_DISK_SIZE: {sys.argv[1]}")
units = {"": 1, "K": 1024, "M": 1024**2, "G": 1024**3,
         "T": 1024**4, "P": 1024**5, "E": 1024**6}
print(int(match.group(1)) * units[match.group(2)])
PY
}

__vm_libvirt_render_machine_volume_xml() {
  local machine volume capacity backing xml identity owner group
  machine="${1:?machine required}"
  volume="$(vm_libvirt_machine_volume_name "$machine")"
  capacity="$(__vm_libvirt_disk_size_bytes)" || return $?
  backing="$(vm_libvirt_baked_base_image_path)"
  xml="$(vm_path_vm_volume_xml "$machine")"
  identity="$(vm_libvirt_qemu_identity)" || return $?
  owner="${identity%% *}"
  group="${identity##* }"
  mkdir -p "$(dirname "$xml")" || return $?
  python3 - "$volume" "$capacity" "$backing" "$owner" "$group" >"$xml" <<'PY'
import sys
import xml.etree.ElementTree as ET

volume = ET.Element("volume", {"type": "file"})
ET.SubElement(volume, "name").text = sys.argv[1]
ET.SubElement(volume, "capacity", {"unit": "bytes"}).text = sys.argv[2]
ET.SubElement(volume, "allocation", {"unit": "bytes"}).text = "0"
target = ET.SubElement(volume, "target")
ET.SubElement(target, "format", {"type": "qcow2"})
permissions = ET.SubElement(target, "permissions")
ET.SubElement(permissions, "mode").text = "0600"
ET.SubElement(permissions, "owner").text = sys.argv[4]
ET.SubElement(permissions, "group").text = sys.argv[5]
backing = ET.SubElement(volume, "backingStore")
ET.SubElement(backing, "path").text = sys.argv[3]
ET.SubElement(backing, "format", {"type": "qcow2"})
ET.ElementTree(volume).write(sys.stdout, encoding="unicode")
print()
PY
  chmod 0600 "$xml"
}

__vm_libvirt_write_machine_metadata() {
  local machine file disk pool volume
  local baked_image baked_sha256 disk_virtual_size_bytes
  machine="${1:?machine required}"
  file="$(vm_libvirt_machine_metadata_path "$machine")"
  pool="$(vm_libvirt_storage_pool_name)"
  volume="$(vm_libvirt_machine_volume_name "$machine")"
  disk="$(vm_libvirt_volume_path "$pool" "$volume")" || return $?
  baked_image="$(vm_libvirt_baked_base_image_path)"
  baked_sha256="$(marker_value "$(vm_libvirt_baked_base_image_marker_path)" baked_sha256)"
  disk_virtual_size_bytes="$(vm_libvirt_volume_value "$pool" "$volume" capacity_bytes)" || return $?
  mkdir -p "$(dirname "$file")"
  cat >"$file" <<EOF
machine=$machine
domain=$(vm_libvirt_domain_name "$machine")
mac=$(__vm_libvirt_machine_mac "$machine")
disk=$disk
disk_size=$VM_DOMAIN_DISK_SIZE
disk_virtual_size_bytes=$disk_virtual_size_bytes
storage_pool_name=$pool
volume_name=$volume
disk_ownership=libvirt-managed
base_image=$baked_image
base_image_fingerprint=$VM_BAKED_BASE_IMAGE_FINGERPRINT
base_image_sha256=$baked_sha256
seed_iso=$(__vm_libvirt_seed_iso_path "$machine")
ssh_user=$VM_OPERATOR_USER
ssh_host=pending-up
ssh_port=22
EOF
  chmod 0600 "$file"
}

vm_libvirt_verify_existing_disk_identity() {
  local machine disk metadata pool volume expected_image expected_sha key expected actual
  local recorded_virtual_size actual_virtual_size actual_backing
  machine="${1:?machine required}"
  disk="$(vm_libvirt_disk_path "$machine")"
  metadata="$(vm_libvirt_machine_metadata_path "$machine")"
  pool="$(vm_libvirt_storage_pool_name)"
  volume="$(vm_libvirt_machine_volume_name "$machine")"
  expected_image="$(vm_libvirt_baked_base_image_path)"
  expected_sha="$(marker_value "$(vm_libvirt_baked_base_image_marker_path)" baked_sha256)"
  [ -r "$metadata" ] || {
    printf 'ERROR: Existing VM disk metadata is incompatible for %s: %s. %s\n' \
      "$machine" "$metadata" "Select a fresh HARNESS_RUN_ID and LOOPFORGE_VM_SET_ID; retain this set for M5 down/destroy cleanup." >&2
    return 1
  }
  vm_libvirt_volume_exists "$pool" "$volume" || {
    printf 'ERROR: Existing VM disk is not a libvirt-managed volume for %s. %s\n' \
      "$machine" "Select a fresh HARNESS_RUN_ID and LOOPFORGE_VM_SET_ID; retain this set for M5 down/destroy cleanup." >&2
    return 1
  }
  for key in disk disk_size storage_pool_name volume_name disk_ownership \
    base_image base_image_fingerprint base_image_sha256; do
    case "$key" in
      disk) expected="$disk" ;;
      disk_size) expected="$VM_DOMAIN_DISK_SIZE" ;;
      storage_pool_name) expected="$pool" ;;
      volume_name) expected="$volume" ;;
      disk_ownership) expected=libvirt-managed ;;
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
  [ "$(vm_libvirt_volume_path "$pool" "$volume")" = "$disk" ] || {
    printf 'ERROR: Existing VM disk volume path mismatch for %s. %s\n' \
      "$machine" "Select a fresh HARNESS_RUN_ID and LOOPFORGE_VM_SET_ID; retain this set for M5 down/destroy cleanup." >&2
    return 1
  }
  [ "$(vm_libvirt_volume_value "$pool" "$volume" format)" = qcow2 ] || return 1
  actual_backing="$(vm_libvirt_volume_value "$pool" "$volume" backing_path)" || return $?
  if [ "$actual_backing" != "$expected_image" ] ||
    [ "$(vm_libvirt_volume_value "$pool" "$volume" backing_format)" != qcow2 ]; then
    printf 'ERROR: Existing VM disk backing image mismatch for %s. %s\n' \
      "$machine" "Select a fresh HARNESS_RUN_ID and LOOPFORGE_VM_SET_ID; retain this set for M5 down/destroy cleanup." >&2
    return 1
  fi
  recorded_virtual_size="$(marker_value "$metadata" disk_virtual_size_bytes 2>/dev/null || true)"
  actual_virtual_size="$(vm_libvirt_volume_value "$pool" "$volume" capacity_bytes)" || return $?
  if [ -z "$recorded_virtual_size" ] || [ "$actual_virtual_size" != "$recorded_virtual_size" ]; then
    printf 'ERROR: Existing VM disk virtual size mismatch for %s. %s\n' \
      "$machine" "Select a fresh HARNESS_RUN_ID and LOOPFORGE_VM_SET_ID; retain this set for M5 down/destroy cleanup." >&2
    return 1
  fi
}

vm_libvirt_verify_existing_disk_identities() {
  local machine pool volume
  pool="$(vm_libvirt_storage_pool_name)"
  for machine in "${vm_machines[@]}"; do
    volume="$(vm_libvirt_machine_volume_name "$machine")"
    vm_libvirt_volume_exists "$pool" "$volume" || continue
    vm_libvirt_verify_existing_disk_identity "$machine" || return $?
  done
}

vm_libvirt_existing_disks_present() {
  local machine pool volume
  pool="$(vm_libvirt_storage_pool_name)"
  for machine in "${vm_machines[@]}"; do
    [ ! -e "$(vm_libvirt_disk_path "$machine")" ] || return 0
    if vm_libvirt_pool_exists "$pool"; then
      volume="$(vm_libvirt_machine_volume_name "$machine")"
      vm_libvirt_volume_exists "$pool" "$volume" && return 0
    fi
  done
  return 1
}

__vm_libvirt_create_disk() {
  local machine pool volume xml
  machine="${1:?machine required}"
  pool="$(vm_libvirt_storage_pool_name)"
  volume="$(vm_libvirt_machine_volume_name "$machine")"
  xml="$(vm_path_vm_volume_xml "$machine")"
  if vm_libvirt_volume_exists "$pool" "$volume"; then
    vm_libvirt_verify_existing_disk_identity "$machine"
    return $?
  fi
  [ ! -e "$(vm_libvirt_disk_path "$machine")" ] || {
    printf 'ERROR: Existing VM disk is not registered in the selected libvirt storage pool: %s. %s\n' \
      "$(vm_libvirt_disk_path "$machine")" \
      "Select a fresh HARNESS_RUN_ID and LOOPFORGE_VM_SET_ID; retain this set for M5 down/destroy cleanup." >&2
    return 1
  }
  __vm_libvirt_render_machine_volume_xml "$machine" || return $?
  virsh -c "$VM_LIBVIRT_URI" vol-create "$pool" "$xml" >/dev/null || return $?
  virsh -c "$VM_LIBVIRT_URI" pool-refresh "$pool" >/dev/null || return $?
  vm_libvirt_volume_exists "$pool" "$volume"
}

vm_libvirt_remove_pool() {
  local pool
  pool="${1:?pool required}"
  vm_libvirt_pool_exists "$pool" || return 0
  if __vm_libvirt_pool_is_active "$pool"; then
    virsh -c "$VM_LIBVIRT_URI" pool-destroy "$pool" >/dev/null || return $?
  fi
  virsh -c "$VM_LIBVIRT_URI" pool-undefine "$pool" >/dev/null
}
