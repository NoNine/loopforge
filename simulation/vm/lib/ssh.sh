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
    printf 'LDAP_BIND_PASSWORD=%s\n' "$(shell_quote "$HARNESS_LDAP_BIND_PASSWORD")"
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
  chmod "$LF_MODE_PRIVATE_FILE" "$local_file"
}

vm_ssh_stage_role_helpers() {
  local machine remote_dir remote_tmp path
  local -a source_paths
  machine="${1:?machine required}"
  remote_dir="$(vm_path_guest_role_helpers_root)"
  remote_tmp="$remote_dir.loopforge-tmp-$$"
  mapfile -t source_paths < <(role_helper_source_paths)
  for path in "${source_paths[@]}"; do
    [ -e "$repo_root/$path" ] || die "Missing role helper source: $repo_root/$path"
  done
  vm_libvirt_require_running "$machine" || return $?
  vm_ssh_verify_known_host "$machine" || return $?
  vm_ssh_run_machine "$machine" \
    "set -eu; rm -rf -- $(shell_quote "$remote_tmp"); install -d -m $LF_MODE_PUBLIC_DIR $(shell_quote "$remote_tmp")" || return $?
  tar -C "$repo_root" -cf - "${source_paths[@]}" |
    ssh $(vm_ssh_common_options) "$(vm_ssh_target "$machine")" \
      "set -eu; tar -xf - -C $(shell_quote "$remote_tmp"); find $(shell_quote "$remote_tmp") -type d -exec chmod $LF_MODE_PUBLIC_DIR {} +; find $(shell_quote "$remote_tmp") -type f -exec chmod $LF_MODE_PUBLIC_FILE {} +; chmod $LF_MODE_EXECUTABLE_FILE $(shell_quote "$remote_tmp/scripts/gerrit-setup.sh") $(shell_quote "$remote_tmp/scripts/jenkins-controller-setup.sh") $(shell_quote "$remote_tmp/scripts/jenkins-agent-setup.sh"); rm -rf -- $(shell_quote "$remote_dir"); mv -- $(shell_quote "$remote_tmp") $(shell_quote "$remote_dir"); test -x $(shell_quote "$remote_dir/scripts/gerrit-setup.sh"); test -x $(shell_quote "$remote_dir/scripts/jenkins-controller-setup.sh"); test -x $(shell_quote "$remote_dir/scripts/jenkins-agent-setup.sh")"
}

vm_ssh_stage_role_helpers_all() {
  local machine
  for machine in bundle-factory gerrit jenkins-controller jenkins-agent; do
    vm_ssh_stage_role_helpers "$machine" || return $?
  done
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

vm_ssh_boot_id() {
  vm_ssh_run_machine "${1:?machine required}" \
    'set -eu; cat /proc/sys/kernel/random/boot_id'
}

vm_ssh_wait_unavailable() {
  local machine host deadline
  machine="${1:?machine required}"
  host="$(vm_ssh_machine_host "$machine")"
  deadline=$((SECONDS + VM_OPERATOR_SSH_TIMEOUT_SECONDS))
  while [ "$SECONDS" -lt "$deadline" ]; do
    if ! ssh $(vm_ssh_common_options) "$VM_OPERATOR_USER@$host" 'true' >/dev/null 2>&1; then
      return 0
    fi
    sleep "$VM_OPERATOR_SSH_POLL_SECONDS"
  done
  die "Timed out waiting for target OS SSH to stop during reboot: $machine"
}

vm_ssh_wait_system_ready() {
  local machine output
  machine="${1:?machine required}"
  vm_ssh_wait_ready "$machine"
  vm_ssh_wait_cloud_init "$machine"
  output="$(vm_ssh_run_machine "$machine" 'set -eu; sudo -n systemctl is-system-running --wait')" || return $?
  [ "$output" = running ] ||
    die "Target OS did not reach running system state after reboot: $machine ($output)"
}

vm_ssh_reboot_machine() {
  local machine before after rc
  machine="${1:?machine required}"
  before="$(vm_ssh_boot_id "$machine")" || return $?
  rc=0
  vm_ssh_run_machine "$machine" 'set -eu; sudo -n systemctl reboot' >/dev/null 2>&1 || rc=$?
  case "$rc" in
    0|255) ;;
    *) die "Delegated guest reboot failed for $machine (ssh exit $rc)" ;;
  esac
  vm_ssh_wait_unavailable "$machine" || return $?
  vm_ssh_wait_system_ready "$machine" || return $?
  vm_ssh_verify_known_host "$machine" || return $?
  after="$(vm_ssh_boot_id "$machine")" || return $?
  [ -n "$before" ] && [ -n "$after" ] && [ "$before" != "$after" ] ||
    die "Guest boot ID did not change after reboot: $machine"
  printf 'reboot=ready machine=%s boot-id-before=%s boot-id-after=%s ssh-return=ready system=running\n' \
    "$machine" "$before" "$after"
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
  chmod "$LF_MODE_PRIVATE_FILE" "$HARNESS_TARGET_SSH_KNOWN_HOSTS_FILE"
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
  chmod "$LF_MODE_REVIEW_FILE" "$tmp"
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
