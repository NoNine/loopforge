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

vm_write_ldap_evidence() {
  local log_ref file tmp q_timestamp q_run q_set q_endpoint q_log_ref
  log_ref="${1:?bounded log required}"
  mkdir -p "$HARNESS_EVIDENCE_DIR"
  file="$(evidence_record_path "$HARNESS_EVIDENCE_DIR" create ldap)"
  tmp="$(mktemp "${file}.XXXXXX")"
  q_timestamp="$(json_quote "$(iso_timestamp_utc)")"
  q_run="$(json_quote "$HARNESS_RUN_ID")"
  q_set="$(json_quote "$LOOPFORGE_VM_SET_ID")"
  q_endpoint="$(json_quote "ldap://$HARNESS_LDAP_HOST:$HARNESS_LDAP_PORT")"
  q_log_ref="$(json_quote "$log_ref")"
  cat >"$tmp" <<EOF
{
  "verification_mode": "vm-simulation",
  "timestamp": $q_timestamp,
  "package_version": "gerrit-jenkins-setup",
  "helper_command_version": "simulation/vm/simulate.sh",
  "role_or_environment": "ldap",
  "checkpoint": "create",
  "status": "pass",
  "run_id": $q_run,
  "vm_set_id": $q_set,
  "ldap_endpoint": $q_endpoint,
  "ldap_label": "simulation-only",
  "service_readiness": "pass",
  "seeded_accounts": ["gerrit-admin", "jenkins-admin", "test-user"],
  "seeded_groups": ["gerrit-admins", "jenkins-admins"],
  "local_bind_search": "pass",
  "consumer_bind_search": {
    "gerrit": "pass",
    "jenkins-controller": "pass"
  },
  "bounded_log": $q_log_ref,
  "redaction": "secrets-not-recorded"
}
EOF
  chmod 0600 "$tmp"
  mv -- "$tmp" "$file"
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

vm_cmd_preflight_readonly_checks() {
  libvirt_summary="$(vm_libvirt_preflight_readonly)" || return 1
  vm_set_summary="$(vm_state_validate_vm_set_ownership_readonly)" || return 1
  printf '%s\n' "$libvirt_summary"
  printf '%s\n' "$vm_set_summary"
}

vm_cmd_preflight() {
  local evidence log libvirt_summary vm_set_summary
  vm_config_load "$HARNESS_ENV_FILE"
  vm_config_ensure_m1_dirs
  require_command python3
  require_command sha256sum
  require_command awk
  require_command base64
  require_command flock
  [ -f "$vm_env_example" ] || die "Missing VM example env: $vm_env_example"
  [ -f "$vm_dir/README.md" ] || die "Missing VM README"
  [ -f "$vm_dir/design.md" ] || die "Missing VM design doc"
  [ -f "$vm_dir/sequences.md" ] || die "Missing VM command sequence doc"
  [ -x "$repo_root/scripts/integration-setup.sh" ] ||
    die "Missing executable integration helper: $repo_root/scripts/integration-setup.sh"
  log="$(vm_path_bounded_log preflight)"
  vm_cmd_preflight_readonly_checks >"$log" 2>&1 || {
    evidence="$(vm_write_harness_evidence preflight fail "simulate.sh preflight" "$log" "M2 read-only libvirt/KVM preflight or VM-set ownership validation failed")"
    print_command_failure preflight "" "failed reason=libvirt-or-vm-set-preflight" "$log" "$evidence"
    return 1
  }
  evidence="$(vm_write_harness_evidence preflight pass "simulate.sh preflight" "$log" "M2 read-only static wiring, libvirt/KVM preflight, and VM-set ownership validation passed")"
  print_command_summary preflight "" "ok mode=$HARNESS_MODE libvirt=ok"
}

vm_cmd_init_run() {
  local evidence
  vm_config_init_run
  evidence="$(vm_write_harness_evidence init-run pass "simulate.sh init-run" "not-applicable" "Copied runtime inputs, wrote rendered/runtime config, and recorded the M1 run marker")"
  print_command_summary init-run "" "ok run-id=$HARNESS_RUN_ID"
}

vm_cmd_status() {
  local status_label ldap_status
  vm_config_load_runtime
  vm_state_validate_vm_set_ownership_readonly >/dev/null
  ldap_status="$(vm_state_baseline_prereqs_status)"
  status_label="initialized"
  if [ "$(vm_libvirt_domain_state gerrit)" = "running" ] &&
    [ "$(vm_libvirt_domain_state jenkins-controller)" = "running" ] &&
    [ "$(vm_libvirt_domain_state jenkins-agent)" = "running" ]; then
    status_label="running"
  fi
  printf 'status: %s\n\n' "$status_label"
  printf 'Run\n'
  printf '  %-13s %s\n' 'Run ID' "$HARNESS_RUN_ID"
  printf '  %-13s %s\n' 'VM set' "$LOOPFORGE_VM_SET_ID"
  printf '  %-13s %s\n' 'Project' "$HARNESS_PROJECT_NAME"
  printf '  %-13s %s\n' 'Gerrit URL' 'pending-role-configuration'
  printf '  %-13s %s\n' 'Jenkins URL' 'pending-role-configuration'
  printf '  %-13s %s\n' 'LDAP' "$ldap_status"
  printf '\n'
  printf 'Target SSH\n'
  printf '  %-18s  %-12s  %-15s  %-19s\n' 'Role' 'User' 'Host' 'State'
  printf '  %-18s  %-12s  %-15s  %-19s\n' '------------------' '------------' '---------------' '-------------------'
  vm_ssh_status_readonly
  printf '  %-18s  %-12s  %-15s  %-19s\n' '------------------' '------------' '---------------' '-------------------'
  printf '\n'
  printf 'Login accounts\n'
  printf '  %-18s  %-14s  %-20s  %-40s\n' 'System' 'Username' 'Password' 'Purpose'
  printf '  %-18s  %-14s  %-20s  %-40s\n' '------------------' '--------------' '--------------------' '----------------------------------------'
  printf '  %-18s  %-14s  %-20s  %-40s\n' 'Gerrit' 'gerrit-admin' 'admin-password' 'Gerrit admin user'
  printf '  %-18s  %-14s  %-20s  %-40s\n' 'Jenkins' 'jenkins-admin' 'admin-password' 'Jenkins admin user'
  printf '  %-18s  %-14s  %-20s  %-40s\n' 'Gerrit' 'test-user' 'test-password' 'Test/change workflow user'
  printf '  %-18s  %-14s  %-20s  %-40s\n' '------------------' '--------------' '--------------------' '----------------------------------------'
}

vm_cmd_audit_state() {
  local evidence log summary libvirt_status ssh_status vm_set_status
  vm_config_load_runtime
  vm_state_audit_readonly
  summary="$(vm_state_read_summary)"
  libvirt_status="$(vm_libvirt_status_readonly)"
  vm_set_status="$(vm_state_validate_vm_set_ownership_readonly)"
  ssh_status="$(vm_ssh_status_readonly)"
  log="$(vm_path_bounded_log audit-state)"
  {
    printf '%s\n' "$summary"
    printf 'baseline-prereqs=%s\n' "$(vm_state_baseline_prereqs_status)"
    printf '%s\n' "$libvirt_status"
    printf '%s\n' "$vm_set_status"
    printf '%s\n' "$ssh_status"
  } >"$log" 2>&1
  evidence="$(vm_write_harness_evidence audit-state pass "simulate.sh audit-state" "$log" "M2 read-only generated state, VM-set ownership, and libvirt resource audit passed")"
  print_command_summary audit-state "" "ok"
}

vm_cmd_run() {
  vm_cmd_blocked_m1 run ""
}

vm_cmd_create_steps() {
  VM_CREATE_BASELINE_INVALIDATED=0
  VM_CREATE_BASELINE_REUSED=0
  vm_state_validate_vm_set_ownership_readonly || return $?
  vm_libvirt_require_base_image || return $?
  vm_libvirt_select_baked_base_image || return $?
  vm_state_write_or_verify_vm_set_marker || return $?
  if vm_libvirt_existing_disks_present; then
    vm_libvirt_require_existing_baked_base_image || return $?
    vm_libvirt_require_existing_storage_pool || return $?
    vm_libvirt_verify_existing_disk_identities || return $?
  else
    vm_libvirt_ensure_ssh_key || return $?
    vm_libvirt_define_network || return $?
    vm_libvirt_ensure_baked_base_image || return $?
    vm_libvirt_ensure_storage_pool || return $?
  fi
  case "$(vm_state_baseline_snapshot_status)" in
    ready)
      vm_state_require_baseline_prereqs_marker || return $?
      vm_libvirt_verify_selected_set_ownership || return $?
      vm_libvirt_verify_baseline_snapshots || return $?
      VM_CREATE_BASELINE_REUSED=1
      printf 'baseline-snapshot=ready source=existing\n'
      vm_libvirt_status_table
      return 0
      ;;
    stale)
      die "Incomplete or mismatched VM baseline snapshot state; destroy the selected VM set before retrying create"
      ;;
  esac
  vm_state_invalidate_baseline_prereqs_marker || return $?
  VM_CREATE_BASELINE_INVALIDATED=1
  vm_libvirt_create_set || return $?
  vm_libvirt_start_set || return $?
  vm_ssh_prepare_all || return $?
  vm_libvirt_verify_baseline_prereqs || return $?
  vm_libvirt_shutdown_set || return $?
  vm_libvirt_capture_baseline || return $?
  vm_libvirt_status_table
}

vm_cmd_create() {
  local evidence log
  vm_config_load_runtime
  log="$(vm_path_bounded_log create)"
  vm_cmd_create_steps >"$log" 2>&1 || {
    if [ "${VM_CREATE_BASELINE_INVALIDATED:-0}" -eq 1 ]; then
      vm_state_invalidate_baseline_prereqs_marker
    fi
    evidence="$(vm_write_harness_evidence create fail "simulate.sh create" "$log" "M4 VM-set creation or baseline prerequisite proof failed")"
    print_command_failure create "" "failed reason=vm-set-create" "$log" "$evidence"
    return 1
  }
  if [ "${VM_CREATE_BASELINE_REUSED:-0}" -eq 0 ]; then
    vm_write_ldap_evidence "$log" >/dev/null || {
      vm_state_invalidate_baseline_prereqs_marker
      evidence="$(vm_write_harness_evidence create fail "simulate.sh create" "$log" "M4 LDAP evidence generation failed after runtime proof")"
      print_command_failure create "" "failed reason=ldap-evidence" "$log" "$evidence"
      return 1
    }
  fi
  evidence="$(vm_write_harness_evidence create pass "simulate.sh create" "$log" "M5 VM set baseline was captured after prerequisite proof")"
  print_command_summary create "" "ok vm-set=$LOOPFORGE_VM_SET_ID baseline-prereqs=ready baseline-snapshot=ready"
}

vm_cmd_up() {
  local evidence log
  vm_config_load_runtime
  log="$(vm_path_bounded_log up)"
  {
    vm_state_verify_run_and_vm_set
    vm_libvirt_start_set
    vm_ssh_prepare_all
    vm_libvirt_status_table
    vm_ssh_status_readonly
  } >"$log" 2>&1 || {
    evidence="$(vm_write_harness_evidence up fail "simulate.sh up" "$log" "M3 VM-set startup or target OS SSH readiness failed")"
    print_command_failure up "" "failed reason=vm-set-up" "$log" "$evidence"
    return 1
  }
  evidence="$(vm_write_harness_evidence up pass "simulate.sh up" "$log" "M3 VM set started and target OS SSH readiness passed")"
  print_command_summary up "" "ok vm-set=$LOOPFORGE_VM_SET_ID ssh=ready"
}

vm_cmd_ssh() {
  local role machine
  role="${1:?role required}"
  vm_config_load_runtime
  vm_state_verify_run_and_vm_set
  machine="$(vm_ssh_role_machine "$role")"
  vm_libvirt_require_running "$machine"
  vm_ssh_interactive_role "$role"
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
  local evidence log
  vm_config_load_runtime
  log="$(vm_path_bounded_log down)"
  {
    vm_state_verify_run_marker
    vm_state_verify_vm_set_marker_for_teardown
    vm_libvirt_shutdown_set
    vm_libvirt_status_table
  } >"$log" 2>&1 || {
    evidence="$(vm_write_harness_evidence down fail "simulate.sh down" "$log" "M3 VM-set graceful shutdown failed")"
    print_command_failure down "" "failed reason=vm-set-down" "$log" "$evidence"
    return 1
  }
  evidence="$(vm_write_harness_evidence down pass "simulate.sh down" "$log" "M3 VM set shut down while retaining disks and generated state")"
  print_command_summary down "" "ok vm-set=$LOOPFORGE_VM_SET_ID"
}

vm_cmd_clean() {
  local evidence log
  vm_config_load_runtime
  log="$(vm_path_bounded_log clean)"
  {
    vm_state_verify_run_and_vm_set
    vm_libvirt_restore_baseline
    vm_state_clean_mutable_run_state
  } >"$log" 2>&1 || {
    evidence="$(vm_write_harness_evidence clean fail "simulate.sh clean" "$log" "M5 baseline rollback failed ownership or snapshot validation")"
    print_command_failure clean "" "failed reason=baseline-rollback" "$log" "$evidence"
    return 1
  }
  evidence="$(vm_write_harness_evidence clean pass "simulate.sh clean" "$log" "M5 restored the selected owned VM set and preserved review output")"
  print_command_summary clean "" "ok vm-set=$LOOPFORGE_VM_SET_ID baseline=restored"
}

vm_cmd_destroy() {
  local evidence log
  vm_config_load_runtime
  log="$(vm_path_bounded_log destroy)"
  {
    vm_state_verify_run_marker
    vm_libvirt_destroy_set
    vm_state_remove_vm_set_metadata
  } >"$log" 2>&1 || {
    evidence="$(vm_write_harness_evidence destroy fail "simulate.sh destroy" "$log" "M5 selected VM-set destruction failed ownership validation or removal")"
    print_command_failure destroy "" "failed reason=vm-set-destroy" "$log" "$evidence"
    return 1
  }
  evidence="$(vm_write_harness_evidence destroy pass "simulate.sh destroy" "$log" "M5 permanently removed only the selected owned VM set")"
  print_command_summary destroy "" "ok vm-set=$LOOPFORGE_VM_SET_ID removed"
}
