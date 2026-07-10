#!/usr/bin/env bash

__vm_baseline_seed_ldif_path() {
  printf '%s/ldap/50-harness-seed.ldif\n' "$vm_dir"
}

__vm_baseline_verify_machine_packages() {
  local machine packages script
  machine="${1:?machine required}"
  packages="$(vm_libvirt_package_list_csv "$machine")"
  script="$(vm_libvirt_os_baseline_verify_script "$packages")"
  vm_ssh_run_machine "$machine" "$script" || return $?
  printf 'os-baseline machine=%s packages=%s source=base-image fingerprint=%s apt-mirror=%s\n' \
    "$machine" "$packages" "$VM_BAKED_BASE_IMAGE_FINGERPRINT" "$HARNESS_UBUNTU_APT_MIRROR"
}

__vm_baseline_verify_machine_packages_all() {
  local machine
  for machine in "${vm_machines[@]}"; do
    __vm_baseline_verify_machine_packages "$machine" || return $?
  done
}

__vm_baseline_configure_ldap_service() {
  local ldif_file seed_b64 script output expected
  ldif_file="$(__vm_baseline_seed_ldif_path)"
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

__vm_baseline_verify_ldap_consumer_reachability() {
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

vm_baseline_verify_prereqs() {
  __vm_baseline_verify_machine_packages_all || return $?
  __vm_baseline_configure_ldap_service || return $?
  __vm_baseline_verify_ldap_consumer_reachability gerrit || return $?
  __vm_baseline_verify_ldap_consumer_reachability jenkins-controller || return $?
  __vm_baseline_write_marker || return $?
  printf 'baseline-prereqs=ready marker=%s\n' \
    "$HARNESS_VM_BASELINE_PREREQS_MARKER"
}

__vm_baseline_write_marker() {
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

vm_baseline_invalidate() {
  rm -f "$HARNESS_VM_BASELINE_PREREQS_MARKER"
}

__vm_baseline_marker_valid() {
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

vm_baseline_require_ready() {
  __vm_baseline_marker_valid ||
    die "Stale VM baseline prerequisite marker: $HARNESS_VM_BASELINE_PREREQS_MARKER"
}

vm_baseline_status() {
  if [ ! -f "$HARNESS_VM_BASELINE_PREREQS_MARKER" ]; then
    printf 'pending'
  elif __vm_baseline_marker_valid; then
    printf 'ready'
  else
    printf 'stale'
  fi
}

vm_baseline_audit_readonly() {
  [ ! -f "$HARNESS_VM_BASELINE_PREREQS_MARKER" ] ||
    vm_baseline_require_ready
}
