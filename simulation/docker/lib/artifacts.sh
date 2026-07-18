#!/usr/bin/env bash

owned_directory_command() {
  local owner group mode path recursive
  owner="${1:?owner required}"
  group="${2:?group required}"
  mode="${3:?mode required}"
  path="${4:?path required}"
  recursive="${5:-0}"

  printf 'install -d -m %s -o %s -g %s %s' \
    "$(shell_quote "$mode")" \
    "$(shell_quote "$owner")" \
    "$(shell_quote "$group")" \
    "$(shell_quote "$path")"
  if [ "$recursive" = "1" ]; then
    printf ' && chown -R %s %s' \
      "$(shell_quote "$owner:$group")" \
      "$(shell_quote "$path")"
  fi
}
copy_bundle_factory_artifacts_to_host() {
  local role service log container_dir container_archive container_checksum container_id
  local archive checksum payload
  role="${1:?role required}"
  service="${2:?service required}"
  log="${3:?log required}"
  container_dir="$(container_bundle_factory_work_dir_for_role "$role")"
  container_archive="$(container_prepared_artifact_archive_for_role "$role")"
  container_checksum="$(container_prepared_artifact_checksum_for_role "$role")"
  archive="$(exported_artifact_archive_for_role "$role")"
  checksum="$(exported_artifact_checksum_for_role "$role")"
  payload="$(bundle_payload_dir_for_role "$role")"
  if ! compose exec -T "$service" sh -c \
    "test -f $(shell_quote "$container_dir/manifest.txt") && test -f $(shell_quote "$container_dir/checksums.sha256") && cd $(shell_quote "$container_dir") && sha256sum -c checksums.sha256 && cd /var/lib/loopforge/preparing && sha256sum -c $(shell_quote "$(basename "$container_checksum")")" \
    >>"$log" 2>&1; then
    return 1
  fi
  container_id="$(container_id_for_service "$service")"
  [ -n "$container_id" ] || die "Harness service '$service' is not created; run start first"
  rm -f "$archive" "$checksum"
  mkdir -p "$HARNESS_EXPORTED_ARTIFACT_DIR"
  if ! docker cp "$container_id:$container_archive" "$archive" >>"$log" 2>&1; then
    return 1
  fi
  if ! docker cp "$container_id:$container_checksum" "$checksum" >>"$log" 2>&1; then
    return 1
  fi
  if ! verify_checksum_file_in_dir "$checksum" "$HARNESS_EXPORTED_ARTIFACT_DIR" "$log"; then
    return 1
  fi
  tar -xOf "$archive" "$payload/manifest.txt" >"$HARNESS_EXPORTED_ARTIFACT_DIR/.manifest-$role.tmp"
  if ! validate_role_baseline_manifest "$role" "$HARNESS_EXPORTED_ARTIFACT_DIR/.manifest-$role.tmp" "$log"; then
    rm -f "$HARNESS_EXPORTED_ARTIFACT_DIR/.manifest-$role.tmp"
    return 1
  fi
  rm -f "$HARNESS_EXPORTED_ARTIFACT_DIR/.manifest-$role.tmp"
  printf 'bundle_factory_artifact_export role=%s service=%s source=%s destination=%s transfer_mode=docker-cp-collector scope=docker-simulation-only\n' \
    "$role" "$service" "$container_archive" "$archive" >>"$log"
  printf '%s\n' "$container_dir"
}

docker_cp_file_to_service() {
  local host_file service container_path owner group mode log container_id tmp_path dest_dir command
  host_file="${1:?host file required}"
  service="${2:?service required}"
  container_path="${3:?container path required}"
  owner="${4:?owner required}"
  group="${5:?group required}"
  mode="${6:?mode required}"
  log="${7:?log required}"
  require_readable_file "Docker cp source file" "$host_file"
  container_id="$(container_id_for_service "$service")"
  [ -n "$container_id" ] || die "Harness service '$service' is not created; run start first"
  tmp_path="/tmp/loopforge-docker-cp-$$-$(basename "$container_path")"
  dest_dir="$(dirname "$container_path")"
  if ! docker cp "$host_file" "$container_id:$tmp_path" >>"$log" 2>&1; then
    return 1
  fi
  command="test -d $(shell_quote "$dest_dir")"
  command="$command && mv $(shell_quote "$tmp_path") $(shell_quote "$container_path") && chown $(shell_quote "$owner:$group") $(shell_quote "$container_path") && chmod $(shell_quote "$mode") $(shell_quote "$container_path")"
  compose exec -T -u root "$service" sh -c "$command" >>"$log" 2>&1 || return $?
  printf 'transfer_mode=docker-cp-waiver source=%s service=%s destination=%s owner=%s group=%s mode=%s scope=docker-simulation-only\n' \
    "$host_file" "$service" "$container_path" "$owner" "$group" "$mode" >>"$log"
}

stage_operator_input_file() {
  local service host_file container_path owner group mode log container_id tmp_path dest_dir command
  service="${1:?service required}"
  host_file="${2:?host file required}"
  container_path="${3:?container path required}"
  owner="${4:?owner required}"
  group="${5:?group required}"
  mode="${6:?mode required}"
  log="${7:?log required}"
  require_readable_file "Docker cp operator input source file" "$host_file"
  container_id="$(container_id_for_service "$service")"
  [ -n "$container_id" ] || die "Harness service '$service' is not created; run start first"
  tmp_path="/tmp/loopforge-input-cp-$$-$(basename "$container_path")"
  dest_dir="$(dirname "$container_path")"
  if ! docker cp "$host_file" "$container_id:$tmp_path" >>"$log" 2>&1; then
    return 1
  fi
  command="$(owned_directory_command "$owner" "$group" 0700 "$dest_dir" 0)"
  command="$command && mv $(shell_quote "$tmp_path") $(shell_quote "$container_path") && chown $(shell_quote "$owner:$group") $(shell_quote "$container_path") && chmod $(shell_quote "$mode") $(shell_quote "$container_path")"
  compose exec -T -u root "$service" sh -c "$command" >>"$log" 2>&1
  printf 'transfer_mode=docker-cp-input-waiver source=%s service=%s destination=%s owner=%s group=%s mode=%s custody=operator-input scope=docker-simulation-only\n' \
    "$host_file" "$service" "$container_path" "$owner" "$group" "$mode" >>"$log"
}

docker_cp_file_from_service() {
  local service container_path host_file log container_id
  service="${1:?service required}"
  container_path="${2:?container path required}"
  host_file="${3:?host file required}"
  log="${4:?log required}"
  container_id="$(container_id_for_service "$service")"
  [ -n "$container_id" ] || die "Harness service '$service' is not created; run start first"
  mkdir -p "$(dirname "$host_file")"
  if ! docker cp "$container_id:$container_path" "$host_file" >>"$log" 2>&1; then
    return 1
  fi
  chmod u+rw,go-rwx "$host_file" 2>/dev/null || true
  printf 'transfer_mode=docker-cp-collector service=%s source=%s destination=%s scope=docker-simulation-only\n' \
    "$service" "$container_path" "$host_file" >>"$log"
}

stage_operator_env_file() {
  local service host_env_file container_env_file owner group log
  service="${1:?service required}"
  host_env_file="${2:?host env file required}"
  container_env_file="${3:?container env file required}"
  owner="${4:?owner required}"
  group="${5:?group required}"
  log="${6:?log required}"
  stage_operator_input_file "$service" "$host_env_file" "$container_env_file" "$owner" "$group" 0600 "$log"
  printf '%s\n' "$container_env_file"
}

stage_role_helpers_for_service() {
  local service log root tmp command
  service="${1:?service required}"
  log="${2:?log required}"
  root="$(role_helpers_root_for_operator ci-operator)"
  tmp="$root.loopforge-tmp-$$"
  command="rm -rf -- $(shell_quote "$tmp")"
  command="$command && install -d -m $LF_MODE_PUBLIC_DIR -o ci-operator -g ci-operator $(shell_quote "$tmp/scripts") $(shell_quote "$tmp/templates/gerrit") $(shell_quote "$tmp/templates/jenkins-controller") $(shell_quote "$tmp/templates/jenkins-agent")"
  command="$command && install -m $LF_MODE_PUBLIC_FILE -o ci-operator -g ci-operator /workspace/scripts/common.sh $(shell_quote "$tmp/scripts/common.sh")"
  command="$command && install -m $LF_MODE_EXECUTABLE_FILE -o ci-operator -g ci-operator /workspace/scripts/gerrit-setup.sh /workspace/scripts/jenkins-controller-setup.sh /workspace/scripts/jenkins-agent-setup.sh $(shell_quote "$tmp/scripts")"
  command="$command && cp -R /workspace/templates/gerrit/. $(shell_quote "$tmp/templates/gerrit/")"
  command="$command && cp -R /workspace/templates/jenkins-controller/. $(shell_quote "$tmp/templates/jenkins-controller/")"
  command="$command && cp -R /workspace/templates/jenkins-agent/. $(shell_quote "$tmp/templates/jenkins-agent/")"
  command="$command && chown -R ci-operator:ci-operator $(shell_quote "$tmp")"
  command="$command && find $(shell_quote "$tmp") -type d -exec chmod $LF_MODE_PUBLIC_DIR {} +"
  command="$command && find $(shell_quote "$tmp") -type f -exec chmod $LF_MODE_PUBLIC_FILE {} +"
  command="$command && chmod $LF_MODE_EXECUTABLE_FILE $(shell_quote "$tmp/scripts/gerrit-setup.sh") $(shell_quote "$tmp/scripts/jenkins-controller-setup.sh") $(shell_quote "$tmp/scripts/jenkins-agent-setup.sh")"
  command="$command && rm -rf -- $(shell_quote "$root") && mv -- $(shell_quote "$tmp") $(shell_quote "$root")"
  command="$command && test -x $(shell_quote "$root/scripts/gerrit-setup.sh") && test -x $(shell_quote "$root/scripts/jenkins-controller-setup.sh") && test -x $(shell_quote "$root/scripts/jenkins-agent-setup.sh")"
  compose exec -T -u root "$service" sh -c "$command" >>"$log" 2>&1
  printf 'role_helpers=ready service=%s path=%s owner=ci-operator mode=operator-writable source=/workspace scope=docker-simulation-only\n' \
    "$service" "$root" >>"$log"
}

stage_role_helpers_for_all_services() {
  local service log
  log="${1:?log required}"
  for service in bundle-factory gerrit-target jenkins-controller-target jenkins-agent-target; do
    stage_role_helpers_for_service "$service" "$log" || return $?
  done
}

require_gerrit_bundle_factory_env() {
  require_readable_file \
    "Rendered Gerrit bundle factory env file; run init-run first" \
    "$(host_gerrit_bundle_factory_env_file)"
  gerrit_bundle_factory_env_file
}

require_jenkins_controller_bundle_factory_env() {
  require_readable_file \
    "Rendered Jenkins controller bundle factory env file; run init-run first" \
    "$(host_jenkins_controller_bundle_factory_env_file)"
  jenkins_controller_bundle_factory_env_file
}
require_staged_artifacts_in_target() {
  local role service log payload manifest checksums script
  role="${1:?role required}"
  service="${2:?service required}"
  log="${3:?log required}"
  payload="$(target_payload_dir_for_role "$role")"
  manifest="$payload/manifest.txt"
  checksums="$payload/checksums.sha256"
  script='
payload="$1"
manifest="$2"
checksums="$3"
test -d "$payload" || {
  printf "missing_staged_artifacts payload=%s\n" "$payload"
  exit 1
}
test -f "$manifest" || {
  printf "missing_staged_artifacts manifest=%s\n" "$manifest"
  exit 1
}
test -f "$checksums" || {
  printf "missing_staged_artifacts checksums=%s\n" "$checksums"
  exit 1
}
cd "$payload"
sha256sum -c checksums.sha256
'
  if ! compose exec -T "$service" sh -c "$script" sh "$payload" "$manifest" "$checksums" >>"$log" 2>&1; then
    return 1
  fi
  printf 'staged_artifacts_ready role=%s service=%s payload=%s\n' "$role" "$service" "$payload" >>"$log"
}
docker_artifacts_prepare() {
  local role helper_path service log rc evidence artifact_dir host_env_file role_env_file export_archive
  bootstrap_harness_env
  docker_set_require_runtime || return $?
  require_docker_effective_inputs
  role="${1:?role required}"
  helper_path="$(role_helper_path_for_operator ci-operator "$role")"
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
  require_running_service "$(docker_compose_service_for_role "$role")"
  if compose exec -T "$(docker_compose_service_for_role "$role")" env | grep -q '^HARNESS_ENVIRONMENT=bundle-factory$'; then
    die "Refusing prepare-artifacts: selected target container is incorrectly marked as bundle factory"
  fi

  log="$(bounded_log_path "prepare-artifacts-$role")"
  if ! docker_compose_role_helper_present "$service" "$helper_path"; then
    evidence="$(write_evidence prepare-artifacts "$role" blocked "simulate.sh prepare-artifacts" "$log" "Missing executable role helper $helper_path in bundle factory")"
    printf 'ERROR: Missing role helper for %s in bundle factory: %s\n' "$role" "$helper_path" >"$log"
    print_command_failure prepare-artifacts "$role" failed "$log" "$evidence" >&2
    return 1
  fi

  : >"$log"
  role_env_file="$(stage_operator_env_file "$service" "$host_env_file" "$role_env_file" ci-operator ci-operator "$log")"

  if [ "$role" = "gerrit" ]; then
    if compose exec -T -u ci-operator "$service" "$helper_path" --env "$role_env_file" --yes prepare-artifacts >>"$log" 2>&1; then
      rc=0
    else
      rc=$?
    fi
  elif [ "$role" = "jenkins-controller" ]; then
    if compose exec -T -u ci-operator "$service" "$helper_path" --env "$role_env_file" --yes prepare-artifacts >>"$log" 2>&1; then
      rc=0
    else
      rc=$?
    fi
  elif [ "$role" = "jenkins-agent" ]; then
    if compose exec -T -u ci-operator "$service" "$helper_path" --env "$role_env_file" prepare-artifacts >>"$log" 2>&1; then
      rc=0
    else
      rc=$?
    fi
  elif compose exec -T -u ci-operator "$service" "$helper_path" prepare-artifacts >>"$log" 2>&1; then
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

__docker_artifacts_prepare_target_workspace() {
  local role service helper_path log role_env_file
  role="${1:?role required}"
  service="${2:?service required}"
  helper_path="$(role_helper_path_for_operator ci-operator "$role")"
  log="${3:?log required}"
  role_env_file="$(stage_container_role_env "$role" "$service" "$log")"
  compose exec -T -u ci-operator "$service" "$helper_path" --env "$role_env_file" --yes prepare-target-workspace >>"$log" 2>&1
}

docker_artifacts_stage() {
  local role service archive checksum target_bundle_dir target_payload_dir log evidence
  local staging_root archive_name checksum_name container_archive container_checksum extract_script
  bootstrap_harness_env
  docker_set_require_runtime || return $?
  require_docker_effective_inputs
  role="${1:?role required}"
  service="$(docker_compose_service_for_role "$role")"
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

  if ! __docker_artifacts_prepare_target_workspace "$role" "$service" "$log"; then
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
