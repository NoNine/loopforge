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
  vm_libvirt_require_running "$machine"
  vm_ssh_verify_known_host "$machine"
  printf '%s\n' "$script" | ssh $(vm_ssh_common_options) "$(vm_ssh_target "$machine")" bash -s
}

vm_ssh_run_machine_with_ldap_password() {
  local machine script
  machine="${1:?machine required}"
  script="${2:?script required}"
  vm_libvirt_require_running "$machine"
  vm_ssh_verify_known_host "$machine"
  {
    printf 'LDAP_BIND_PASSWORD=%s\n' "$(shell_quote "$VM_RUNTIME_LDAP_BIND_PASSWORD")"
    printf 'export LDAP_BIND_PASSWORD\n'
    printf '%s\n' "$script"
  } | ssh $(vm_ssh_common_options) "$(vm_ssh_target "$machine")" bash -s
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
