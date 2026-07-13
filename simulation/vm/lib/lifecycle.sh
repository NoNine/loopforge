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
  chmod "$LF_MODE_REVIEW_FILE" "$file"
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
  chmod "$LF_MODE_REVIEW_FILE" "$tmp"
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
  vm_set_summary="$(vm_set_validate_ownership_readonly)" || return 1
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

vm_status_http_url() {
  local machine path
  machine="${1:?machine required}"
  path="${2:?path required}"
  if [ "$(vm_libvirt_domain_state "$machine")" != "running" ]; then
    printf 'pending-up\n'
    return 0
  fi
  printf 'http://%s.%s:8080%s\n' "$machine" "$HARNESS_LDAP_DOMAIN" "$path"
}

vm_cmd_status() {
  local status_label ldap_status gerrit_url jenkins_url
  vm_config_load_runtime
  vm_set_validate_ownership_readonly >/dev/null
  ldap_status="$(vm_baseline_status_summary)"
  status_label="initialized"
  if [ "$(vm_libvirt_domain_state gerrit)" = "running" ] &&
    [ "$(vm_libvirt_domain_state jenkins-controller)" = "running" ] &&
    [ "$(vm_libvirt_domain_state jenkins-agent)" = "running" ]; then
    status_label="running"
  fi
  gerrit_url="$(vm_status_http_url gerrit /)"
  jenkins_url="$(vm_status_http_url jenkins-controller /login)"
  printf 'status: %s\n\n' "$status_label"
  printf 'Run\n'
  printf '  %-13s %s\n' 'Run ID' "$HARNESS_RUN_ID"
  printf '  %-13s %s\n' 'VM set' "$LOOPFORGE_VM_SET_ID"
  printf '  %-13s %s\n' 'Project' "$HARNESS_PROJECT_NAME"
  printf '  %-13s %s\n' 'LDAP' "$ldap_status"
  printf '  %-13s %s\n' 'Gerrit URL' "$gerrit_url"
  printf '  %-13s %s\n' 'Jenkins URL' "$jenkins_url"
  printf '\n'
  printf '  %s\n' '*For host DNS, run simulation/vm/tools/configure-systemd-resolved.sh --help'
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
  vm_set_validate_ownership_readonly >/dev/null
  vm_baseline_audit_readonly
  vm_snapshots_audit_readonly
  summary="$(vm_state_read_summary)"
  libvirt_status="$(vm_libvirt_status_readonly)"
  vm_set_status="$(vm_set_validate_ownership_readonly)"
  ssh_status="$(vm_ssh_status_readonly)"
  log="$(vm_path_bounded_log audit-state)"
  {
    printf '%s\n' "$summary"
    printf 'baseline-prereqs=%s\n' "$(vm_baseline_status)"
    printf '%s\n' "$libvirt_status"
    printf '%s\n' "$vm_set_status"
    printf '%s\n' "$ssh_status"
  } >"$log" 2>&1
  evidence="$(vm_write_harness_evidence audit-state pass "simulate.sh audit-state" "$log" "M2 read-only generated state, VM-set ownership, and libvirt resource audit passed")"
  print_command_summary audit-state "" "ok"
}

vm_workflow_step() {
  local step
  step="${1:?workflow step required}"
  shift
  printf '==> %s\n' "$step"
  if [ -n "${HARNESS_TEST_WORKFLOW_CALLS:-}" ]; then
    mkdir -p "$(dirname "$HARNESS_TEST_WORKFLOW_CALLS")"
    printf '%s\n' "$step" >>"$HARNESS_TEST_WORKFLOW_CALLS"
    return 0
  fi
  "$@"
}

vm_workflow_downstream_steps() {
  vm_workflow_step create vm_cmd_create || return $?
  vm_workflow_step up vm_cmd_up || return $?
  vm_workflow_step status vm_cmd_status || return $?
  vm_workflow_step prepare-artifacts vm_cmd_prepare_artifacts "" || return $?
  vm_workflow_step stage-artifacts vm_cmd_stage_artifacts "" || return $?
  vm_workflow_step configure-role vm_cmd_configure_role "" || return $?
  vm_workflow_step validate-role vm_cmd_validate_role "" || return $?
  vm_workflow_step configure-integration vm_cmd_configure_integration || return $?
  vm_workflow_step validate-integration vm_cmd_validate_integration || return $?
  vm_workflow_step prove-integration vm_cmd_prove_integration || return $?
}

vm_cmd_run_logged() {
  local log
  log="${1:?bounded log required}"
  shift
  ( "$@" ) >"$log" 2>&1
}

vm_cmd_run() {
  if vm_config_runtime_valid; then
    vm_config_load_runtime
    printf 'run: mode=resume run-id=%s vm-set=%s\n' "$HARNESS_RUN_ID" "$LOOPFORGE_VM_SET_ID"
  else
    vm_config_load "$HARNESS_ENV_FILE"
    printf 'run: mode=fresh run-id=%s vm-set=%s\n' "$HARNESS_RUN_ID" "$LOOPFORGE_VM_SET_ID"
    vm_workflow_step preflight vm_cmd_preflight || return $?
    vm_workflow_step init-run vm_cmd_init_run || return $?
  fi
  vm_workflow_downstream_steps || return $?
  print_command_summary run "" "ok run-id=$HARNESS_RUN_ID vm-set=$LOOPFORGE_VM_SET_ID"
}

vm_cmd_create_result_path() {
  printf '%s.result.env\n' "${1:?bounded log required}"
}

vm_cmd_create_write_result() {
  local result_file invalidated reused tmp
  result_file="${1:-}"
  [ -n "$result_file" ] || return 0
  invalidated="${2:?baseline invalidated required}"
  reused="${3:?baseline reused required}"
  tmp="$(mktemp "${result_file}.XXXXXX")" || return $?
  {
    printf 'baseline_invalidated=%s\n' "$invalidated"
    printf 'baseline_reused=%s\n' "$reused"
  } >"$tmp" || {
    rm -f "$tmp"
    return 1
  }
  chmod 0600 "$tmp" || {
    rm -f "$tmp"
    return 1
  }
  mv -- "$tmp" "$result_file"
}

vm_cmd_create_result_value() {
  local result_file key
  result_file="${1:?result file required}"
  key="${2:?result key required}"
  marker_value "$result_file" "$key" 2>/dev/null || printf '0\n'
}

vm_cmd_create_steps() {
  local result_file
  result_file="${1:-}"
  VM_CREATE_BASELINE_INVALIDATED=0
  VM_CREATE_BASELINE_REUSED=0
  vm_cmd_create_write_result "$result_file" 0 0 || return $?
  vm_set_prepare || return $?
  case "$(vm_snapshots_status)" in
    ready)
      vm_baseline_require_ready || return $?
      vm_set_verify_selected_ownership || return $?
      vm_snapshots_verify || return $?
      VM_CREATE_BASELINE_REUSED=1
      vm_cmd_create_write_result "$result_file" "$VM_CREATE_BASELINE_INVALIDATED" "$VM_CREATE_BASELINE_REUSED" || return $?
      printf 'baseline-snapshot=ready source=existing\n'
      vm_libvirt_status_table
      return 0
      ;;
    stale)
      die "Incomplete or mismatched VM baseline snapshot state; destroy the selected VM set before retrying create"
      ;;
  esac
  vm_baseline_invalidate || return $?
  VM_CREATE_BASELINE_INVALIDATED=1
  vm_cmd_create_write_result "$result_file" "$VM_CREATE_BASELINE_INVALIDATED" "$VM_CREATE_BASELINE_REUSED" || return $?
  vm_set_create || return $?
  vm_libvirt_start_set || return $?
  vm_ssh_prepare_all || return $?
  vm_baseline_verify_prereqs || return $?
  vm_libvirt_shutdown_set || return $?
  vm_snapshots_capture || return $?
  vm_libvirt_status_table
}

vm_cmd_create_print_failure() {
  local evidence log result_file
  log="${1:?log required}"
  result_file="${2:-}"
  if [ -n "$result_file" ] &&
    [ "$(vm_cmd_create_result_value "$result_file" baseline_invalidated)" -eq 1 ]; then
    vm_baseline_invalidate || true
  fi
  evidence="$(vm_write_harness_evidence create fail "simulate.sh create" "$log" "M4 VM-set creation or baseline prerequisite proof failed")" ||
    evidence=""
  print_command_failure create "" "failed reason=vm-set-create" "$log" "$evidence"
}

vm_cmd_create() {
  local evidence log result_file
  vm_config_load_runtime
  log="$(vm_path_bounded_log create)"
  result_file="$(vm_cmd_create_result_path "$log")"
  rm -f "$result_file"
  vm_cmd_run_logged "$log" vm_cmd_create_steps "$result_file" || {
    vm_cmd_create_print_failure "$log" "$result_file"
    rm -f "$result_file"
    return 1
  }
  if [ "$(vm_cmd_create_result_value "$result_file" baseline_reused)" -eq 0 ]; then
    vm_write_ldap_evidence "$log" >/dev/null || {
      vm_baseline_invalidate
      evidence="$(vm_write_harness_evidence create fail "simulate.sh create" "$log" "M4 LDAP evidence generation failed after runtime proof")"
      print_command_failure create "" "failed reason=ldap-evidence" "$log" "$evidence"
      rm -f "$result_file"
      return 1
    }
  fi
  rm -f "$result_file"
  evidence="$(vm_write_harness_evidence create pass "simulate.sh create" "$log" "M5 VM set baseline was captured after prerequisite proof")"
  print_command_summary create "" "ok vm-set=$LOOPFORGE_VM_SET_ID baseline-prereqs=ready baseline-snapshot=ready"
}

vm_cmd_up() {
  local evidence log
  vm_config_load_runtime
  log="$(vm_path_bounded_log up)"
  vm_cmd_run_logged "$log" vm_cmd_up_steps || {
    evidence="$(vm_write_harness_evidence up fail "simulate.sh up" "$log" "M3 VM-set startup or target OS SSH readiness failed")"
    print_command_failure up "" "failed reason=vm-set-up" "$log" "$evidence"
    return 1
  }
  evidence="$(vm_write_harness_evidence up pass "simulate.sh up" "$log" "M3 VM set started and target OS SSH readiness passed")"
  print_command_summary up "" "ok vm-set=$LOOPFORGE_VM_SET_ID ssh=ready"
}

vm_cmd_up_steps() {
  vm_set_verify_run_and_set
  vm_libvirt_start_set
  vm_ssh_prepare_all
  vm_ssh_stage_role_helpers_all
  vm_libvirt_status_table
  vm_ssh_status_readonly
}

vm_cmd_ssh() {
  local role machine
  role="${1:?role required}"
  vm_config_load_runtime
  vm_set_verify_run_and_set
  machine="$(vm_ssh_role_machine "$role")"
  vm_libvirt_require_running "$machine"
  vm_ssh_interactive_role "$role"
}

vm_cmd_prepare_artifacts() {
  local role selected log evidence rc
  selected="${1:-}"
  vm_config_load_runtime
  for role in ${selected:-${roles[*]}}; do
    log="$(vm_path_bounded_log "prepare-artifacts-$role")"
    rc=0
    vm_cmd_run_logged "$log" vm_artifacts_prepare_role "$role" || rc=$?
    if [ "$rc" -ne 0 ]; then
      evidence="$(vm_write_artifact_evidence prepare-artifacts "$role" fail "$log" "Bundle-factory helper execution or artifact verification failed")"
      print_command_failure prepare-artifacts "$role" failed "$log" "$evidence"
      return "$rc"
    fi
    evidence="$(vm_write_artifact_evidence prepare-artifacts "$role" pass "$log" "Bundle-factory helper produced and exported a verified artifact archive pair")"
    print_command_summary prepare-artifacts "$role" "ok artifact-export=$(basename "$(vm_artifacts_exported_archive "$role")")"
  done
}

vm_cmd_stage_artifacts() {
  local role selected log evidence rc
  selected="${1:-}"
  vm_config_load_runtime
  for role in ${selected:-${roles[*]}}; do
    log="$(vm_path_bounded_log "stage-artifacts-$role")"
    rc=0
    vm_cmd_run_logged "$log" vm_artifacts_stage_role "$role" || rc=$?
    if [ "$rc" -ne 0 ]; then
      evidence="$(vm_write_artifact_evidence stage-artifacts "$role" fail "$log" "SSH transfer or target-side artifact verification failed")"
      print_command_failure stage-artifacts "$role" failed "$log" "$evidence"
      return "$rc"
    fi
    evidence="$(vm_write_artifact_evidence stage-artifacts "$role" pass "$log" "Target OS SSH transfer and guest-local manifest/checksum verification passed")"
    print_command_summary stage-artifacts "$role" ok
  done
}

vm_cmd_configure_role() {
  local role selected log evidence rc status
  selected="${1:-}"
  vm_config_load_runtime
  for role in ${selected:-${roles[*]}}; do
    log="$(vm_path_bounded_log "configure-role-$role")"
    rc=0
    vm_cmd_run_logged "$log" vm_roles_configure "$role" || rc=$?
    if [ "$rc" -eq 0 ] && { ! vm_roles_assert_no_placeholder_success "$log" || ! vm_roles_assert_no_contradictory_failure "$log"; }; then
      rc=1
    fi
    if [ "$rc" -ne 0 ]; then
      status="$(vm_roles_failure_status "$log")"
      evidence="$(vm_write_role_evidence configure-role "$role" "$status" "$log" "Role configuration failed or emitted forbidden success markers")"
      print_command_failure configure-role "$role" "$status" "$log" "$evidence"
      return "$rc"
    fi
    evidence="$(vm_write_role_evidence configure-role "$role" pass "$log" "Role helper completed target-local installation and configuration")"
    print_command_summary configure-role "$role" ok
  done
}

vm_cmd_validate_role() {
  local role selected log evidence rc status
  selected="${1:-}"
  vm_config_load_runtime
  for role in ${selected:-${roles[*]}}; do
    log="$(vm_path_bounded_log "validate-role-$role")"
    rc=0
    vm_cmd_run_logged "$log" vm_roles_validate "$role" || rc=$?
    if [ "$rc" -eq 0 ] && { ! vm_roles_assert_no_placeholder_success "$log" || ! vm_roles_assert_no_contradictory_failure "$log"; }; then
      rc=1
    fi
    if [ "$rc" -ne 0 ]; then
      status="$(vm_roles_failure_status "$log")"
      evidence="$(vm_write_role_evidence validate-role "$role" "$status" "$log" "Real role readiness or evidence collection failed")"
      print_command_failure validate-role "$role" "$status" "$log" "$evidence"
      return "$rc"
    fi
    evidence="$(vm_write_role_evidence validate-role "$role" pass "$log" "Real role service/runtime readiness and copied target evidence passed")"
    print_command_summary validate-role "$role" ok
  done
}

vm_cmd_configure_integration() {
  local log evidence rc status
  vm_config_load_runtime
  log="$(vm_path_bounded_log configure-integration)"
  rc=0
  vm_cmd_run_logged "$log" vm_integration_configure || rc=$?
  if [ "$rc" -eq 0 ] && { ! vm_integration_assert_no_placeholder_success "$log" || ! vm_integration_assert_no_contradictory_failure "$log"; }; then
    rc=1
  fi
  if [ "$rc" -ne 0 ]; then
    status="$(vm_integration_failure_status "$log")"
    evidence="$(vm_write_integration_evidence configure-integration "$status" "$log" "Shared integration configuration failed or emitted forbidden success markers")"
    print_command_failure configure-integration "" "$status" "$log" "$evidence"
    return "$rc"
  fi
  evidence="$(vm_write_integration_evidence configure-integration pass "$log" "Shared integration helper configured cross-role SSH, shared storage, and trigger state")"
  print_command_summary configure-integration "" ok
}

vm_cmd_validate_integration() {
  local log evidence rc status
  vm_config_load_runtime
  log="$(vm_path_bounded_log validate-integration)"
  rc=0
  vm_cmd_run_logged "$log" vm_integration_validate || rc=$?
  if [ "$rc" -eq 0 ] && { ! vm_integration_assert_no_placeholder_success "$log" || ! vm_integration_assert_no_contradictory_failure "$log"; }; then
    rc=1
  fi
  if [ "$rc" -ne 0 ]; then
    status="$(vm_integration_failure_status "$log")"
    evidence="$(vm_write_integration_evidence validate-integration "$status" "$log" "Passive shared integration validation failed or emitted forbidden success markers")"
    print_command_failure validate-integration "" "$status" "$log" "$evidence"
    return "$rc"
  fi
  evidence="$(vm_write_integration_evidence validate-integration pass "$log" "Passive cross-role integration validation passed")"
  print_command_summary validate-integration "" ok
}

vm_cmd_prove_integration() {
  local log evidence rc status
  vm_config_load_runtime
  log="$(vm_path_bounded_log prove-integration)"
  rc=0
  vm_cmd_run_logged "$log" vm_integration_prove || rc=$?
  if [ "$rc" -eq 0 ] && { ! vm_integration_assert_no_placeholder_success "$log" || ! vm_integration_assert_no_contradictory_failure "$log"; }; then
    rc=1
  fi
  if [ "$rc" -ne 0 ]; then
    status="$(vm_integration_failure_status "$log")"
    evidence="$(vm_write_integration_evidence prove-integration "$status" "$log" "Active integration proof failed or emitted forbidden success markers")"
    print_command_failure prove-integration "" "$status" "$log" "$evidence"
    return "$rc"
  fi
  evidence="$(vm_write_integration_evidence prove-integration pass "$log" "Active cross-role integration proof passed")"
  print_command_summary prove-integration "" ok
}

vm_cmd_reboot() {
  local role all target machine log evidence rc targets
  role="${1:-}"
  all="${2:-0}"
  target="$role"
  [ "$all" -eq 0 ] || target="all"
  vm_config_load_runtime
  if [ "$all" -eq 1 ]; then
    targets="${vm_machines[*]}"
  else
    targets="$(vm_ssh_role_machine "$role")"
  fi
  log="$(vm_path_bounded_log "reboot-$target")"
  rc=0
  vm_cmd_run_logged "$log" vm_cmd_reboot_steps "$targets" || rc=$?
  if [ "$rc" -ne 0 ]; then
    evidence="$(vm_write_reboot_evidence fail "$targets" "$log" "Delegated guest reboot, SSH return, or boot-ID proof failed")"
    print_command_failure reboot "$target" failed "$log" "$evidence"
    return "$rc"
  fi
  evidence="$(vm_write_reboot_evidence pass "$targets" "$log" "Delegated guest reboot changed boot IDs and restored SSH plus required guest service readiness")"
  print_command_summary reboot "$target" ok
}

vm_cmd_reboot_steps() {
  local machine targets
  targets="${1:?targets required}"
  vm_set_verify_run_and_set
  for machine in $targets; do
    vm_libvirt_require_running "$machine"
  done
  for machine in $targets; do
    vm_ssh_reboot_machine "$machine"
    case "$machine" in
      gerrit|jenkins-controller|jenkins-agent)
        vm_state_invalidate_role_validation "$machine"
        vm_roles_assert_reboot_recovery "$machine"
        ;;
    esac
  done
}

vm_write_reboot_evidence() {
  local status targets log_ref message file
  status="${1:?status required}"
  targets="${2:?targets required}"
  log_ref="${3:?bounded log required}"
  message="${4:-}"
  mkdir -p "$HARNESS_EVIDENCE_DIR"
  file="$(evidence_record_path "$HARNESS_EVIDENCE_DIR" reboot harness)"
  cat >"$file" <<EOF
{
  "verification_mode": "vm-simulation",
  "timestamp": $(json_quote "$(iso_timestamp_utc)"),
  "package_version": "gerrit-jenkins-setup",
  "helper_command_version": "simulation/vm/simulate.sh",
  "role_or_environment": "harness",
  "checkpoint": "reboot",
  "command": "reboot",
  "status": $(json_quote "$status"),
  "run_id": $(json_quote "$HARNESS_RUN_ID"),
  "vm_set_id": $(json_quote "$LOOPFORGE_VM_SET_ID"),
  "selected_vm_targets": $(json_quote "$targets"),
  "reboot_path": "target-os-ssh delegated-operator-account",
  "ssh_return": $(json_quote "$([ "$status" = pass ] && printf pass || printf not-proven)"),
  "boot_id_change": $(json_quote "$([ "$status" = pass ] && printf pass || printf not-proven)"),
  "post_reboot_system_readiness": $(json_quote "$([ "$status" = pass ] && printf pass || printf not-proven)"),
  "bounded_log": $(json_quote "$log_ref"),
  "message": $(json_quote "$message"),
  "redaction": "secrets-not-recorded"
}
EOF
  chmod "$LF_MODE_REVIEW_FILE" "$file"
  printf '%s\n' "$file"
}

vm_cmd_down() {
  local evidence log
  vm_config_load_runtime
  log="$(vm_path_bounded_log down)"
  vm_cmd_run_logged "$log" vm_cmd_down_steps || {
    evidence="$(vm_write_harness_evidence down fail "simulate.sh down" "$log" "M3 VM-set graceful shutdown failed")"
    print_command_failure down "" "failed reason=vm-set-down" "$log" "$evidence"
    return 1
  }
  evidence="$(vm_write_harness_evidence down pass "simulate.sh down" "$log" "M3 VM set shut down while retaining disks and generated state")"
  print_command_summary down "" "ok vm-set=$LOOPFORGE_VM_SET_ID"
}

vm_cmd_down_steps() {
  vm_state_verify_run_marker
  vm_set_verify_marker_for_teardown
  vm_libvirt_shutdown_set
  vm_libvirt_status_table
}

vm_cmd_clean() {
  local evidence log reason
  vm_config_load_runtime
  log="$(vm_path_bounded_log clean)"
  vm_cmd_run_logged "$log" vm_cmd_clean_steps || {
    reason=generated-cleanup
    grep -Fq 'vm-set-running operation=clean' "$log" && reason=vm-set-running
    evidence="$(vm_write_harness_evidence clean fail "simulate.sh clean" "$log" "VM generated runtime cleanup failed or VM set was not down")"
    print_command_failure clean "" "failed reason=$reason" "$log" "$evidence"
    return 1
  }
  evidence="$(vm_write_harness_evidence clean pass "simulate.sh clean" "$log" "Cleaned mutable generated runtime state while preserving VM resources and review output")"
  print_command_summary clean "" "ok vm-set=$LOOPFORGE_VM_SET_ID generated-state=cleaned"
}

vm_cmd_clean_steps() {
  vm_state_verify_run_marker
  vm_set_verify_teardown_ownership
  vm_libvirt_require_set_shut_off clean
  vm_state_clean_mutable_run_state
}

vm_cmd_restore_baseline() {
  local evidence log reason
  vm_config_load_runtime
  log="$(vm_path_bounded_log restore-baseline)"
  vm_cmd_run_logged "$log" vm_cmd_restore_baseline_steps || {
    reason=baseline-restore
    grep -Fq 'vm-set-running operation=restore-baseline' "$log" && reason=vm-set-running
    evidence="$(vm_write_harness_evidence restore-baseline fail "simulate.sh restore-baseline" "$log" "Baseline restore failed ownership, snapshot validation, or down-state validation")"
    print_command_failure restore-baseline "" "failed reason=$reason" "$log" "$evidence"
    return 1
  }
  evidence="$(vm_write_harness_evidence restore-baseline pass "simulate.sh restore-baseline" "$log" "Restored the selected owned VM set to the clean baseline snapshot")"
  print_command_summary restore-baseline "" "ok vm-set=$LOOPFORGE_VM_SET_ID baseline=restored"
}

vm_cmd_restore_baseline_steps() {
  vm_state_verify_run_marker
  vm_snapshots_restore
  vm_libvirt_status_table
}

vm_cmd_destroy() {
  local detail evidence log
  if vm_config_runtime_valid; then
    vm_config_load_runtime
  else
    vm_config_load "$HARNESS_ENV_FILE"
  fi
  log="$(vm_path_bounded_log destroy)"
  vm_cmd_run_logged "$log" vm_cmd_destroy_steps || {
    evidence="$(vm_write_harness_evidence destroy fail "simulate.sh destroy" "$log" "M5 selected VM-set destruction failed ownership validation or removal")"
    print_command_failure destroy "" "failed reason=vm-set-destroy" "$log" "$evidence"
    return 1
  }
  evidence="$(vm_write_harness_evidence destroy pass "simulate.sh destroy" "$log" "M5 permanently removed only the selected owned VM set")"
  detail="ok vm-set=$LOOPFORGE_VM_SET_ID removed"
  print_command_summary destroy "" "$detail"
}

vm_cmd_destroy_steps() {
  if [ -f "$HARNESS_RUN_MARKER" ]; then
    vm_state_verify_run_marker
  else
    printf 'recovery-missing-run-marker path=%s\n' "$HARNESS_RUN_MARKER"
  fi
  vm_set_destroy
  vm_set_remove_metadata
}
