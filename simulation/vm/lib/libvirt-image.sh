#!/usr/bin/env bash

vm_libvirt_require_base_image() {
  require_readable_file "VM_BASE_IMAGE_PATH" "$VM_BASE_IMAGE_PATH"
}

__vm_libvirt_bake_work_dir() {
  printf '%s/bake-work-%s-%s\n' \
    "$(vm_path_baked_base_image_dir "${VM_BAKED_BASE_IMAGE_FINGERPRINT:?baked base image fingerprint required}")" \
    "$HARNESS_PROJECT_NAME" "$$"
}

__vm_libvirt_bake_disk_path() {
  printf '%s/base-build.qcow2\n' "$(__vm_libvirt_bake_work_dir)"
}

__vm_libvirt_bake_domain_xml_path() {
  printf '%s/base-image-bake.xml\n' "$(__vm_libvirt_bake_work_dir)"
}

__vm_libvirt_bake_seed_iso_path() {
  printf '%s/base-image-bake-seed.iso\n' "$(__vm_libvirt_bake_work_dir)"
}

__vm_libvirt_bake_seed_work_dir() {
  printf '%s/seed\n' "$(__vm_libvirt_bake_work_dir)"
}

vm_libvirt_baked_base_image_fingerprint_file() {
  printf '%s/base-image-fingerprint.txt\n' "$HARNESS_RENDERED_DIR"
}

__vm_libvirt_baked_base_image_fingerprint() {
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
  VM_BAKED_BASE_IMAGE_FINGERPRINT="$(__vm_libvirt_baked_base_image_fingerprint)" || return $?
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

vm_libvirt_require_existing_baked_base_image() {
  if __vm_libvirt_ensure_baked_base_image_pool && vm_libvirt_baked_base_image_ready; then
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

vm_libvirt_base_image_superset_packages_csv() {
  local machine package packages_file
  packages_file="$(mktemp)"
  for machine in "${vm_machines[@]}"; do
    __vm_libvirt_service_packages_for_machine "$machine" >>"$packages_file"
  done
  sort -u "$packages_file" | paste -sd, -
  rm -f "$packages_file"
}

__vm_libvirt_os_baseline_install_script() {
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
    nfs-common) command -v mount.nfs >/dev/null ;;
    nfs-kernel-server) command -v exportfs >/dev/null ;;
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

__vm_libvirt_bake_domain_exists() {
  virsh -c "$VM_LIBVIRT_URI" dominfo "$(__vm_libvirt_bake_domain_name)" >/dev/null 2>&1
}

__vm_libvirt_bake_domain_state() {
  virsh -c "$VM_LIBVIRT_URI" domstate "$(__vm_libvirt_bake_domain_name)" 2>/dev/null ||
    printf 'missing\n'
}

__vm_libvirt_bake_machine_ip() {
  local mac network
  mac="$(__vm_libvirt_bake_machine_mac)"
  network="$(vm_libvirt_network_name)"
  virsh -c "$VM_LIBVIRT_URI" net-dhcp-leases "$network" --mac "$mac" 2>/dev/null |
    awk '$0 ~ /ipv4/ { split($5, address, "/"); print address[1]; found = 1; exit } END { exit !found }'
}

__vm_libvirt_bake_wait_host() {
  local deadline host
  deadline=$((SECONDS + VM_OPERATOR_SSH_TIMEOUT_SECONDS))
  while [ "$SECONDS" -lt "$deadline" ]; do
    host="$(__vm_libvirt_bake_machine_ip 2>/dev/null || true)"
    if [ -n "$host" ]; then
      printf '%s\n' "$host"
      return 0
    fi
    sleep "$VM_OPERATOR_SSH_POLL_SECONDS"
  done
  die "Timed out waiting for DHCP lease for VM base-image bake"
}

__vm_libvirt_bake_ssh_options() {
  printf '%s\n' \
    -i "$HARNESS_TARGET_SSH_IDENTITY_FILE" \
    -o UserKnownHostsFile=/dev/null \
    -o StrictHostKeyChecking=no \
    -o BatchMode=yes \
    -o ConnectTimeout=10 \
    -o LogLevel=ERROR
}

__vm_libvirt_bake_wait_ready() {
  local deadline host
  host="$(__vm_libvirt_bake_wait_host)"
  deadline=$((SECONDS + VM_OPERATOR_SSH_TIMEOUT_SECONDS))
  while [ "$SECONDS" -lt "$deadline" ]; do
    if ssh $(__vm_libvirt_bake_ssh_options) "$VM_OPERATOR_USER@$host" 'printf ready' >/dev/null 2>&1; then
      return 0
    fi
    sleep "$VM_OPERATOR_SSH_POLL_SECONDS"
  done
  die "Timed out waiting for target OS SSH on VM base-image bake ($host)"
}

__vm_libvirt_bake_run() {
  local host script
  script="${1:?script required}"
  host="$(__vm_libvirt_bake_machine_ip)"
  printf '%s\n' "$script" |
    ssh $(__vm_libvirt_bake_ssh_options) "$VM_OPERATOR_USER@$host" bash -s ||
    return $?
}

__vm_libvirt_shutdown_bake_domain() {
  local deadline domain state
  domain="$(__vm_libvirt_bake_domain_name)"
  __vm_libvirt_bake_domain_exists || return 0
  state="$(__vm_libvirt_bake_domain_state)"
  case "$state" in
    running)
      virsh -c "$VM_LIBVIRT_URI" shutdown "$domain" >/dev/null || true
      deadline=$((SECONDS + VM_OPERATOR_SSH_TIMEOUT_SECONDS))
      while [ "$SECONDS" -lt "$deadline" ]; do
        state="$(__vm_libvirt_bake_domain_state)"
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

__vm_libvirt_cleanup_bake_domain() {
  local domain state
  domain="$(__vm_libvirt_bake_domain_name)"
  __vm_libvirt_bake_domain_exists || return 0
  state="$(__vm_libvirt_bake_domain_state)"
  if [ "$state" = running ]; then
    virsh -c "$VM_LIBVIRT_URI" destroy "$domain" >/dev/null || return $?
  fi
  virsh -c "$VM_LIBVIRT_URI" undefine "$domain" --nvram >/dev/null 2>&1 ||
    virsh -c "$VM_LIBVIRT_URI" undefine "$domain" >/dev/null 2>&1 || return $?
  __vm_libvirt_bake_domain_exists && return 1
  return 0
}

__vm_libvirt_write_baked_base_image_marker() {
  local image marker packages pool target volume baked_sha256 tmp
  image="$(vm_libvirt_baked_base_image_path)"
  marker="$(vm_libvirt_baked_base_image_marker_path)"
  packages="$(vm_libvirt_base_image_superset_packages_csv)"
  pool="$(vm_libvirt_baked_base_image_pool_name)"
  target="$(vm_path_baked_base_image_volume_dir "$VM_BAKED_BASE_IMAGE_FINGERPRINT")"
  volume="$(vm_libvirt_baked_base_image_volume_name)"
  baked_sha256="$(__vm_libvirt_volume_sha256 "$pool" "$volume")" || return $?
  tmp="$(mktemp "${marker}.XXXXXX")" || return $?
  if ! cat >"$tmp" <<EOF
schema=$VM_BASE_IMAGE_BAKE_SCHEMA_VERSION
fingerprint=$VM_BAKED_BASE_IMAGE_FINGERPRINT
source_image=$VM_BASE_IMAGE_PATH
source_sha256=$(sha256sum "$VM_BASE_IMAGE_PATH" | awk '{print $1}')
baked_image=$image
baked_sha256=$baked_sha256
storage_pool_name=$pool
storage_pool_target=$target
volume_name=$volume
image_ownership=libvirt-managed
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

__vm_libvirt_baked_base_image_volume_ready() {
  local image pool target volume
  image="$(vm_libvirt_baked_base_image_path)"
  pool="$(vm_libvirt_baked_base_image_pool_name)"
  target="$(vm_path_baked_base_image_volume_dir "$VM_BAKED_BASE_IMAGE_FINGERPRINT")"
  volume="$(vm_libvirt_baked_base_image_volume_name)"
  vm_libvirt_pool_exists "$pool" || return 1
  __vm_libvirt_pool_is_active "$pool" || return 1
  [ "$(vm_libvirt_pool_target "$pool")" = "$target" ] || return 1
  vm_libvirt_volume_exists "$pool" "$volume" || return 1
  [ "$(vm_libvirt_volume_path "$pool" "$volume")" = "$image" ] || return 1
  [ "$(vm_libvirt_volume_value "$pool" "$volume" format)" = qcow2 ] || return 1
  [ "$(vm_libvirt_volume_value "$pool" "$volume" capacity_bytes)" = \
    "$(__vm_libvirt_disk_size_bytes)" ] || return 1
  [ "$(vm_libvirt_volume_value "$pool" "$volume" backing_path)" = \
    "$VM_BASE_IMAGE_PATH" ] || return 1
  [ "$(vm_libvirt_volume_value "$pool" "$volume" backing_format)" = qcow2 ] || return 1
}

vm_libvirt_baked_base_image_ready() {
  local image marker pool target volume status expected_sha actual_sha
  image="$(vm_libvirt_baked_base_image_path)"
  marker="$(vm_libvirt_baked_base_image_marker_path)"
  [ -r "$marker" ] || return 1
  pool="$(vm_libvirt_baked_base_image_pool_name)"
  target="$(vm_path_baked_base_image_volume_dir "$VM_BAKED_BASE_IMAGE_FINGERPRINT")"
  volume="$(vm_libvirt_baked_base_image_volume_name)"
  __vm_libvirt_baked_base_image_volume_ready || return 1
  status="$(marker_value "$marker" status 2>/dev/null || true)"
  [ "$status" = ready ] || return 1
  [ "$(marker_value "$marker" schema 2>/dev/null || true)" = "$VM_BASE_IMAGE_BAKE_SCHEMA_VERSION" ] || return 1
  [ "$(marker_value "$marker" fingerprint 2>/dev/null || true)" = "$VM_BAKED_BASE_IMAGE_FINGERPRINT" ] || return 1
  [ "$(marker_value "$marker" baked_image 2>/dev/null || true)" = "$image" ] || return 1
  [ "$(marker_value "$marker" storage_pool_name 2>/dev/null || true)" = "$pool" ] || return 1
  [ "$(marker_value "$marker" storage_pool_target 2>/dev/null || true)" = "$target" ] || return 1
  [ "$(marker_value "$marker" volume_name 2>/dev/null || true)" = "$volume" ] || return 1
  [ "$(marker_value "$marker" image_ownership 2>/dev/null || true)" = libvirt-managed ] || return 1
  expected_sha="$(marker_value "$marker" baked_sha256 2>/dev/null || true)"
  [ -n "$expected_sha" ] || return 1
  actual_sha="$(__vm_libvirt_volume_sha256 "$pool" "$volume")" || return 1
  [ "$actual_sha" = "$expected_sha" ]
}

__vm_libvirt_baked_base_image_marker_matches_identity() {
  local fingerprint image marker pool target volume
  fingerprint="${1:?fingerprint required}"
  image="${2:?image required}"
  pool="${3:?pool required}"
  target="${4:?target required}"
  volume="${5:?volume required}"
  marker="$(vm_path_baked_base_image_marker "$fingerprint")"
  [ -r "$marker" ] || return 1
  [ "$(marker_value "$marker" status 2>/dev/null || true)" = ready ] || return 1
  [ "$(marker_value "$marker" schema 2>/dev/null || true)" = "$VM_BASE_IMAGE_BAKE_SCHEMA_VERSION" ] || return 1
  [ "$(marker_value "$marker" fingerprint 2>/dev/null || true)" = "$fingerprint" ] || return 1
  [ "$(marker_value "$marker" baked_image 2>/dev/null || true)" = "$image" ] || return 1
  [ "$(marker_value "$marker" storage_pool_name 2>/dev/null || true)" = "$pool" ] || return 1
  [ "$(marker_value "$marker" storage_pool_target 2>/dev/null || true)" = "$target" ] || return 1
  [ "$(marker_value "$marker" volume_name 2>/dev/null || true)" = "$volume" ] || return 1
  [ "$(marker_value "$marker" image_ownership 2>/dev/null || true)" = libvirt-managed ] || return 1
}

__vm_libvirt_baked_base_image_volume_matches_identity() {
  local image pool target volume
  image="${1:?image required}"
  pool="${2:?pool required}"
  target="${3:?target required}"
  volume="${4:?volume required}"
  vm_libvirt_pool_exists "$pool" || return 1
  [ "$(vm_libvirt_pool_target "$pool")" = "$target" ] || return 1
  vm_libvirt_volume_exists "$pool" "$volume" || return 1
  [ "$(vm_libvirt_volume_path "$pool" "$volume")" = "$image" ] || return 1
  [ "$(vm_libvirt_volume_value "$pool" "$volume" format)" = qcow2 ] || return 1
}

__vm_libvirt_baked_base_image_marker_in_use() {
  local fingerprint image marker marker_image marker_fingerprint
  fingerprint="${1:?fingerprint required}"
  image="${2:?image required}"
  while IFS= read -r marker; do
    [ -n "$marker" ] || continue
    marker_fingerprint="$(marker_value "$marker" base_image_fingerprint 2>/dev/null || true)"
    marker_image="$(marker_value "$marker" base_image 2>/dev/null || true)"
    if [ "$marker_fingerprint" = "$fingerprint" ] || [ "$marker_image" = "$image" ]; then
      return 0
    fi
  done < <(find "$(vm_generated_root)/vm-sets" -mindepth 2 -maxdepth 2 \
    -name .loopforge-vm-set.env -type f -print 2>/dev/null | sort)
  return 1
}

__vm_libvirt_baked_base_image_volume_in_use() {
  local image output pool volume volumes
  image="${1:?image required}"
  output="$(virsh -c "$VM_LIBVIRT_URI" pool-list --all --name 2>/dev/null)" || return 2
  while IFS= read -r pool; do
    [ -n "$pool" ] || continue
    case "$pool" in
      loopforge-vm-base-*) continue ;;
      loopforge-vm-*) ;;
      *) continue ;;
    esac
    volumes="$(virsh -c "$VM_LIBVIRT_URI" vol-list "$pool" --name 2>/dev/null)" || return 2
    while IFS= read -r volume; do
      [ -n "$volume" ] || continue
      [ "$(vm_libvirt_volume_value "$pool" "$volume" backing_path 2>/dev/null || true)" != "$image" ] ||
        return 0
    done <<<"$volumes"
  done <<<"$output"
  return 1
}

__vm_libvirt_baked_base_image_cache_in_use() {
  local image status
  image="${2:?image required}"
  if __vm_libvirt_baked_base_image_marker_in_use "$1" "$image"; then
    return 0
  fi
  if __vm_libvirt_baked_base_image_volume_in_use "$image"; then
    return 0
  else
    status=$?
  fi
  case "$status" in
    1) return 1 ;;
    *) return 2 ;;
  esac
}

vm_libvirt_prune_baked_base_image_cache_after_destroy() {
  local cache_dir fingerprint image in_use_status lock lock_fd pool target volume
  fingerprint="${VM_DESTROY_CACHE_FINGERPRINT:-}"
  image="${VM_DESTROY_CACHE_IMAGE:-}"
  pool="${VM_DESTROY_CACHE_POOL:-}"
  target="${VM_DESTROY_CACHE_TARGET:-}"
  volume="${VM_DESTROY_CACHE_VOLUME:-}"
  if [ -n "${VM_DESTROY_CACHE_SKIP_REASON:-}" ]; then
    printf 'cache-prune=skipped reason=%s\n' "$VM_DESTROY_CACHE_SKIP_REASON"
    return 0
  fi
  for value in "$fingerprint" "$image" "$pool" "$target" "$volume"; do
    [ -n "$value" ] || {
      printf 'cache-prune=skipped reason=missing-cache-identity\n'
      return 0
    }
  done
  cache_dir="$(vm_path_baked_base_image_dir "$fingerprint")"
  lock="$(vm_path_baked_base_image_lock "$fingerprint")"
  mkdir -p "$(dirname "$lock")" || {
    printf 'cache-prune=skipped reason=lock-unavailable fingerprint=%s\n' "$fingerprint"
    return 0
  }
  exec {lock_fd}>"$lock" || {
    printf 'cache-prune=skipped reason=lock-unavailable fingerprint=%s\n' "$fingerprint"
    return 0
  }
  flock "$lock_fd" || {
    exec {lock_fd}>&-
    printf 'cache-prune=skipped reason=lock-unavailable fingerprint=%s\n' "$fingerprint"
    return 0
  }
  if ! __vm_libvirt_baked_base_image_marker_matches_identity \
    "$fingerprint" "$image" "$pool" "$target" "$volume"; then
    exec {lock_fd}>&-
    printf 'cache-prune=skipped reason=cache-invalid fingerprint=%s\n' "$fingerprint"
    return 0
  fi
  if ! vm_libvirt_pool_exists "$pool"; then
    exec {lock_fd}>&-
    printf 'cache-prune=skipped reason=cache-invalid fingerprint=%s\n' "$fingerprint"
    return 0
  fi
  if ! __vm_libvirt_pool_is_active "$pool"; then
    virsh -c "$VM_LIBVIRT_URI" pool-start "$pool" >/dev/null || {
      exec {lock_fd}>&-
      printf 'cache-prune=skipped reason=remove-failed fingerprint=%s\n' "$fingerprint"
      return 0
    }
  fi
  virsh -c "$VM_LIBVIRT_URI" pool-refresh "$pool" >/dev/null || {
    exec {lock_fd}>&-
    printf 'cache-prune=skipped reason=remove-failed fingerprint=%s\n' "$fingerprint"
    return 0
  }
  if ! __vm_libvirt_baked_base_image_volume_matches_identity \
    "$image" "$pool" "$target" "$volume"; then
    exec {lock_fd}>&-
    printf 'cache-prune=skipped reason=cache-invalid fingerprint=%s\n' "$fingerprint"
    return 0
  fi
  if __vm_libvirt_baked_base_image_cache_in_use "$fingerprint" "$image"; then
    in_use_status=0
  else
    in_use_status=$?
  fi
  case "$in_use_status" in
    0)
      exec {lock_fd}>&-
      printf 'cache-prune=skipped reason=in-use fingerprint=%s\n' "$fingerprint"
      return 0
      ;;
    1) ;;
    *)
      exec {lock_fd}>&-
      printf 'cache-prune=skipped reason=dependency-check-failed fingerprint=%s\n' "$fingerprint"
      return 0
      ;;
  esac
  if vm_libvirt_volume_exists "$pool" "$volume"; then
    virsh -c "$VM_LIBVIRT_URI" vol-delete "$volume" --pool "$pool" >/dev/null || {
      exec {lock_fd}>&-
      printf 'cache-prune=skipped reason=remove-failed fingerprint=%s\n' "$fingerprint"
      return 0
    }
  fi
  vm_libvirt_remove_pool "$pool" || {
    exec {lock_fd}>&-
    printf 'cache-prune=skipped reason=remove-failed fingerprint=%s\n' "$fingerprint"
    return 0
  }
  rm -rf -- "$cache_dir" || {
    exec {lock_fd}>&-
    printf 'cache-prune=skipped reason=remove-failed fingerprint=%s\n' "$fingerprint"
    return 0
  }
  exec {lock_fd}>&-
  printf 'cache-prune=removed fingerprint=%s\n' "$fingerprint"
}

__vm_libvirt_bake_base_image() {
  local final_image packages script tmp_image
  final_image="$(vm_libvirt_baked_base_image_path)"
  tmp_image="$(__vm_libvirt_bake_disk_path)"
  packages="$(vm_libvirt_base_image_superset_packages_csv)"
  if [ -e "$final_image" ] || [ -e "$(vm_libvirt_baked_base_image_marker_path)" ]; then
    printf 'ERROR: Refusing to replace an existing invalid VM baked-image cache entry: %s\n' \
      "$(dirname "$final_image")" >&2
    return 1
  fi
  mkdir -p "$(dirname "$final_image")" "$(__vm_libvirt_bake_work_dir)" || return $?
  vm_libvirt_make_storage_path_searchable "$(dirname "$final_image")" || return $?
  __vm_libvirt_cleanup_bake_domain || return $?
  rm -f "$tmp_image" || return $?
  qemu-img create -f qcow2 -F qcow2 -b "$VM_BASE_IMAGE_PATH" "$tmp_image" >/dev/null || return $?
  qemu-img resize "$tmp_image" "$VM_DOMAIN_DISK_SIZE" >/dev/null || return $?
  __vm_libvirt_render_bake_seed_media || return $?
  __vm_libvirt_render_bake_domain_xml || return $?
  script="$(__vm_libvirt_os_baseline_install_script base-image-bake "$packages")
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
    virsh -c "$VM_LIBVIRT_URI" define "$(__vm_libvirt_bake_domain_xml_path)" >/dev/null &&
      virsh -c "$VM_LIBVIRT_URI" start "$(__vm_libvirt_bake_domain_name)" >/dev/null &&
      __vm_libvirt_bake_wait_ready &&
      __vm_libvirt_bake_run 'command -v cloud-init >/dev/null 2>&1 && sudo cloud-init status --wait >/dev/null || true' &&
      __vm_libvirt_bake_run "$script" &&
      __vm_libvirt_shutdown_bake_domain
  }; then
    __vm_libvirt_cleanup_bake_domain || true
    rm -rf "$(__vm_libvirt_bake_work_dir)" || true
    return 1
  fi
  __vm_libvirt_cleanup_bake_domain || return $?
  mv "$tmp_image" "$final_image" || return $?
  __vm_libvirt_ensure_baked_base_image_pool || return $?
  __vm_libvirt_baked_base_image_volume_ready || {
    printf 'ERROR: VM baked base image is not a valid libvirt-managed qcow2 volume: %s\n' \
      "$final_image" >&2
    return 1
  }
  __vm_libvirt_write_baked_base_image_marker || return $?
  rm -rf "$(__vm_libvirt_bake_work_dir)" || return $?
  printf 'base-image-ownership=libvirt-managed pool=%s volume=%s image=%s\n' \
    "$(vm_libvirt_baked_base_image_pool_name)" \
    "$(vm_libvirt_baked_base_image_volume_name)" "$final_image"
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
  if ! __vm_libvirt_ensure_baked_base_image_pool; then
    exec {lock_fd}>&-
    return 1
  fi
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
  __vm_libvirt_bake_base_image
  rc=$?
  exec {lock_fd}>&-
  return "$rc"
}

__vm_libvirt_service_packages_for_machine() {
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
      printf '%s\n' ca-certificates curl fontconfig nfs-common openjdk-21-jre openssh-client rsync tar unzip wget ldap-utils
      ;;
    jenkins-agent)
      printf '%s\n' ca-certificates curl nfs-kernel-server openjdk-21-jre-headless openssh-server rsync tar wget git unzip
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
$(__vm_libvirt_service_packages_for_machine "$machine")
EOF
}
