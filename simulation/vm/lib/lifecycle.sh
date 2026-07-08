#!/usr/bin/env bash

vm_write_harness_evidence() {
  local checkpoint status command_name log_ref message file
  local q_mode q_timestamp q_run q_set q_checkpoint q_command q_status
  local q_message q_log_ref q_redaction q_marker q_vm_set_marker
  checkpoint="${1:?checkpoint required}"
  status="${2:?status required}"
  command_name="${3:?command required}"
  log_ref="${4:-not-applicable}"
  message="${5:-}"
  mkdir -p "$HARNESS_EVIDENCE_DIR"
  file="$(evidence_record_path "$HARNESS_EVIDENCE_DIR" "$checkpoint" harness)"
  q_mode="$(json_quote "$HARNESS_MODE")"
  q_timestamp="$(json_quote "$(iso_timestamp_utc)")"
  q_run="$(json_quote "$HARNESS_RUN_ID")"
  q_set="$(json_quote "$LOOPFORGE_VM_SET_ID")"
  q_checkpoint="$(json_quote "$checkpoint")"
  q_command="$(json_quote "$command_name")"
  q_status="$(json_quote "$status")"
  q_message="$(json_quote "$message")"
  q_log_ref="$(json_quote "$log_ref")"
  q_redaction="$(json_quote "secrets-not-recorded")"
  q_marker="$(json_quote "${HARNESS_RUN_MARKER:-not-created}")"
  q_vm_set_marker="$(json_quote "${HARNESS_VM_SET_MARKER:-not-created}")"
  cat >"$file" <<EOF
{
  "verification_mode": $q_mode,
  "timestamp": $q_timestamp,
  "package_version": "gerrit-jenkins-setup",
  "helper_command_version": "simulation/vm/simulate.sh",
  "role_or_environment": "harness",
  "checkpoint": $q_checkpoint,
  "command": $q_command,
  "status": $q_status,
  "run_id": $q_run,
  "vm_set_id": $q_set,
  "run_marker": $q_marker,
  "vm_set_marker": $q_vm_set_marker,
  "bounded_log": $q_log_ref,
  "message": $q_message,
  "redaction": $q_redaction
}
EOF
  chmod 0600 "$file"
  printf '%s\n' "$file"
}

vm_cmd_blocked_m1() {
  local command_name role
  command_name="${1:?command required}"
  role="${2:-}"
  vm_config_load "$HARNESS_ENV_FILE"
  print_command_summary "$command_name" "$role" "blocked milestone=M1 reason=not-implemented no-vm-resources-changed"
  return 2
}

vm_cmd_preflight() {
  local evidence
  vm_config_load "$HARNESS_ENV_FILE"
  vm_config_ensure_m1_dirs
  require_command python3
  require_command sha256sum
  require_command awk
  [ -f "$vm_env_example" ] || die "Missing VM example env: $vm_env_example"
  [ -f "$vm_dir/README.md" ] || die "Missing VM README"
  [ -f "$vm_dir/design.md" ] || die "Missing VM design doc"
  [ -f "$vm_dir/sequences.md" ] || die "Missing VM command sequence doc"
  [ -x "$repo_root/scripts/integration-setup.sh" ] ||
    die "Missing executable integration helper: $repo_root/scripts/integration-setup.sh"
  vm_libvirt_preflight_readonly >/dev/null
  evidence="$(vm_write_harness_evidence preflight pass "simulate.sh preflight" "not-applicable" "M1 static wiring passed; libvirt/KVM mutation and ownership checks are deferred to M2")"
  print_command_summary preflight "" "ok mode=$HARNESS_MODE run-id=$HARNESS_RUN_ID vm-set=$LOOPFORGE_VM_SET_ID libvirt=deferred-m2 evidence=$(basename "$evidence")"
}

vm_cmd_init_run() {
  local evidence
  vm_config_init_run
  evidence="$(vm_write_harness_evidence init-run pass "simulate.sh init-run" "not-applicable" "Copied runtime inputs, wrote rendered/runtime config, and recorded the M1 run marker")"
  print_command_summary init-run "" "ok run-id=$HARNESS_RUN_ID vm-set=$LOOPFORGE_VM_SET_ID evidence=$(basename "$evidence")"
}

vm_cmd_status() {
  vm_config_load_runtime
  printf 'status: initialized\n\n'
  printf 'Run\n'
  printf '  %-13s %s\n' 'Run ID' "$HARNESS_RUN_ID"
  printf '  %-13s %s\n' 'VM set' "$LOOPFORGE_VM_SET_ID"
  printf '  %-13s %s\n' 'VM state' 'not-created-m1'
  printf '  %-13s %s\n' 'Libvirt' 'deferred-m2'
  printf '\n'
  printf 'Interfaces\n'
  printf '  %-13s %s\n' 'Gerrit URL' 'pending-up'
  printf '  %-13s %s\n' 'Jenkins URL' 'pending-up'
  printf '  %-13s %s\n' 'Target SSH' 'pending-up'
  printf '\n'
  printf 'Login accounts\n'
  printf '  %-18s  %-14s  %-20s  %-40s\n' 'System' 'Username' 'Password' 'Purpose'
  printf '  %-18s  %-14s  %-20s  %-40s\n' '------------------' '--------------' '--------------------' '----------------------------------------'
  printf '  %-18s  %-14s  %-20s  %-40s\n' 'Gerrit' 'gerrit-admin' 'admin-password' 'Gerrit admin user'
  printf '  %-18s  %-14s  %-20s  %-40s\n' 'Jenkins' 'jenkins-admin' 'admin-password' 'Jenkins admin user'
  printf '  %-18s  %-14s  %-20s  %-40s\n' 'Gerrit' 'test-user' 'test-password' 'Test/change workflow user'
}

vm_cmd_audit_state() {
  local evidence summary libvirt_status ssh_status
  vm_config_load_runtime
  vm_state_audit_readonly
  summary="$(vm_state_read_summary)"
  libvirt_status="$(vm_libvirt_status_readonly)"
  ssh_status="$(vm_ssh_status_readonly)"
  evidence="$(vm_write_harness_evidence audit-state pass "simulate.sh audit-state" "not-applicable" "M1 read-only generated state audit passed; libvirt resources are not created in M1")"
  print_command_summary audit-state "" "ok $summary $libvirt_status $ssh_status evidence=$(basename "$evidence")"
}

vm_cmd_run() {
  vm_cmd_blocked_m1 run ""
}

vm_cmd_create() {
  vm_cmd_blocked_m1 create ""
}

vm_cmd_up() {
  vm_cmd_blocked_m1 up ""
}

vm_cmd_ssh() {
  vm_cmd_blocked_m1 ssh "${1:?role required}"
}

vm_cmd_prepare_artifacts() {
  vm_artifacts_blocked_m1 prepare-artifacts "${1:-}"
}

vm_cmd_stage_artifacts() {
  vm_artifacts_blocked_m1 stage-artifacts "${1:-}"
}

vm_cmd_configure_role() {
  vm_roles_blocked_m1 configure-role "${1:-}"
}

vm_cmd_validate_role() {
  vm_roles_blocked_m1 validate-role "${1:-}"
}

vm_cmd_configure_integration() {
  vm_integration_blocked_m1 configure-integration
}

vm_cmd_validate_integration() {
  vm_integration_blocked_m1 validate-integration
}

vm_cmd_prove_integration() {
  vm_integration_blocked_m1 prove-integration
}

vm_cmd_reboot() {
  local role all target
  role="${1:-}"
  all="${2:-0}"
  target="$role"
  [ "$all" -eq 0 ] || target="all"
  vm_cmd_blocked_m1 reboot "$target"
}

vm_cmd_down() {
  vm_cmd_blocked_m1 down ""
}

vm_cmd_clean() {
  vm_cmd_blocked_m1 clean ""
}

vm_cmd_destroy() {
  vm_cmd_blocked_m1 destroy ""
}
