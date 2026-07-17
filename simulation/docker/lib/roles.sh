#!/usr/bin/env bash

docker_roles_configure() {
  local role helper_path service log rc evidence role_env_file
  bootstrap_harness_env
  docker_set_require_runtime
  require_docker_effective_inputs
  role="${1:?role required}"
  helper_path="$(role_helper_path_for_operator ci-operator "$role")"
  service="$(docker_compose_service_for_role "$role")"
  require_running_service "$service"

  log="$(bounded_log_path "configure-role-$role")"
  : >"$log"
  if ! docker_compose_role_helper_present "$service" "$helper_path"; then
    evidence="$(write_evidence configure-role "$role" blocked "simulate.sh configure-role" "$log" "Missing executable role helper $helper_path in target container")"
    printf 'ERROR: Missing role helper for %s in target container: %s\n' "$role" "$helper_path" >>"$log"
    printf 'exit=1 log=%s evidence=%s\n' "$log" "$evidence" >&2
    return 1
  fi
  role_env_file="$(stage_container_role_env "$role" "$service" "$log")"

  case "$role" in
    gerrit)
      if require_staged_artifacts_in_target gerrit "$service" "$log" &&
        compose_exec_with_ldap_password "$service" "$helper_path" --env "$role_env_file" --yes install >>"$log" 2>&1 &&
        compose_exec_with_ldap_password "$service" "$helper_path" --env "$role_env_file" --yes configure >>"$log" 2>&1; then
        rc=0
      else
        rc=$?
      fi
      ;;
    jenkins-controller)
      if require_staged_artifacts_in_target jenkins-controller "$service" "$log" &&
        compose_exec_with_ldap_password "$service" "$helper_path" --env "$role_env_file" --yes install >>"$log" 2>&1 &&
        compose_exec_with_ldap_password "$service" "$helper_path" --env "$role_env_file" --yes configure-service >>"$log" 2>&1 &&
        compose_exec_with_ldap_password "$service" "$helper_path" --env "$role_env_file" --yes install-plugins >>"$log" 2>&1 &&
        compose_exec_with_ldap_password "$service" "$helper_path" --env "$role_env_file" --yes configure-jcasc >>"$log" 2>&1; then
        rc=0
      else
        rc=$?
      fi
      ;;
    jenkins-agent)
      if require_staged_artifacts_in_target jenkins-agent "$service" "$log" &&
        compose exec -T -u ci-operator "$service" "$helper_path" --env "$role_env_file" --yes install >>"$log" 2>&1 &&
        compose exec -T -u ci-operator "$service" "$helper_path" --env "$role_env_file" --yes configure-runtime >>"$log" 2>&1; then
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

__docker_roles_validate_jenkins_controller_authorization() {
  local service log
  service="${1:?service required}"
  log="${2:?log required}"
  compose exec -T -u jenkins "$service" sh -c '
    set -eu
    crumb_json="$(mktemp /tmp/jenkins-auth-crumb.XXXXXX)"
    cookie_jar="$(mktemp /tmp/jenkins-auth-cookie.XXXXXX)"
    script_out="$(mktemp /tmp/jenkins-auth-script.XXXXXX)"
    trap '\''rm -f "$crumb_json" "$cookie_jar" "$script_out"'\'' EXIT
    curl -fsS -u jenkins-admin:admin-password -c "$cookie_jar" \
      "http://jenkins-controller-target:8080/crumbIssuer/api/json" >"$crumb_json"
    crumb="$(sed -n '\''s/.*"crumb":"\([^"]*\)".*/\1/p'\'' "$crumb_json")"
    crumb_field="$(sed -n '\''s/.*"crumbRequestField":"\([^"]*\)".*/\1/p'\'' "$crumb_json")"
    test -n "$crumb"
    test -n "$crumb_field"
    curl -fsS -u jenkins-admin:admin-password -b "$cookie_jar" \
      -H "$crumb_field:$crumb" \
      --data-urlencode script@/workspace/simulation/docker/scripts/verify-jenkins-authorization.groovy \
      "http://jenkins-controller-target:8080/scriptText" >"$script_out"
    grep -Fxq "jenkins-authorization=ready strategy=global-matrix admin=jenkins-admin authenticated=read,job-read,job-build" "$script_out"
    cat "$script_out"
  ' >>"$log" 2>&1
}

docker_roles_validate() {
  local role helper_path service log rc evidence role_env_file
  bootstrap_harness_env
  docker_set_require_runtime
  require_docker_effective_inputs
  role="${1:?role required}"
  helper_path="$(role_helper_path_for_operator ci-operator "$role")"
  service="$(docker_compose_service_for_role "$role")"
  require_running_service "$service"
  check_target_os_release "$role"

  log="$(bounded_log_path "validate-role-$role")"
  : >"$log"
  if ! docker_compose_role_helper_present "$service" "$helper_path"; then
    evidence="$(write_evidence validate-role "$role" blocked "simulate.sh validate-role" "$log" "Missing executable role helper $helper_path in target container")"
    printf 'ERROR: Missing role helper for %s in target container: %s\n' "$role" "$helper_path" >>"$log"
    printf 'exit=1 log=%s evidence=%s\n' "$log" "$evidence" >&2
    return 1
  fi
  role_env_file="$(stage_container_role_env "$role" "$service" "$log")"

  case "$role" in
    gerrit)
      if compose_exec_with_ldap_password "$service" "$helper_path" --env "$role_env_file" --yes validate >>"$log" 2>&1 &&
        compose_exec_with_ldap_password "$service" "$helper_path" --env "$role_env_file" --yes collect-evidence >>"$log" 2>&1 &&
        normalize_gerrit_role_evidence_logs "$log"; then
        rc=0
      else
        rc=$?
      fi
      ;;
    jenkins-controller)
      if compose_exec_with_ldap_password "$service" "$helper_path" --env "$role_env_file" validate >>"$log" 2>&1 &&
        compose_exec_with_ldap_password "$service" "$helper_path" --env "$role_env_file" collect-evidence >>"$log" 2>&1 &&
        __docker_roles_validate_jenkins_controller_authorization "$service" "$log" &&
        normalize_jenkins_controller_role_evidence_logs "$log"; then
        rc=0
      else
        rc=$?
      fi
      ;;
    jenkins-agent)
      if compose exec -T -u ci-operator "$service" "$helper_path" --env "$role_env_file" validate >>"$log" 2>&1 &&
        compose exec -T -u ci-operator "$service" "$helper_path" --env "$role_env_file" collect-evidence >>"$log" 2>&1 &&
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
