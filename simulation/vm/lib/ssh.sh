#!/usr/bin/env bash

vm_ssh_role_machine() {
  case "${1:?role required}" in
    gerrit) printf 'gerrit\n' ;;
    jenkins-controller) printf 'jenkins-controller\n' ;;
    jenkins-agent) printf 'jenkins-agent\n' ;;
    *) die "Unknown VM SSH role: $1" ;;
  esac
}

vm_ssh_machine_metadata_path() {
  vm_libvirt_machine_metadata_path "${1:?machine required}"
}

vm_ssh_machine_host() {
  local machine host
  machine="${1:?machine required}"
  host="$(vm_libvirt_machine_ip "$machine" 2>/dev/null || true)"
  [ -n "$host" ] || die "No DHCP lease found for VM machine: $machine"
  printf '%s\n' "$host"
}

vm_ssh_common_options() {
  printf '%s\n' \
    -i "$HARNESS_TARGET_SSH_IDENTITY_FILE" \
    -o "UserKnownHostsFile=$HARNESS_TARGET_SSH_KNOWN_HOSTS_FILE" \
    -o StrictHostKeyChecking=yes \
    -o BatchMode=yes \
    -o IdentitiesOnly=yes \
    -o ConnectTimeout=10 \
    -o LogLevel=ERROR
}

vm_ssh_target() {
  local machine host
  machine="${1:?machine required}"
  host="$(vm_ssh_machine_host "$machine")"
  printf '%s@%s\n' "$VM_OPERATOR_USER" "$host"
}

vm_ssh_run_machine() {
  local machine script
  machine="${1:?machine required}"
  script="${2:?script required}"
  vm_libvirt_require_running "$machine" || return $?
  vm_ssh_verify_known_host "$machine" || return $?
  printf '%s\n' "$script" |
    ssh $(vm_ssh_common_options) "$(vm_ssh_target "$machine")" bash -s ||
    return $?
}

vm_ssh_run_machine_with_ldap_password() {
  local machine script
  machine="${1:?machine required}"
  script="${2:?script required}"
  vm_libvirt_require_running "$machine" || return $?
  vm_ssh_verify_known_host "$machine" || return $?
  {
    printf 'LDAP_BIND_PASSWORD=%s\n' "$(shell_quote "$VM_RUNTIME_LDAP_BIND_PASSWORD")"
    printf 'export LDAP_BIND_PASSWORD\n'
    printf '%s\n' "$script"
  } | ssh $(vm_ssh_common_options) "$(vm_ssh_target "$machine")" bash -s ||
    return $?
}

vm_ssh_copy_file_to_machine_atomic() {
  local machine local_file remote_file mode remote_tmp
  machine="${1:?machine required}"
  local_file="${2:?local file required}"
  remote_file="${3:?remote file required}"
  mode="${4:-0600}"
  [ -f "$local_file" ] || die "Missing SSH transfer source: $local_file"
  vm_libvirt_require_running "$machine" || return $?
  vm_ssh_verify_known_host "$machine" || return $?
  remote_tmp="$remote_file.loopforge-tmp-$$"
  scp -q $(vm_ssh_common_options) "$local_file" \
    "$(vm_ssh_target "$machine"):$remote_tmp" || return $?
  vm_ssh_run_machine "$machine" \
    "set -eu; test -d $(shell_quote "$(dirname "$remote_file")"); chmod $(shell_quote "$mode") $(shell_quote "$remote_tmp"); mv -f -- $(shell_quote "$remote_tmp") $(shell_quote "$remote_file")"
}

vm_ssh_copy_file_from_machine() {
  local machine remote_file local_file
  machine="${1:?machine required}"
  remote_file="${2:?remote file required}"
  local_file="${3:?local file required}"
  vm_libvirt_require_running "$machine" || return $?
  vm_ssh_verify_known_host "$machine" || return $?
  mkdir -p "$(dirname "$local_file")"
  scp -q $(vm_ssh_common_options) \
    "$(vm_ssh_target "$machine"):$remote_file" "$local_file" || return $?
  chmod 0600 "$local_file"
}

vm_ssh_copy_role_package() {
  local machine role helper template_dir remote_dir
  machine="${1:?machine required}"
  role="${2:?role required}"
  helper="$(helper_for_role "$role")"
  template_dir="templates/$role"
  remote_dir="$(vm_path_guest_package_dir "$role")"
  [ -f "$repo_root/$helper" ] || die "Missing role helper: $repo_root/$helper"
  [ -f "$repo_root/scripts/common.sh" ] || die "Missing shared role helper library"
  [ -d "$repo_root/$template_dir" ] || die "Missing role template directory: $repo_root/$template_dir"
  vm_libvirt_require_running "$machine" || return $?
  vm_ssh_verify_known_host "$machine" || return $?
  vm_ssh_run_machine "$machine" \
    "set -eu; if test -e $(shell_quote "$remote_dir"); then chmod -R u+w $(shell_quote "$remote_dir"); rm -rf -- $(shell_quote "$remote_dir"); fi; install -d -m 0700 $(shell_quote "$remote_dir")" || return $?
  tar -C "$repo_root" -cf - scripts/common.sh "$helper" "$template_dir" |
    ssh $(vm_ssh_common_options) "$(vm_ssh_target "$machine")" \
      "set -eu; tar -xf - -C $(shell_quote "$remote_dir"); find $(shell_quote "$remote_dir") -type d -exec chmod 0500 {} +; find $(shell_quote "$remote_dir") -type f -exec chmod 0400 {} +; chmod 0500 $(shell_quote "$remote_dir/$helper")"
}

vm_ssh_remove_role_package() {
  local machine role remote_dir
  machine="${1:?machine required}"
  role="${2:?role required}"
  remote_dir="$(vm_path_guest_package_dir "$role")"
  vm_ssh_run_machine "$machine" \
    "set -eu; if test -e $(shell_quote "$remote_dir"); then chmod -R u+w $(shell_quote "$remote_dir"); rm -rf -- $(shell_quote "$remote_dir"); fi"
}

vm_ssh_wait_host() {
  local machine deadline host
  machine="${1:?machine required}"
  deadline=$((SECONDS + VM_OPERATOR_SSH_TIMEOUT_SECONDS))
  while [ "$SECONDS" -lt "$deadline" ]; do
    host="$(vm_libvirt_machine_ip "$machine" 2>/dev/null || true)"
    if [ -n "$host" ]; then
      printf '%s\n' "$host"
      return 0
    fi
    sleep "$VM_OPERATOR_SSH_POLL_SECONDS"
  done
  die "Timed out waiting for DHCP lease for VM machine: $machine"
}

vm_ssh_wait_ready() {
  local machine host deadline
  machine="${1:?machine required}"
  host="$(vm_ssh_wait_host "$machine")"
  deadline=$((SECONDS + VM_OPERATOR_SSH_TIMEOUT_SECONDS))
  while [ "$SECONDS" -lt "$deadline" ]; do
    if ssh $(vm_ssh_common_options) "$VM_OPERATOR_USER@$host" 'printf ready' >/dev/null 2>&1; then
      return 0
    fi
    sleep "$VM_OPERATOR_SSH_POLL_SECONDS"
  done
  die "Timed out waiting for target OS SSH on $machine ($host)"
}

vm_ssh_wait_cloud_init() {
  local machine host
  machine="${1:?machine required}"
  host="$(vm_ssh_machine_host "$machine")"
  ssh $(vm_ssh_common_options) "$VM_OPERATOR_USER@$host" \
    'command -v cloud-init >/dev/null 2>&1 && sudo cloud-init status --wait >/dev/null || true'
}

vm_ssh_capture_known_host() {
  local machine host tmp deadline
  machine="${1:?machine required}"
  host="$(vm_ssh_wait_host "$machine")"
  mkdir -p "$(dirname "$HARNESS_TARGET_SSH_KNOWN_HOSTS_FILE")"
  touch "$HARNESS_TARGET_SSH_KNOWN_HOSTS_FILE"
  chmod 0600 "$HARNESS_TARGET_SSH_KNOWN_HOSTS_FILE"
  if ssh-keygen -F "$host" -f "$HARNESS_TARGET_SSH_KNOWN_HOSTS_FILE" >/dev/null 2>&1; then
    return 0
  fi
  tmp="$(mktemp "$HARNESS_TARGET_SSH_DIR/known-hosts.XXXXXX")"
  deadline=$((SECONDS + VM_OPERATOR_SSH_TIMEOUT_SECONDS))
  while [ "$SECONDS" -lt "$deadline" ]; do
    if ssh-keyscan -T 10 -H "$host" >"$tmp" 2>/dev/null && [ -s "$tmp" ]; then
      break
    fi
    sleep "$VM_OPERATOR_SSH_POLL_SECONDS"
  done
  [ -s "$tmp" ] || die "Unable to capture SSH host key for $machine ($host)"
  cat "$tmp" >>"$HARNESS_TARGET_SSH_KNOWN_HOSTS_FILE"
  rm -f "$tmp"
}

vm_ssh_verify_known_host() {
  local machine host
  machine="${1:?machine required}"
  host="$(vm_ssh_machine_host "$machine")"
  ssh-keygen -F "$host" -f "$HARNESS_TARGET_SSH_KNOWN_HOSTS_FILE" >/dev/null 2>&1 ||
    die "Missing SSH known-host entry for $machine ($host)"
}

vm_ssh_update_machine_metadata() {
  local machine file tmp host
  machine="${1:?machine required}"
  file="$(vm_ssh_machine_metadata_path "$machine")"
  host="$(vm_ssh_machine_host "$machine")"
  [ -f "$file" ] || die "Missing VM machine metadata: $file"
  tmp="$(mktemp "${file}.XXXXXX")"
  grep -v '^ssh_host=' "$file" >"$tmp" || true
  printf 'ssh_host=%s\n' "$host" >>"$tmp"
  chmod 0600 "$tmp"
  mv -- "$tmp" "$file"
}

vm_ssh_prepare_machine() {
  local machine
  machine="${1:?machine required}"
  vm_libvirt_require_running "$machine"
  vm_ssh_capture_known_host "$machine"
  vm_ssh_wait_ready "$machine"
  vm_ssh_wait_cloud_init "$machine"
  vm_ssh_verify_known_host "$machine"
  vm_ssh_update_machine_metadata "$machine"
}

vm_ssh_prepare_all() {
  local machine
  for machine in "${vm_machines[@]}"; do
    vm_ssh_prepare_machine "$machine"
  done
}

vm_ssh_interactive_role() {
  local role machine host
  role="${1:?role required}"
  machine="$(vm_ssh_role_machine "$role")"
  vm_libvirt_require_running "$machine"
  vm_ssh_verify_known_host "$machine"
  host="$(vm_ssh_machine_host "$machine")"
  ssh -i "$HARNESS_TARGET_SSH_IDENTITY_FILE" \
    -o "UserKnownHostsFile=$HARNESS_TARGET_SSH_KNOWN_HOSTS_FILE" \
    -o StrictHostKeyChecking=yes \
    "$VM_OPERATOR_USER@$host"
}

vm_ssh_status_readonly() {
  local role machine file host status
  for role in "${roles[@]}"; do
    machine="$(vm_ssh_role_machine "$role")"
    file="$(vm_ssh_machine_metadata_path "$machine")"
    host="pending-up"
    status="pending-up"
    if [ -f "$file" ]; then
      host="$(marker_value "$file" ssh_host 2>/dev/null || printf 'pending-up')"
      if [ "$host" != "pending-up" ]; then
        status="not-ready"
        if [ -f "$HARNESS_TARGET_SSH_KNOWN_HOSTS_FILE" ] &&
          ssh-keygen -F "$host" -f "$HARNESS_TARGET_SSH_KNOWN_HOSTS_FILE" >/dev/null 2>&1; then
          status="ready"
        fi
      fi
    fi
    printf '  %-18s  %-12s  %-15s  %-19s\n' "$role" "$VM_OPERATOR_USER" "$host" "$status"
  done
}
