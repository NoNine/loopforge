#!/usr/bin/env bash

docker_set_create() {
  local log rc evidence
  bootstrap_harness_env
  docker_set_require_runtime
  require_command docker
  detect_compose
  require_baseline_label
  [ -f "$compose_file" ] || die "Missing Compose file: $compose_file"
  [ -f "$docker_dir/ldap/50-harness-seed.ldif" ] || die "Missing LDAP seed LDIF"
  [ -f "$docker_dir/target/Dockerfile" ] || die "Missing harness target Dockerfile"
  [ -f "$docker_dir/scripts/harness-sleep.sh" ] || die "Missing harness container entrypoint"
  log="$(bounded_log_path create)"
  if compose build >"$log" 2>&1; then
    rc=0
  else
    rc=$?
  fi
  if [ "$rc" -ne 0 ]; then
    evidence="$(write_evidence create harness fail "simulate.sh create" "$log" "Compose image build failed")"
    print_command_failure create "" failed "$log" "$evidence"
    return "$rc"
  fi
  evidence="$(write_evidence create harness pass "simulate.sh create" "$log" "Built selected Docker simulation project images without starting containers")"
  print_command_summary create "" "ok images=project-built"
}

__docker_set_initialize_or_validate_product_homes() {
  local log marker pending spec service account group path
  local expected expected_uid expected_gid actual
  log="${1:?log required}"
  marker="$HARNESS_PRODUCT_HOME_DIR/.runtime-identity-pending"
  pending=0
  [ ! -f "$marker" ] || pending=1

  for spec in \
    'gerrit-target:gerrit:gerrit:/srv/gerrit:61010:61010' \
    'jenkins-controller-target:jenkins:jenkins:/var/lib/jenkins:61020:61020' \
    'jenkins-agent-target:jenkins-agent:jenkins-agent:/var/lib/jenkins-agent:61030:61030'; do
    IFS=: read -r service account group path expected_uid expected_gid <<<"$spec"
    expected="$expected_uid:$expected_gid"
    if [ "$pending" -eq 1 ]; then
      compose exec -T "$service" sh -c \
        'test -d "$1" && test -z "$(find "$1" -mindepth 1 -maxdepth 1 -print -quit)" && install -d -m 0755 -o "$2" -g "$3" "$1"' \
        sh "$path" "$account" "$group" >>"$log" 2>&1 || {
          printf 'ERROR: Fresh Docker product home initialization failed for %s:%s\n' "$service" "$path" >>"$log"
          return 1
        }
    else
      actual="$(compose exec -T "$service" stat -c '%u:%g' "$path" 2>>"$log" | tr -d '\r')" || {
        printf 'ERROR: Could not inspect Docker product home ownership for %s:%s\n' "$service" "$path" >>"$log"
        return 1
      }
      if [ "$actual" != "$expected" ]; then
        printf 'ERROR: Docker product home ownership mismatch for %s:%s expected=%s actual=%s; run explicit cleanup and use a fresh run\n' \
          "$service" "$path" "$expected" "$actual" >>"$log"
        return 1
      fi
    fi
  done

  if [ "$pending" -eq 1 ]; then
    rm -f -- "$marker"
    printf 'product-home-runtime-identities=initialized\n' >>"$log"
  else
    printf 'product-home-runtime-identities=validated\n' >>"$log"
  fi
}

docker_set_start() {
  local log rc evidence
  bootstrap_harness_env
  docker_set_require_runtime
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
  log="$(bounded_log_path start)"
  if compose up -d >"$log" 2>&1; then
    rc=0
  else
    rc=$?
    if compose_v1_recreate_bug_detected "$log"; then
      {
        printf 'compose_recovery_required=docker-compose-v1-containerconfig\n'
        printf 'recovery_instruction=run-stop-then-restore-baseline\n'
      } >>"$log"
    fi
  fi
  if [ "$rc" -ne 0 ]; then
    evidence="$(write_evidence start harness fail "simulate.sh start" "$log" "Compose startup failed")"
    print_command_failure start "" failed "$log" "$evidence"
    return "$rc"
  fi
  if ! __docker_set_initialize_or_validate_product_homes "$log"; then
    evidence="$(write_evidence start harness fail "simulate.sh start" "$log" "Docker product home runtime identity initialization or validation failed")"
    print_command_failure start "" failed "$log" "$evidence"
    return 1
  fi
  check_ubuntu_service_baseline bundle-factory bundle-factory
  check_ubuntu_service_baseline gerrit-target gerrit
  check_ubuntu_service_baseline jenkins-controller-target jenkins-controller
  check_ubuntu_service_baseline jenkins-agent-target jenkins-agent
  if ! stage_role_helpers_for_all_services "$log"; then
    evidence="$(write_evidence start harness fail "simulate.sh start" "$log" "Canonical role-helper staging failed")"
    print_command_failure start "" failed "$log" "$evidence"
    return 1
  fi
  if ! stage_target_ssh_authorized_keys "$log"; then
    evidence="$(write_evidence start harness fail "simulate.sh start" "$log" "Post-start target SSH public-key staging failed")"
    print_command_failure start "" failed "$log" "$evidence"
    return 1
  fi
  if ! refresh_target_ssh_known_hosts "$log"; then
    evidence="$(write_evidence start harness fail "simulate.sh start" "$log" "Post-start target SSH known_hosts refresh failed")"
    print_command_failure start "" failed "$log" "$evidence"
    return 1
  fi
  if ! docker_publish_or_verify_effective_inputs >>"$log" 2>&1; then
    evidence="$(write_evidence start harness fail "simulate.sh start" "$log" "Stable effective input publication or verification failed")"
    print_command_failure start "" failed "$log" "$evidence"
    return 1
  fi
  require_running_service ldap
  evidence="$(write_evidence start harness pass "simulate.sh start" "$log" "Started bundle factory, LDAP, Gerrit target, Jenkins controller target, and Jenkins agent target")"
  print_command_summary start "" "ok resources=running target-access=ready inputs=ready"
}

__docker_set_destroy_container_targets() {
  local service
  for service in "${services[@]}"; do
    docker ps -a -q \
      --filter "label=org.loopforge.resource=docker-simulation" \
      --filter "label=org.loopforge.project=$HARNESS_PROJECT_NAME" \
      --filter "label=org.loopforge.set-id=$HARNESS_SET_ID" \
      --filter "label=org.loopforge.service=$service" 2>/dev/null || true
  done | awk 'NF && !seen[$0]++'
}

__docker_set_destroy_network_targets() {
  (docker network ls -q \
    --filter "label=org.loopforge.resource=docker-simulation" \
    --filter "label=org.loopforge.project=$HARNESS_PROJECT_NAME" \
    --filter "label=org.loopforge.set-id=$HARNESS_SET_ID" \
    --filter "label=org.loopforge.network=harness" 2>/dev/null || true) |
    awk 'NF && !seen[$0]++'
}

__docker_set_destroy_image_targets() {
  local service
  for service in "${services[@]}"; do
    docker images -q \
      --filter "label=org.loopforge.resource=docker-simulation" \
      --filter "label=org.loopforge.project=$HARNESS_PROJECT_NAME" \
      --filter "label=org.loopforge.set-id=$HARNESS_SET_ID" \
      --filter "label=org.loopforge.service=$service" 2>/dev/null || true
  done | awk 'NF && !seen[$0]++'
}

docker_set_destroy() {
  local log rc evidence target container_count network_count image_count
  bootstrap_harness_env
  require_command docker
  log="$(bounded_log_path destroy)"
  rc=0
  container_count=0
  network_count=0
  image_count=0
  : >"$log"
  while IFS= read -r target; do
    [ -n "$target" ] || continue
    if docker rm -f "$target" >>"$log" 2>&1; then
      container_count=$((container_count + 1))
    else
      rc=$?
      printf 'container_remove_failed target=%s\n' "$target" >>"$log"
      break
    fi
  done <<EOF
$(__docker_set_destroy_container_targets)
EOF
  if [ "$rc" -eq 0 ]; then
    while IFS= read -r target; do
      [ -n "$target" ] || continue
      if docker network rm "$target" >>"$log" 2>&1; then
        network_count=$((network_count + 1))
      else
        rc=$?
        printf 'network_remove_failed target=%s\n' "$target" >>"$log"
        break
      fi
    done <<EOF
$(__docker_set_destroy_network_targets)
EOF
  fi
  if [ "$rc" -eq 0 ]; then
    while IFS= read -r target; do
      [ -n "$target" ] || continue
      if docker image rm "$target" >>"$log" 2>&1; then
        image_count=$((image_count + 1))
      else
        rc=$?
        printf 'image_remove_failed target=%s\n' "$target" >>"$log"
        break
      fi
    done <<EOF
$(__docker_set_destroy_image_targets)
EOF
  fi
  if [ "$rc" -ne 0 ]; then
    evidence="$(write_evidence destroy harness fail "simulate.sh destroy" "$log" "Docker selected resource destruction failed")"
    print_command_failure destroy "" failed "$log" "$evidence"
    return "$rc"
  fi
  evidence="$(write_evidence destroy harness pass "simulate.sh destroy" "$log" "Removed selected Docker simulation containers, harness network, and project-built images; base images and generated state were not removed")"
  print_command_summary destroy "" "ok containers-removed=$container_count networks-removed=$network_count images-removed=$image_count"
}

docker_set_status() {
  local gerrit_port jenkins_port
  bootstrap_harness_env
  docker_set_require_runtime
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

docker_set_audit() {
  bootstrap_harness_env
  docker_set_require_runtime
  require_command docker
  detect_compose
  docker_set_verify_selected_mounts
  print_command_summary audit-state "" "ok"
}

docker_set_stop() {
  local log rc evidence container
  bootstrap_harness_env
  require_command docker
  if docker_set_runtime_config_valid; then
    detect_compose
    log="$(bounded_log_path stop)"
    if compose down >"$log" 2>&1; then
      rc=0
    else
      rc=$?
    fi
  else
    ensure_preflight_dirs
    log="$(bounded_log_path stop)"
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
    evidence="$(write_evidence stop harness fail "simulate.sh stop" "$log" "Compose stop failed")"
    print_command_failure stop "" failed "$log" "$evidence"
    return "$rc"
  fi
  evidence="$(write_evidence stop harness pass "simulate.sh stop" "$log" "Stopped harness containers without deleting retained evidence")"
  print_command_summary stop "" "stopped harness containers"
}

__docker_set_cleanup_mutable_paths_host() {
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

__docker_set_cleanup_mutable_paths_container() {
  local log
  log="${1:?log required}"
  docker run --rm \
    --mount "type=bind,source=$HARNESS_GENERATED_RUN_DIR,target=/cleanup-root" \
    "$HARNESS_UBUNTU_IMAGE" \
    sh -c 'rm -rf -- /cleanup-root/target/helper-state /cleanup-root/target/product-homes /cleanup-root/target/artifacts/staging /cleanup-root/target/ldap /cleanup-root/target/shared-jenkins-storage /cleanup-root/host/rendered /cleanup-root/host/runtime-inputs /cleanup-root/host/target-ssh /cleanup-root/host/validation-secrets /cleanup-root/host/bundle-factory' \
    >>"$log" 2>&1
}

__docker_set_backup_and_clear_retained_outputs() {
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

__docker_set_run_root_exists_for_recovery() {
  local expected actual_real expected_real
  expected="$(canonical_generated_run_dir)"
  [ "$HARNESS_GENERATED_RUN_DIR" = "$expected" ] || return 1
  [ -d "$HARNESS_GENERATED_RUN_DIR" ] || return 1
  [ ! -L "$HARNESS_GENERATED_RUN_DIR" ] || return 1
  actual_real="$(realpath "$HARNESS_GENERATED_RUN_DIR")"
  expected_real="$(realpath "$expected")"
  [ "$actual_real" = "$expected_real" ]
}

__docker_set_verify_clean_output_dirs() {
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

docker_set_clean() {
  local log rc evidence cleanup_fallback container backup_name backup_path recovery_run_root_exists
  bootstrap_harness_env
  require_command docker
  recovery_run_root_exists=0
  if docker_set_runtime_config_valid; then
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
    if __docker_set_run_root_exists_for_recovery; then
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
      if ! __docker_set_cleanup_mutable_paths_container "$log"; then
        evidence="$(write_evidence clean harness fail "simulate.sh clean" "$log" "Generated runtime cleanup failed during recovery")"
        print_command_failure clean "" failed "$log" "$evidence"
        return 1
      fi
      backup_path="$(__docker_set_backup_and_clear_retained_outputs "$log" "$backup_name")" || rc=$?
      rc="${rc:-0}"
      if [ "$rc" -ne 0 ]; then
        evidence="$(write_evidence clean harness fail "simulate.sh clean" "$log" "Retained output backup failed during recovery")"
        print_command_failure clean "" failed "$log" "$evidence"
        return "$rc"
      fi
      __docker_set_verify_clean_output_dirs
      evidence="$(write_evidence clean harness pass "simulate.sh clean" "$log" "Removed selected containers, cleaned mutable generated runtime data, and backed up retained outputs during recovery to $backup_path")"
      print_command_summary clean "" "removed containers runtime data backup=$backup_name cleanup=$cleanup_fallback"
      return 0
    else
      evidence="$(write_evidence clean harness pass "simulate.sh clean" "$log" "Removed selected containers with bootstrap recovery; host generated cleanup skipped because runtime config is invalid or missing")"
      print_command_summary clean "" "removed containers cleanup=skipped reason=invalid-or-missing-runtime-config"
      return 0
    fi
  fi

  if ! __docker_set_cleanup_mutable_paths_host >>"$log" 2>&1; then
    cleanup_fallback=container
    __docker_set_cleanup_mutable_paths_container "$log" || rc=$?
    rc="${rc:-0}"
    if [ "$rc" -ne 0 ]; then
      evidence="$(write_evidence clean harness fail "simulate.sh clean" "$log" "Generated runtime cleanup failed")"
      print_command_failure clean "" failed "$log" "$evidence"
      return "$rc"
    fi
  fi
  backup_name="clean-$(timestamp_utc)"
  backup_path="$(__docker_set_backup_and_clear_retained_outputs "$log" "$backup_name")" || rc=$?
  rc="${rc:-0}"
  if [ "$rc" -ne 0 ]; then
    evidence="$(write_evidence clean harness fail "simulate.sh clean" "$log" "Retained output backup failed")"
    print_command_failure clean "" failed "$log" "$evidence"
    return "$rc"
  fi
  ensure_preflight_dirs
  __docker_set_verify_clean_output_dirs
  evidence="$(write_evidence clean harness pass "simulate.sh clean" "$log" "Removed mutable generated runtime data and backed up retained outputs to $backup_path")"
  print_command_summary clean "" "removed runtime data backup=$backup_name cleanup=$cleanup_fallback"
}

docker_set_require_runtime() {
  if [ -n "$HARNESS_RENDERED_ENV_OPERATOR_SET" ] && docker_config_load_runtime_if_present; then
    verify_run_marker
    validate_core_generated_state
    return 0
  fi
  if docker_config_load_runtime_if_present; then
    verify_run_marker
    validate_core_generated_state
    return 0
  fi
  if selected_containers_exist; then
    die "Docker generated state is missing while selected containers exist; use stop and explicit recovery before resuming"
  fi
  die "Missing Docker harness runtime config: run init-run first"
}

docker_set_runtime_config_valid() {
  (
    docker_config_load_runtime_if_present &&
    verify_run_marker >/dev/null 2>&1 &&
    validate_core_generated_state >/dev/null 2>&1
  ) >/dev/null 2>&1
}

docker_set_verify_selected_mounts() {
  validate_selected_container_mounts
}
