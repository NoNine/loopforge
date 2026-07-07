#!/usr/bin/env bash

service_for_role() {
  case "${1:-}" in
    gerrit) printf '%s\n' gerrit-target ;;
    jenkins-controller) printf '%s\n' jenkins-controller-target ;;
    jenkins-agent) printf '%s\n' jenkins-agent-target ;;
    *) die "Unknown role '${1:-}'; expected gerrit, jenkins-controller, or jenkins-agent" ;;
  esac
}

test_stub_role_command() {
  local command_name role
  command_name="${1:?command required}"
  role="${2:?role required}"
  [ -n "${HARNESS_TEST_STUB_ROLE_COMMANDS:-}" ] || return 1
  mkdir -p "$(dirname "$HARNESS_TEST_STUB_ROLE_COMMANDS")" "$HARNESS_LOG_DIR"
  printf '%s %s\n' "$command_name" "$role" >>"$HARNESS_TEST_STUB_ROLE_COMMANDS"
  if [ "${HARNESS_TEST_STUB_ROLE_FAIL:-}" = "$role" ] ||
    [ "${HARNESS_TEST_STUB_ROLE_FAIL:-}" = "$command_name:$role" ]; then
    print_command_failure "$command_name" "$role" failed "$HARNESS_LOG_DIR/test-stub-$command_name-$role.log" test-stub-fail
    return 9
  fi
  print_command_summary "$command_name" "$role" ok
  return 0
}

run_role_command_logged() {
  local command_name role output rc
  command_name="${1:?command required}"
  role="${2:?role required}"

  if [ -n "${HARNESS_TEST_STUB_ROLE_COMMANDS:-}" ]; then
    test_stub_role_command "$command_name" "$role"
    return "$?"
  fi

  case "$command_name" in
    prepare-artifacts) output="$(cmd_prepare_artifacts "$role")" || rc=$? ;;
    stage-artifacts) output="$(cmd_stage_artifacts "$role")" || rc=$? ;;
    configure-role) output="$(cmd_configure_role "$role")" || rc=$? ;;
    validate-role) output="$(cmd_validate_role "$role")" || rc=$? ;;
    *) die "Unknown role command: $command_name" ;;
  esac
  rc="${rc:-0}"
  printf '%s\n' "$output"
  return "$rc"
}

run_all_roles() {
  local command_name role rc first_rc
  command_name="${1:?command required}"
  first_rc=0
  for role in "${roles[@]}"; do
    run_role_command_logged "$command_name" "$role" || rc=$?
    rc="${rc:-0}"
    if [ "$rc" -ne 0 ]; then
      if [ "$first_rc" -eq 0 ]; then
        first_rc="$rc"
      fi
    fi
    unset rc
  done
  return "$first_rc"
}
workflow_step() {
  local step
  step="${1:?step required}"
  shift
  printf '==> %s\n' "$step"
  if [ -n "${HARNESS_TEST_WORKFLOW_CALLS:-}" ]; then
    mkdir -p "$(dirname "$HARNESS_TEST_WORKFLOW_CALLS")"
    printf '%s\n' "$step" >>"$HARNESS_TEST_WORKFLOW_CALLS"
    return 0
  fi
  "$@"
}

workflow_downstream_steps() {
  workflow_step up cmd_up
  workflow_step status cmd_status
  workflow_step prepare-artifacts cmd_prepare_artifacts ""
  workflow_step stage-artifacts cmd_stage_artifacts ""
  workflow_step configure-role cmd_configure_role ""
  workflow_step validate-role cmd_validate_role ""
  workflow_step configure-integration cmd_configure_integration
  workflow_step validate-integration cmd_validate_integration
  workflow_step prove-integration cmd_prove_integration
}

cmd_run() {
  bootstrap_harness_env
  if runtime_config_valid; then
    printf 'run: mode=resume run-id=%s\n' "$HARNESS_RUN_ID"
    workflow_downstream_steps
    return
  fi
  if selected_containers_exist; then
    die "Docker generated state is missing or invalid while selected containers exist; run down or clean before running workflow"
  fi
  printf 'run: mode=fresh run-id=%s\n' "$HARNESS_RUN_ID"
  workflow_step preflight cmd_preflight
  workflow_step init-run cmd_init_run
  workflow_downstream_steps
}

cmd_preflight() {
  bootstrap_harness_env
  validate_harness_inputs
  ensure_preflight_dirs
  require_command docker
  require_command python3
  require_command sha256sum
  require_command tar
  require_command awk
  require_command ssh-keygen
  require_command ssh-keyscan
  detect_compose
  require_baseline_label
  [ -x "$integration_helper" ] || die "Missing executable integration helper: $integration_helper"
  [ -f "$compose_file" ] || die "Missing Compose file: $compose_file"
  [ -f "$docker_dir/ldap/50-harness-seed.ldif" ] || die "Missing LDAP seed LDIF"
  [ -f "$docker_dir/target/Dockerfile" ] || die "Missing harness target Dockerfile"
  [ -f "$docker_dir/scripts/harness-sleep.sh" ] || die "Missing harness container entrypoint"
  write_evidence preflight harness pass "simulate.sh preflight" "not-applicable" "Compose provider: $compose_kind; generated output paths are ignored local state" >/dev/null
  print_command_summary preflight "" "ok mode=$HARNESS_MODE compose=$compose_kind"
}

cmd_init_run() {
  bootstrap_harness_env
  require_baseline_label
  if selected_containers_exist; then
    die "Selected Docker simulation containers already exist; run down or clean before starting a fresh init-run workflow"
  fi
  write_rendered_env
  write_evidence init-run harness pass "simulate.sh init-run" "not-applicable" "Rendered redacted harness configuration with Version Baseline values" >/dev/null
  printf 'init-run: ok run-id=%s\n' "$HARNESS_RUN_ID"
}

cmd_up() {
  local log rc evidence
  bootstrap_harness_env
  ensure_runtime_config
  require_command docker
  require_command python3
  require_command sha256sum
  require_command tar
  require_command awk
  require_command ssh-keyscan
  detect_compose
  require_baseline_label
  [ -f "$compose_file" ] || die "Missing Compose file: $compose_file"
  [ -f "$docker_dir/ldap/50-harness-seed.ldif" ] || die "Missing LDAP seed LDIF"
  [ -f "$docker_dir/target/Dockerfile" ] || die "Missing harness target Dockerfile"
  [ -f "$docker_dir/scripts/harness-sleep.sh" ] || die "Missing harness container entrypoint"
  log="$(bounded_log_path up)"
  if compose up -d --build >"$log" 2>&1; then
    rc=0
  else
    rc=$?
    if compose_v1_recreate_bug_detected "$log"; then
      {
        printf 'compose_recovery_required=docker-compose-v1-containerconfig\n'
        printf 'recovery_instruction=run-down-or-clean-before-up\n'
      } >>"$log"
    fi
  fi
  if [ "$rc" -ne 0 ]; then
    evidence="$(write_evidence up harness fail "simulate.sh up" "$log" "Compose up failed")"
    print_command_failure up "" failed "$log" "$evidence"
    return "$rc"
  fi
  check_ubuntu_service_baseline bundle-factory bundle-factory
  check_ubuntu_service_baseline gerrit-target gerrit
  check_ubuntu_service_baseline jenkins-controller-target jenkins-controller
  check_ubuntu_service_baseline jenkins-agent-target jenkins-agent
  if ! stage_target_ssh_authorized_keys "$log"; then
    evidence="$(write_evidence up harness fail "simulate.sh up" "$log" "Post-start target SSH public-key staging failed")"
    print_command_failure up "" failed "$log" "$evidence"
    return 1
  fi
  if ! refresh_target_ssh_known_hosts "$log"; then
    evidence="$(write_evidence up harness fail "simulate.sh up" "$log" "Post-start target SSH known_hosts refresh failed")"
    print_command_failure up "" failed "$log" "$evidence"
    return 1
  fi
  require_running_service ldap
  evidence="$(write_evidence up harness pass "simulate.sh up" "$log" "Started bundle factory, LDAP, Gerrit target, Jenkins controller target, and Jenkins agent target")"
  print_command_summary up "" "started bundle-factory ldap gerrit jenkins-controller jenkins-agent"
}

cmd_status() {
  local gerrit_port jenkins_port
  bootstrap_harness_env
  ensure_runtime_config
  require_command docker
  detect_compose
  require_running_service bundle-factory
  require_running_service ldap
  require_running_service gerrit-target
  require_running_service jenkins-controller-target
  require_running_service jenkins-agent-target
  gerrit_port="$(running_loopback_port_for_service_port gerrit-target 8080/tcp)"
  jenkins_port="$(running_loopback_port_for_service_port jenkins-controller-target 8080/tcp)"

  printf 'status: running\n\n'
  printf 'Run\n'
  printf '  %-13s %s\n' 'Run ID' "$HARNESS_RUN_ID"
  printf '  %-13s %s\n' 'Project' "$HARNESS_PROJECT_NAME"
  printf '  %-13s http://127.0.0.1:%s/\n' 'Gerrit URL' "$gerrit_port"
  printf '  %-13s http://127.0.0.1:%s/login\n' 'Jenkins URL' "$jenkins_port"
  printf '\n'
  printf 'Login accounts\n'
  printf '  %-18s  %-14s  %-20s  %-40s\n' 'System' 'Username' 'Password' 'Purpose'
  printf '  %-18s  %-14s  %-20s  %-40s\n' '------------------' '--------------' '--------------------' '----------------------------------------'
  printf '  %-18s  %-14s  %-20s  %-40s\n' 'Gerrit' 'gerrit-admin' 'admin-password' 'Gerrit admin user'
  printf '  %-18s  %-14s  %-20s  %-40s\n' 'Jenkins' 'jenkins-admin' 'admin-password' 'Jenkins admin user'
  printf '  %-18s  %-14s  %-20s  %-40s\n' 'Gerrit' 'test-user' 'test-password' 'Test/change workflow user'
  printf '  %-18s  %-14s  %-20s  %-40s\n' '------------------' '--------------' '--------------------' '----------------------------------------'
}

target_ssh_env_prefix() {
  case "${1:-}" in
    gerrit) printf '%s\n' INTEGRATION_GERRIT_TARGET ;;
    jenkins-controller) printf '%s\n' INTEGRATION_JENKINS_CONTROLLER_TARGET ;;
    jenkins-agent) printf '%s\n' INTEGRATION_JENKINS_AGENT_TARGET ;;
    *) die "Unknown role '${1:-}'; expected gerrit, jenkins-controller, or jenkins-agent" ;;
  esac
}

target_ssh_inventory_value() {
  local role suffix prefix value
  role="${1:?role required}"
  suffix="${2:?suffix required}"
  prefix="$(target_ssh_env_prefix "$role")"
  eval "value=\${${prefix}_SSH_${suffix}:-}"
  printf '%s\n' "$value"
}

cmd_ssh() {
  local role host port user identity_file known_hosts_file
  role="${1:?role required}"
  bootstrap_harness_env
  ensure_runtime_config
  require_command ssh
  require_running_service "$(service_for_role "$role")"
  require_readable_file "Runtime integration env file" "$HARNESS_INTEGRATION_ENV_FILE"
  set -a
  # shellcheck disable=SC1090
  . "$HARNESS_INTEGRATION_ENV_FILE"
  set +a

  host="$(target_ssh_inventory_value "$role" HOST)"
  port="$(target_ssh_inventory_value "$role" PORT)"
  user="$(target_ssh_inventory_value "$role" USER)"
  identity_file="$(target_ssh_inventory_value "$role" IDENTITY_FILE)"
  known_hosts_file="$(target_ssh_inventory_value "$role" KNOWN_HOSTS_FILE)"

  [ -n "$host" ] || die "Missing target SSH host for role: $role"
  [ -n "$port" ] || die "Missing target SSH port for role: $role"
  [ -n "$user" ] || die "Missing target SSH user for role: $role"
  require_readable_file "Target SSH identity file for $role" "$identity_file"
  require_readable_file "Target SSH known_hosts file for $role" "$known_hosts_file"

  exec ssh -t \
    -p "$port" \
    -i "$identity_file" \
    -o BatchMode=yes \
    -o IdentitiesOnly=yes \
    -o StrictHostKeyChecking=yes \
    -o UserKnownHostsFile="$known_hosts_file" \
    "$user@$host"
}

role_helper_present_in_container() {
  local service helper
  service="${1:?service required}"
  helper="${2:?helper required}"
  compose exec -T "$service" test -x "/workspace/$helper" >/dev/null 2>&1
}

cmd_prepare_artifacts() {
  local role helper service log rc evidence artifact_dir host_env_file role_env_file export_archive
  bootstrap_harness_env
  ensure_runtime_config
  role="${1-}"
  if [ -z "$role" ]; then
    run_all_roles prepare-artifacts
    return
  fi
  if [ -n "${HARNESS_TEST_STUB_ROLE_COMMANDS:-}" ]; then
    test_stub_role_command prepare-artifacts "$role"
    return "$?"
  fi
  helper="$(helper_for_role "$role")"
  service="bundle-factory"
  case "$role" in
    gerrit)
      host_env_file="$(host_gerrit_bundle_factory_env_file)"
      role_env_file="$(gerrit_bundle_factory_env_file)"
      require_readable_file "Rendered Gerrit bundle factory env file; run init-run first" "$host_env_file"
      ;;
    jenkins-controller)
      host_env_file="$(host_jenkins_controller_bundle_factory_env_file)"
      role_env_file="$(jenkins_controller_bundle_factory_env_file)"
      require_readable_file "Rendered Jenkins controller bundle factory env file; run init-run first" "$host_env_file"
      ;;
    jenkins-agent)
      host_env_file="$(host_container_env_file_for_role jenkins-agent "$service")"
      role_env_file="$(container_env_file_for_role jenkins-agent "$service")"
      require_readable_file "Rendered jenkins-agent env file; run init-run first" "$host_env_file"
      ;;
  esac
  require_running_service "$service"

  # Guard the boundary-first model: artifact preparation runs only in the
  # bundle factory, never in target containers.
  require_running_service "$(service_for_role "$role")"
  if compose exec -T "$(service_for_role "$role")" env | grep -q '^HARNESS_ENVIRONMENT=bundle-factory$'; then
    die "Refusing prepare-artifacts: selected target container is incorrectly marked as bundle factory"
  fi

  log="$(bounded_log_path "prepare-artifacts-$role")"
  if ! role_helper_present_in_container "$service" "$helper"; then
    evidence="$(write_evidence prepare-artifacts "$role" blocked "simulate.sh prepare-artifacts" "$log" "Missing executable role helper /workspace/$helper in bundle factory")"
    printf 'ERROR: Missing role helper for %s in bundle factory: /workspace/%s\n' "$role" "$helper" >"$log"
    print_command_failure prepare-artifacts "$role" failed "$log" "$evidence" >&2
    return 1
  fi

  : >"$log"
  role_env_file="$(stage_operator_env_file "$service" "$host_env_file" "$role_env_file" ci-operator ci-operator "$log")"

  if [ "$role" = "gerrit" ]; then
    if compose exec -T -u ci-operator "$service" "/workspace/$helper" --env "$role_env_file" --yes prepare-artifacts >>"$log" 2>&1; then
      rc=0
    else
      rc=$?
    fi
  elif [ "$role" = "jenkins-controller" ]; then
    if compose exec -T -u ci-operator "$service" "/workspace/$helper" --env "$role_env_file" --yes prepare-artifacts >>"$log" 2>&1; then
      rc=0
    else
      rc=$?
    fi
  elif [ "$role" = "jenkins-agent" ]; then
    if compose exec -T -u ci-operator "$service" "/workspace/$helper" --env "$role_env_file" prepare-artifacts >>"$log" 2>&1; then
      rc=0
    else
      rc=$?
    fi
  elif compose exec -T -u ci-operator "$service" "/workspace/$helper" prepare-artifacts >>"$log" 2>&1; then
    rc=0
  else
    rc=$?
  fi
  if [ "$rc" -ne 0 ]; then
    if grep -Eq "is not implemented in this repository step|is a placeholder" "$log"; then
      evidence="$(write_evidence prepare-artifacts "$role" blocked "simulate.sh prepare-artifacts" "$log" "Role helper exists but prepare-artifacts is not implemented yet")"
      printf 'ERROR: Role helper for %s exists but prepare-artifacts is not implemented yet\n' "$role" >&2
    else
      evidence="$(write_evidence prepare-artifacts "$role" fail "simulate.sh prepare-artifacts" "$log" "Role helper prepare-artifacts failed in bundle factory")"
    fi
    print_command_failure prepare-artifacts "$role" failed "$log" "$evidence"
    return "$rc"
  fi

  if ! artifact_dir="$(copy_bundle_factory_artifacts_to_host "$role" "$service" "$log")"; then
    evidence="$(write_evidence prepare-artifacts "$role" fail "simulate.sh prepare-artifacts" "$log" "Role helper did not produce valid manifest/checksum artifacts in bundle factory")"
    print_command_failure prepare-artifacts "$role" failed "$log" "$evidence"
    return 1
  fi
  export_archive="$(exported_artifact_archive_for_role "$role")"

  evidence="$(write_evidence prepare-artifacts "$role" pass "simulate.sh prepare-artifacts" "$log" "Role archive pair produced in bundle factory and exported for operator handoff: source=$artifact_dir export=$export_archive")"
  print_command_summary prepare-artifacts "$role" "ok artifact-export=$(basename "$export_archive")"
}

prepare_target_workspace_for_role() {
  local role service helper log role_env_file
  role="${1:?role required}"
  service="${2:?service required}"
  helper="$(helper_for_role "$role")"
  log="${3:?log required}"
  role_env_file="$(stage_container_role_env "$role" "$service" "$log")"
  compose exec -T -u ci-operator "$service" "/workspace/$helper" --env "$role_env_file" --yes prepare-target-workspace >>"$log" 2>&1
}

cmd_stage_artifacts() {
  local role service archive checksum target_bundle_dir target_payload_dir log evidence
  local staging_root archive_name checksum_name container_archive container_checksum extract_script
  bootstrap_harness_env
  ensure_runtime_config
  role="${1-}"
  if [ -z "$role" ]; then
    run_all_roles stage-artifacts
    return
  fi
  if [ -n "${HARNESS_TEST_STUB_ROLE_COMMANDS:-}" ]; then
    test_stub_role_command stage-artifacts "$role"
    return "$?"
  fi
  service="$(service_for_role "$role")"
  archive="$(exported_artifact_archive_for_role "$role")"
  checksum="$(exported_artifact_checksum_for_role "$role")"
  target_bundle_dir="$(target_bundle_dir_for_role "$role")"
  target_payload_dir="$(target_payload_dir_for_role "$role")"
  staging_root="/var/lib/loopforge/staging"
  archive_name="$(basename "$archive")"
  checksum_name="$(basename "$checksum")"
  container_archive="$staging_root/$archive_name"
  container_checksum="$staging_root/$checksum_name"
  log="$(bounded_log_path "stage-artifacts-$role")"

  require_running_service "$service"
  [ -f "$archive" ] || die "Missing exported artifact archive for $role: $archive"
  [ -f "$checksum" ] || die "Missing exported artifact archive checksum for $role: $checksum"

  : >"$log"
  if ! verify_checksum_file_in_dir "$checksum" "$(dirname "$archive")" "$log"; then
    evidence="$(write_evidence stage-artifacts "$role" fail "simulate.sh stage-artifacts" "$log" "Exported artifact archive checksum verification failed")"
    print_command_failure stage-artifacts "$role" failed "$log" "$evidence"
    return 1
  fi

  if ! prepare_target_workspace_for_role "$role" "$service" "$log"; then
    evidence="$(write_evidence stage-artifacts "$role" fail "simulate.sh stage-artifacts" "$log" "Role helper target workspace preparation failed")"
    print_command_failure stage-artifacts "$role" failed "$log" "$evidence"
    return 1
  fi

  if ! docker_cp_file_to_service "$archive" "$service" "$container_archive" ci-operator ci-operator 0644 "$log"; then
    evidence="$(write_evidence stage-artifacts "$role" fail "simulate.sh stage-artifacts" "$log" "Docker cp waiver transfer of artifact archive failed")"
    print_command_failure stage-artifacts "$role" failed "$log" "$evidence"
    return 1
  fi
  if ! docker_cp_file_to_service "$checksum" "$service" "$container_checksum" ci-operator ci-operator 0644 "$log"; then
    evidence="$(write_evidence stage-artifacts "$role" fail "simulate.sh stage-artifacts" "$log" "Docker cp waiver transfer of artifact checksum failed")"
    print_command_failure stage-artifacts "$role" failed "$log" "$evidence"
    return 1
  fi

  extract_script='
staging_root="$1"
checksum_name="$2"
archive_name="$3"
target_bundle_dir="$4"
target_payload_dir="$5"
cd "$staging_root"
sha256sum -c "$checksum_name"
rm -rf "$target_bundle_dir"
tar --no-same-owner -xzf "$archive_name" -C "$staging_root"
test -d "$target_bundle_dir"
test -f "$target_payload_dir/manifest.txt"
test -f "$target_payload_dir/checksums.sha256"
cd "$target_payload_dir"
sha256sum -c checksums.sha256
'
  if ! compose exec -T -u ci-operator "$service" sh -c "$extract_script" sh \
    "$staging_root" \
    "$checksum_name" \
    "$archive_name" \
    "$target_bundle_dir" \
    "$target_payload_dir" >>"$log" 2>&1; then
    evidence="$(write_evidence stage-artifacts "$role" fail "simulate.sh stage-artifacts" "$log" "Target-side artifact extraction and checksum verification failed")"
    print_command_failure stage-artifacts "$role" failed "$log" "$evidence"
    return 1
  fi
  printf 'target_artifact_extract role=%s service=%s transfer_mode=docker-cp-waiver bundle=%s payload=%s scope=docker-simulation-only\n' \
    "$role" "$service" "$target_bundle_dir" "$target_payload_dir" >>"$log"

  if ! validate_role_baseline_manifest_in_target "$role" "$service" "$log"; then
    evidence="$(write_evidence stage-artifacts "$role" blocked "simulate.sh stage-artifacts" "$log" "Target staged manifest baseline metadata is missing or drifted; comparable readiness is blocked")"
    printf 'ERROR: Target staged baseline metadata for %s is missing or drifted; log=%s evidence=%s\n' "$role" "$log" "$evidence" >&2
    print_command_failure stage-artifacts "$role" blocked "$log" "$evidence" >&2
    return 1
  fi

  evidence="$(write_evidence stage-artifacts "$role" pass "simulate.sh stage-artifacts" "$log" "Artifacts transferred with Docker cp simulation-only waiver, extracted in target, and verified by manifest/checksum before mutation")"
  print_command_summary stage-artifacts "$role" ok
}

cmd_configure_role() {
  local role helper service log rc evidence role_env_file
  bootstrap_harness_env
  ensure_runtime_config
  role="${1:-}"
  if [ -z "$role" ]; then
    run_all_roles configure-role
    return "$?"
  fi
  helper="$(helper_for_role "$role")"
  service="$(service_for_role "$role")"
  require_running_service "$service"

  log="$(bounded_log_path "configure-role-$role")"
  : >"$log"
  if ! role_helper_present_in_container "$service" "$helper"; then
    evidence="$(write_evidence configure-role "$role" blocked "simulate.sh configure-role" "$log" "Missing executable role helper /workspace/$helper in target container")"
    printf 'ERROR: Missing role helper for %s in target container: /workspace/%s\n' "$role" "$helper" >>"$log"
    printf 'exit=1 log=%s evidence=%s\n' "$log" "$evidence" >&2
    return 1
  fi
  role_env_file="$(stage_container_role_env "$role" "$service" "$log")"

  case "$role" in
    gerrit)
      if require_staged_artifacts_in_target gerrit "$service" "$log" &&
        compose_exec_with_ldap_password "$service" "/workspace/$helper" --env "$role_env_file" --yes install >>"$log" 2>&1 &&
        compose_exec_with_ldap_password "$service" "/workspace/$helper" --env "$role_env_file" --yes configure >>"$log" 2>&1; then
        rc=0
      else
        rc=$?
      fi
      ;;
    jenkins-controller)
      if require_staged_artifacts_in_target jenkins-controller "$service" "$log" &&
        compose_exec_with_ldap_password "$service" "/workspace/$helper" --env "$role_env_file" --yes install >>"$log" 2>&1 &&
        compose_exec_with_ldap_password "$service" "/workspace/$helper" --env "$role_env_file" --yes configure-service >>"$log" 2>&1 &&
        compose_exec_with_ldap_password "$service" "/workspace/$helper" --env "$role_env_file" --yes install-plugins >>"$log" 2>&1 &&
        compose_exec_with_ldap_password "$service" "/workspace/$helper" --env "$role_env_file" --yes configure-jcasc >>"$log" 2>&1; then
        rc=0
      else
        rc=$?
      fi
      ;;
    jenkins-agent)
      if require_staged_artifacts_in_target jenkins-agent "$service" "$log" &&
        compose exec -T -u ci-operator "$service" "/workspace/$helper" --env "$role_env_file" --yes install >>"$log" 2>&1 &&
        compose exec -T -u ci-operator "$service" "/workspace/$helper" --env "$role_env_file" --yes configure-runtime >>"$log" 2>&1; then
        rc=0
      else
        rc=$?
      fi
      ;;
    *)
      die "Unknown role for configure-role: $role"
      ;;
  esac

  if [ "$rc" -eq 0 ]; then
    if ! validate_role_baseline_manifest_in_target "$role" "$service" "$log"; then
      evidence="$(write_evidence configure-role "$role" blocked "simulate.sh configure-role" "$log" "Staged artifact baseline metadata is missing or drifted; role configuration cannot be comparable")"
      print_command_failure configure-role "$role" blocked "$log" "$evidence" >&2
      return 1
    fi

    if ! assert_no_placeholder_success "$log"; then
      evidence="$(write_evidence configure-role "$role" fail "simulate.sh configure-role" "$log" "Role configuration produced dummy, placeholder, operation-plan-only, planned-checks-only, or modeled success")"
      print_command_failure configure-role "$role" failed "$log" "$evidence"
      return 1
    fi
    evidence="$(write_evidence configure-role "$role" pass "simulate.sh configure-role" "$log" "Role helper completed role-local install/configuration without placeholder success markers")"
    print_command_summary configure-role "$role" ok
    return 0
  fi

  if grep -Eq "missing_staged_artifacts|sha256sum:|FAILED open or read|WARNING: [0-9]+ listed file" "$log"; then
    evidence="$(write_evidence configure-role "$role" blocked "simulate.sh configure-role" "$log" "Staged artifacts are missing or invalid; run stage-artifacts for this role before configure-role")"
    printf 'ERROR: Staged artifacts for %s are missing or invalid; run stage-artifacts --role %s first\n' "$role" "$role" >&2
  elif grep -Eq "BLOCKED:" "$log"; then
    evidence="$(write_evidence configure-role "$role" blocked "simulate.sh configure-role" "$log" "Role helper reported a blocked runtime configuration requirement")"
    printf 'ERROR: Role helper for %s reported blocked runtime behavior\n' "$role" >&2
  elif grep -Eq "is not implemented in this repository step|is a placeholder" "$log"; then
    evidence="$(write_evidence configure-role "$role" blocked "simulate.sh configure-role" "$log" "Role helper exists but role configuration is not implemented yet")"
    printf 'ERROR: Role helper for %s exists but role configuration is not implemented yet\n' "$role" >&2
  else
    evidence="$(write_evidence configure-role "$role" fail "simulate.sh configure-role" "$log" "Role helper configuration failed")"
  fi
  print_command_failure configure-role "$role" failed "$log" "$evidence"
  return "$rc"
}

cmd_validate_role() {
  local role helper service log rc evidence role_env_file
  bootstrap_harness_env
  ensure_runtime_config
  role="${1:-}"
  if [ -z "$role" ]; then
    run_all_roles validate-role
    return "$?"
  fi
  helper="$(helper_for_role "$role")"
  service="$(service_for_role "$role")"
  require_running_service "$service"
  check_target_os_release "$role"

  log="$(bounded_log_path "validate-role-$role")"
  : >"$log"
  if ! role_helper_present_in_container "$service" "$helper"; then
    evidence="$(write_evidence validate-role "$role" blocked "simulate.sh validate-role" "$log" "Missing executable role helper /workspace/$helper in target container")"
    printf 'ERROR: Missing role helper for %s in target container: /workspace/%s\n' "$role" "$helper" >>"$log"
    printf 'exit=1 log=%s evidence=%s\n' "$log" "$evidence" >&2
    return 1
  fi
  role_env_file="$(stage_container_role_env "$role" "$service" "$log")"

  case "$role" in
    gerrit)
      if compose_exec_with_ldap_password "$service" "/workspace/$helper" --env "$role_env_file" --yes validate >>"$log" 2>&1 &&
        compose_exec_with_ldap_password "$service" "/workspace/$helper" --env "$role_env_file" --yes collect-evidence >>"$log" 2>&1 &&
        normalize_gerrit_role_evidence_logs "$log"; then
        rc=0
      else
        rc=$?
      fi
      ;;
    jenkins-controller)
      if compose_exec_with_ldap_password "$service" "/workspace/$helper" --env "$role_env_file" validate >>"$log" 2>&1 &&
        compose_exec_with_ldap_password "$service" "/workspace/$helper" --env "$role_env_file" collect-evidence >>"$log" 2>&1 &&
        normalize_jenkins_controller_role_evidence_logs "$log"; then
        rc=0
      else
        rc=$?
      fi
      ;;
    jenkins-agent)
      if compose exec -T -u ci-operator "$service" "/workspace/$helper" --env "$role_env_file" validate >>"$log" 2>&1 &&
        compose exec -T -u ci-operator "$service" "/workspace/$helper" --env "$role_env_file" collect-evidence >>"$log" 2>&1 &&
        normalize_jenkins_agent_role_evidence_logs "$log"; then
        rc=0
      else
        rc=$?
      fi
      ;;
    *)
      die "Unknown role for validate-role: $role"
      ;;
  esac

  if [ "$rc" -eq 0 ]; then
    if ! validate_role_baseline_manifest_in_target "$role" "$service" "$log"; then
      evidence="$(write_evidence validate-role "$role" blocked "simulate.sh validate-role" "$log" "Staged artifact baseline metadata is missing or drifted; role readiness cannot be comparable")"
      print_command_failure validate-role "$role" blocked "$log" "$evidence" >&2
      return 1
    fi

    if ! assert_no_placeholder_success "$log"; then
      evidence="$(write_evidence validate-role "$role" fail "simulate.sh validate-role" "$log" "Role validation produced dummy, placeholder, operation-plan-only, planned-checks-only, or modeled success")"
      print_command_failure validate-role "$role" failed "$log" "$evidence"
      return 1
    fi
    evidence="$(write_evidence validate-role "$role" pass "simulate.sh validate-role" "$log" "Role helper validated required real behavior without placeholder success markers")"
    print_command_summary validate-role "$role" ok
    return 0
  fi

  if grep -Eq "missing_staged_artifacts|sha256sum:|FAILED open or read|WARNING: [0-9]+ listed file" "$log"; then
    evidence="$(write_evidence validate-role "$role" blocked "simulate.sh validate-role" "$log" "Staged artifacts are missing or invalid; run stage-artifacts and configure-role for this role before validate-role")"
    printf 'ERROR: Staged artifacts for %s are missing or invalid; run stage-artifacts --role %s first\n' "$role" "$role" >&2
  elif grep -Eq "BLOCKED:" "$log"; then
    evidence="$(write_evidence validate-role "$role" blocked "simulate.sh validate-role" "$log" "Role helper reported a blocked runtime behavior requirement")"
    printf 'ERROR: Role helper for %s reported blocked runtime behavior\n' "$role" >&2
  elif grep -Eq "is not implemented in this repository step|is a placeholder" "$log"; then
    evidence="$(write_evidence validate-role "$role" blocked "simulate.sh validate-role" "$log" "Role helper exists but validate is not implemented yet")"
    printf 'ERROR: Role helper for %s exists but validate is not implemented yet\n' "$role" >&2
  else
    evidence="$(write_evidence validate-role "$role" fail "simulate.sh validate-role" "$log" "Role helper validate failed; readiness is not proven")"
  fi
  print_command_failure validate-role "$role" failed "$log" "$evidence"
  return "$rc"
}

integration_args=()

refresh_integration_args() {
  integration_args=(
    --gerrit-env "$HARNESS_GERRIT_ENV_FILE"
    --jenkins-controller-env "$HARNESS_JENKINS_CONTROLLER_ENV_FILE"
    --jenkins-agent-env "$HARNESS_JENKINS_AGENT_ENV_FILE"
    --integration-env "$HARNESS_INTEGRATION_ENV_FILE"
  )
}

write_blocked_integration_evidence() {
  local checkpoint log reason
  checkpoint="${1:?checkpoint required}"
  log="${2:?log required}"
  reason="${3:?reason required}"
  write_evidence "$checkpoint" integration blocked "scripts/integration-setup.sh" "$log" "$reason" >/dev/null
}

integration_validate_marker_path() {
  printf '%s/rendered/integration-validate-pass.env\n' "$HARNESS_HOST_DIR"
}

write_integration_validate_marker() {
  local marker
  marker="$(integration_validate_marker_path)"
  write_checkpoint_marker \
    "$marker" \
    "$HARNESS_MODE" \
    "$HARNESS_RUN_ID" \
    "$HARNESS_PROJECT_NAME" \
    "$HARNESS_RUNTIME_ENV"
}

prove_integration_validate_marker() {
  local marker
  marker="$(integration_validate_marker_path)"
  [ -f "$marker" ] || die "Missing successful validate-integration marker; run validate-integration first"
  verify_checkpoint_marker \
    "$marker" \
    "$HARNESS_MODE" \
    "$HARNESS_RUN_ID" \
    "$HARNESS_PROJECT_NAME" \
    "$HARNESS_RUNTIME_ENV" \
    "Validate-integration marker"
}

cmd_configure_integration() {
  local log rc evidence
  bootstrap_harness_env
  ensure_runtime_config
  refresh_integration_args

  [ -x "$integration_helper" ] || die "Missing executable integration helper: $integration_helper"
  log="$(bounded_log_path configure-integration)"
  "$integration_helper" "${integration_args[@]}" --yes configure-integration >"$log" 2>&1 || rc=$?
  rc="${rc:-0}"
  if [ "$rc" -eq 0 ]; then
    if ! assert_no_forbidden_success_markers "$log"; then
      evidence="$(write_evidence configure-integration integration fail "simulate.sh configure-integration" "$log" "Forbidden success marker found in integration configuration log")"
      print_command_failure configure-integration "" failed "$log" "$evidence"
      return 1
    fi
    evidence="$(write_evidence configure-integration integration pass "simulate.sh configure-integration" "$log" "Shared integration helper completed cross-role setup/configuration")"
    print_command_summary configure-integration "" ok
    return 0
  fi

  evidence="$(write_evidence configure-integration integration fail "simulate.sh configure-integration" "$log" "Shared integration helper failed cross-role setup/configuration")"
  print_command_failure configure-integration "" failed "$log" "$evidence"
  return "$rc"
}

cmd_validate_integration() {
  local log rc evidence
  bootstrap_harness_env
  ensure_runtime_config
  refresh_integration_args

  [ -x "$integration_helper" ] || die "Missing executable integration helper: $integration_helper"
  log="$(bounded_log_path validate-integration)"
  "$integration_helper" "${integration_args[@]}" --yes validate-integration >"$log" 2>&1 || rc=$?
  rc="${rc:-0}"
  if [ "$rc" -eq 0 ]; then
    if ! assert_no_forbidden_success_markers "$log"; then
      evidence="$(write_evidence validate-integration integration fail "simulate.sh validate-integration" "$log" "Forbidden success marker found in integration validation log")"
      print_command_failure validate-integration "" failed "$log" "$evidence"
      return 1
    fi
    evidence="$(write_evidence validate-integration integration pass "simulate.sh validate-integration" "$log" "Shared integration helper validated cross-role readiness without end-to-end proof")"
    write_integration_validate_marker
    print_command_summary validate-integration "" ok
    return 0
  fi

  write_blocked_integration_evidence jenkins-to-gerrit-ssh "$log" "Blocked: shared integration helper has not implemented real Jenkins-to-Gerrit SSH validation"
  write_blocked_integration_evidence agent-connection "$log" "Blocked: shared integration helper has not implemented real Jenkins-to-agent readiness validation"
  evidence="$(write_evidence validate-integration integration blocked "simulate.sh validate-integration" "$log" "Shared integration helper reported blocked cross-role validation; Docker simulation cannot claim readiness")"
  print_command_summary validate-integration "" blocked
  return "$rc"
}

cmd_prove_integration() {
  local log rc evidence
  bootstrap_harness_env
  ensure_runtime_config
  refresh_integration_args
  prove_integration_validate_marker

  [ -x "$integration_helper" ] || die "Missing executable integration helper: $integration_helper"
  log="$(bounded_log_path prove-integration)"
  "$integration_helper" "${integration_args[@]}" --yes prove-integration >"$log" 2>&1 || rc=$?
  rc="${rc:-0}"
  if [ "$rc" -eq 0 ]; then
    if ! assert_no_forbidden_success_markers "$log"; then
      evidence="$(write_evidence prove-integration integration fail "simulate.sh prove-integration" "$log" "Forbidden success marker found in integration proof log")"
      print_command_failure prove-integration "" failed "$log" "$evidence"
      return 1
    fi
    evidence="$(write_evidence prove-integration integration pass "simulate.sh prove-integration" "$log" "Shared integration helper proved disposable change, Gerrit event receipt, Jenkins job scheduling, agent execution, and Verified +1")"
    print_command_summary prove-integration "" ok
    return 0
  fi

  write_blocked_integration_evidence job-execution "$log" "Blocked: shared integration helper has not implemented real disposable Jenkins job execution proof"
  write_blocked_integration_evidence verified-vote "$log" "Blocked: shared integration helper has not implemented real Gerrit Verified +1 vote proof"
  evidence="$(write_evidence prove-integration integration blocked "simulate.sh prove-integration" "$log" "Shared integration helper reported blocked proof; Docker simulation cannot claim end-to-end success")"
  print_command_summary prove-integration "" blocked
  return "$rc"
}

cmd_audit_state() {
  bootstrap_harness_env
  ensure_runtime_config
  require_command docker
  detect_compose
  verify_selected_container_mounts
  print_command_summary audit-state "" "ok"
}

cmd_down() {
  local log rc evidence container
  bootstrap_harness_env
  require_command docker
  if runtime_config_valid; then
    detect_compose
    log="$(bounded_log_path down)"
    if compose down >"$log" 2>&1; then
      rc=0
    else
      rc=$?
    fi
  else
    ensure_preflight_dirs
    log="$(bounded_log_path down)"
    rc=0
    while IFS= read -r container; do
      [ -n "$container" ] || continue
      if docker rm -f "$container" >>"$log" 2>&1; then
        printf 'recovery_container_removed name=%s\n' "$container" >>"$log"
      else
        rc=$?
      fi
    done <<EOF
$(existing_selected_container_names)
EOF
    docker network rm "${HARNESS_PROJECT_NAME}_harness" >>"$log" 2>&1 || true
    printf 'recovery_mode=bootstrap-only reason=invalid-or-missing-runtime-config\n' >>"$log"
  fi
  if [ "$rc" -ne 0 ]; then
    evidence="$(write_evidence down harness fail "simulate.sh down" "$log" "Compose down failed")"
    print_command_failure down "" failed "$log" "$evidence"
    return "$rc"
  fi
  evidence="$(write_evidence down harness pass "simulate.sh down" "$log" "Stopped harness containers without deleting retained evidence")"
  print_command_summary down "" "stopped harness containers"
}

cleanup_mutable_paths_host() {
  local path
  for path in \
    "$HARNESS_STATE_DIR" \
    "$HARNESS_PRODUCT_HOME_DIR" \
    "$HARNESS_STAGING_DIR" \
    "$HARNESS_HOST_DIR/rendered" \
    "$HARNESS_RUNTIME_INPUT_DIR" \
    "$HARNESS_TARGET_SSH_DIR" \
    "$HARNESS_GERRIT_VALIDATION_SECRET_DIR" \
    "$HARNESS_BUNDLE_FACTORY_RENDERED_DIR" \
    "$HARNESS_BUNDLE_FACTORY_VALIDATION_PUBLIC_DIR" \
    "$HARNESS_LDAP_DATA_DIR" \
    "$HARNESS_LDAP_CONFIG_DIR" \
    "$HARNESS_SHARED_JENKINS_STORAGE_DIR"; do
    [ -e "$path" ] || continue
    rm -rf -- "$path" || return 1
  done
}

cleanup_mutable_paths_container() {
  local log
  log="${1:?log required}"
  docker run --rm \
    --mount "type=bind,source=$HARNESS_GENERATED_RUN_DIR,target=/cleanup-root" \
    "$HARNESS_UBUNTU_IMAGE" \
    sh -c 'rm -rf -- /cleanup-root/target/helper-state /cleanup-root/target/product-homes /cleanup-root/target/artifacts/staging /cleanup-root/target/ldap /cleanup-root/target/shared-jenkins-storage /cleanup-root/host/rendered /cleanup-root/host/runtime-inputs /cleanup-root/host/target-ssh /cleanup-root/host/validation-secrets /cleanup-root/host/bundle-factory' \
    >>"$log" 2>&1
}

backup_and_clear_retained_outputs_container() {
  local log backup_name backup_path uid gid
  log="${1:?log required}"
  backup_name="${2:?backup name required}"
  backup_path="$HARNESS_RETAINED_OUTPUT_BACKUP_DIR/$backup_name"
  uid="$(id -u)"
  gid="$(id -g)"
  docker run --rm \
    --mount "type=bind,source=$HARNESS_GENERATED_RUN_DIR,target=/cleanup-root" \
    "$HARNESS_UBUNTU_IMAGE" \
    sh -c '
      set -e
      backup_name="$1"
      uid="$2"
      gid="$3"
      backup_root="/cleanup-root/host/retained-output-backups/$backup_name"
      mkdir -p "$backup_root/target/artifacts" "$backup_root/host" "$backup_root/target"
      copy_if_present() {
        src="$1"
        dest="$2"
        [ -e "$src" ] || return 0
        mkdir -p "$(dirname "$dest")"
        cp -a "$src" "$dest"
      }
      copy_if_present /cleanup-root/target/artifacts/exported "$backup_root/target/artifacts/exported"
      copy_if_present /cleanup-root/host/evidence "$backup_root/host/evidence"
      copy_if_present /cleanup-root/host/logs "$backup_root/host/logs"
      copy_if_present /cleanup-root/target/evidence "$backup_root/target/evidence"
      copy_if_present /cleanup-root/target/logs "$backup_root/target/logs"
      rm -rf -- /cleanup-root/target/artifacts/exported /cleanup-root/host/evidence /cleanup-root/host/logs /cleanup-root/target/evidence /cleanup-root/target/logs
      chown -R "$uid:$gid" "$backup_root"
    ' sh "$backup_name" "$uid" "$gid" \
    >>"$log" 2>&1
  printf '%s\n' "$backup_path"
}

canonical_run_root_exists_for_recovery() {
  local expected actual_real expected_real
  expected="$(canonical_generated_run_dir)"
  [ "$HARNESS_GENERATED_RUN_DIR" = "$expected" ] || return 1
  [ -d "$HARNESS_GENERATED_RUN_DIR" ] || return 1
  [ ! -L "$HARNESS_GENERATED_RUN_DIR" ] || return 1
  actual_real="$(realpath "$HARNESS_GENERATED_RUN_DIR")"
  expected_real="$(realpath "$expected")"
  [ "$actual_real" = "$expected_real" ]
}

verify_clean_output_dirs() {
  [ -d "$HARNESS_EXPORTED_ARTIFACT_DIR" ] || mkdir -p "$HARNESS_EXPORTED_ARTIFACT_DIR"
  [ -d "$HARNESS_EVIDENCE_DIR" ] || mkdir -p "$HARNESS_EVIDENCE_DIR"
  [ -d "$HARNESS_LOG_DIR" ] || mkdir -p "$HARNESS_LOG_DIR"
  [ -d "$HARNESS_HOST_DIR/evidence/integration" ] || mkdir -p "$HARNESS_HOST_DIR/evidence/integration"
  [ -d "$HARNESS_HOST_DIR/logs/integration" ] || mkdir -p "$HARNESS_HOST_DIR/logs/integration"
  [ -d "$HARNESS_GERRIT_EVIDENCE_DIR" ] || mkdir -p "$HARNESS_GERRIT_EVIDENCE_DIR"
  [ -d "$HARNESS_GERRIT_LOG_DIR" ] || mkdir -p "$HARNESS_GERRIT_LOG_DIR"
  [ -d "$HARNESS_JENKINS_CONTROLLER_EVIDENCE_DIR" ] || mkdir -p "$HARNESS_JENKINS_CONTROLLER_EVIDENCE_DIR"
  [ -d "$HARNESS_JENKINS_CONTROLLER_LOG_DIR" ] || mkdir -p "$HARNESS_JENKINS_CONTROLLER_LOG_DIR"
  [ -d "$HARNESS_JENKINS_AGENT_EVIDENCE_DIR" ] || mkdir -p "$HARNESS_JENKINS_AGENT_EVIDENCE_DIR"
  [ -d "$HARNESS_JENKINS_AGENT_LOG_DIR" ] || mkdir -p "$HARNESS_JENKINS_AGENT_LOG_DIR"
}

cmd_clean() {
  local log rc evidence cleanup_fallback container backup_name backup_path recovery_run_root_exists
  bootstrap_harness_env
  require_command docker
  recovery_run_root_exists=0
  if runtime_config_valid; then
    detect_compose
    validate_canonical_run_root
    log="$(bounded_log_path clean)"
    cleanup_fallback=host
    if compose down --remove-orphans >"$log" 2>&1; then
      rc=0
    else
      rc=$?
    fi
  else
    if canonical_run_root_exists_for_recovery; then
      recovery_run_root_exists=1
    fi
    ensure_preflight_dirs
    log="$(bounded_log_path clean)"
    cleanup_fallback=skipped-invalid-runtime-config
    rc=0
    while IFS= read -r container; do
      [ -n "$container" ] || continue
      if docker rm -f "$container" >>"$log" 2>&1; then
        printf 'recovery_container_removed name=%s\n' "$container" >>"$log"
      else
        rc=$?
      fi
    done <<EOF
$(existing_selected_container_names)
EOF
    docker network rm "${HARNESS_PROJECT_NAME}_harness" >>"$log" 2>&1 || true
    printf 'recovery_mode=bootstrap-only reason=invalid-or-missing-runtime-config\n' >>"$log"
    printf 'host_generated_cleanup=skipped reason=invalid-or-missing-runtime-config\n' >>"$log"
  fi
  if [ "$rc" -ne 0 ]; then
    evidence="$(write_evidence clean harness fail "simulate.sh clean" "$log" "Compose shutdown before cleanup failed")"
    print_command_failure clean "" failed "$log" "$evidence"
    return "$rc"
  fi

  if [ "$cleanup_fallback" = "skipped-invalid-runtime-config" ]; then
    if [ "$recovery_run_root_exists" -eq 1 ]; then
      cleanup_fallback=container-recovery
      backup_name="clean-$(timestamp_utc)"
      if ! cleanup_mutable_paths_container "$log"; then
        evidence="$(write_evidence clean harness fail "simulate.sh clean" "$log" "Generated runtime cleanup failed during recovery")"
        print_command_failure clean "" failed "$log" "$evidence"
        return 1
      fi
      backup_path="$(backup_and_clear_retained_outputs_container "$log" "$backup_name")" || rc=$?
      rc="${rc:-0}"
      if [ "$rc" -ne 0 ]; then
        evidence="$(write_evidence clean harness fail "simulate.sh clean" "$log" "Retained output backup failed during recovery")"
        print_command_failure clean "" failed "$log" "$evidence"
        return "$rc"
      fi
      verify_clean_output_dirs
      evidence="$(write_evidence clean harness pass "simulate.sh clean" "$log" "Removed selected containers, cleaned mutable generated runtime data, and backed up retained outputs during recovery to $backup_path")"
      print_command_summary clean "" "removed containers runtime data backup=$backup_name cleanup=$cleanup_fallback"
      return 0
    else
      evidence="$(write_evidence clean harness pass "simulate.sh clean" "$log" "Removed selected containers with bootstrap recovery; host generated cleanup skipped because runtime config is invalid or missing")"
      print_command_summary clean "" "removed containers cleanup=skipped reason=invalid-or-missing-runtime-config"
      return 0
    fi
  fi

  if ! cleanup_mutable_paths_host >>"$log" 2>&1; then
    cleanup_fallback=container
    cleanup_mutable_paths_container "$log" || rc=$?
    rc="${rc:-0}"
    if [ "$rc" -ne 0 ]; then
      evidence="$(write_evidence clean harness fail "simulate.sh clean" "$log" "Generated runtime cleanup failed")"
      print_command_failure clean "" failed "$log" "$evidence"
      return "$rc"
    fi
  fi
  backup_name="clean-$(timestamp_utc)"
  backup_path="$(backup_and_clear_retained_outputs_container "$log" "$backup_name")" || rc=$?
  rc="${rc:-0}"
  if [ "$rc" -ne 0 ]; then
    evidence="$(write_evidence clean harness fail "simulate.sh clean" "$log" "Retained output backup failed")"
    print_command_failure clean "" failed "$log" "$evidence"
    return "$rc"
  fi
  ensure_preflight_dirs
  verify_clean_output_dirs
  evidence="$(write_evidence clean harness pass "simulate.sh clean" "$log" "Removed mutable generated runtime data and backed up retained outputs to $backup_path")"
  print_command_summary clean "" "removed runtime data backup=$backup_name cleanup=$cleanup_fallback"
}
