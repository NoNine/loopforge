#!/usr/bin/env bash

__docker_baseline_archive_specs() {
  printf '%s\t%s\t%s\t%s\n' \
    ldap_data ldap /var/lib/ldap "$HARNESS_LDAP_DATA_DIR" \
    ldap_config ldap /etc/ldap/slapd.d "$HARNESS_LDAP_CONFIG_DIR" \
    gerrit_home gerrit-target /srv/gerrit "$HARNESS_PRODUCT_HOME_DIR/gerrit" \
    jenkins_controller_home jenkins-controller-target /var/lib/jenkins "$HARNESS_PRODUCT_HOME_DIR/jenkins-controller" \
    jenkins_agent_home jenkins-agent-target /var/lib/jenkins-agent "$HARNESS_PRODUCT_HOME_DIR/jenkins-agent" \
    shared_jenkins_storage jenkins-agent-target "$HARNESS_JENKINS_SHARED_STORAGE_PATH" "$HARNESS_SHARED_JENKINS_STORAGE_DIR"
}

__docker_baseline_service_key() {
  printf '%s\n' "${1//-/_}"
}

__docker_baseline_manifest_keys() {
  local key service service_key
  printf '%s\n' schema_version backend set_id resource_namespace \
    implementation_revision compose_fingerprint network_id \
    ssh_identities_sha256
  for service in "${services[@]}"; do
    service_key="$(__docker_baseline_service_key "$service")"
    printf 'image_%s\nstorage_driver_%s\n' "$service_key" "$service_key"
  done
  while IFS=$'\t' read -r key _; do
    printf 'archive_%s_file\narchive_%s_sha256\narchive_%s_root_metadata\n' \
      "$key" "$key" "$key"
  done <<EOF
$(__docker_baseline_archive_specs)
EOF
}

__docker_baseline_manifest_is_strict() {
  local -a keys
  mapfile -t keys < <(__docker_baseline_manifest_keys)
  strict_record_keys "${1:?Docker baseline manifest required}" "${keys[@]}"
}

__docker_baseline_implementation_revision() {
  local file
  for file in \
    "$compose_file" \
    "$docker_dir/target/Dockerfile" \
    "$docker_dir/ldap/Dockerfile" \
    "$repo_root/simulation/lib/state.sh" \
    "$docker_dir/lib/paths.sh" \
    "$docker_dir/lib/config.sh" \
    "$docker_dir/lib/compose.sh" \
    "$docker_dir/lib/docker-set.sh" \
    "$docker_dir/lib/baseline.sh" \
    "$docker_dir/lib/lifecycle.sh"; do
    printf '%s  %s\n' "$(sha256_file "$file")" "${file#"$repo_root/"}"
  done | sha256sum | awk '{print $1}'
}

__docker_baseline_require_clean_bind_state() {
  local key service container_path host_path found
  while IFS=$'\t' read -r key service container_path host_path; do
    [ -d "$host_path" ] || die "Docker baseline bind source is missing: $host_path"
    case "$key" in
      gerrit_home|jenkins_controller_home|jenkins_agent_home|shared_jenkins_storage)
        found="$(find "$host_path" -mindepth 1 -print -quit)" ||
          die "Could not inspect Docker baseline bind source: $host_path"
        [ -z "$found" ] ||
          die "Docker baseline requires empty pre-setup bind state: $host_path"
        ;;
    esac
  done <<EOF
$(__docker_baseline_archive_specs)
EOF
}

__docker_baseline_archive_is_safe() {
  local archive list member rc
  archive="${1:?baseline archive required}"
  list="$(mktemp)"
  if ! tar -tf "$archive" >"$list"; then
    rm -f -- "$list"
    return 1
  fi
  rc=0
  while IFS= read -r member; do
    case "$member" in
      /*|../*|*/../*|*/..) rc=1; break ;;
    esac
    case "/$member/" in
      */.ssh/*|*/authorized_keys/*|*/secure.config/*|*/credentials.xml/*|*/secrets/*|*/integration-ops/*|*/evidence/*|*/logs/*|*/proof/*)
        rc=1
        break
        ;;
    esac
  done <"$list"
  rm -f -- "$list"
  return "$rc"
}

__docker_baseline_archive_excludes_secrets() {
  local archive key content secret rc
  archive="${1:?baseline archive required}"
  key="${2:?baseline archive key required}"
  case "$key" in
    ldap_data|ldap_config)
      # Clean LDAP data necessarily retains the documented simulation-only
      # fake credential state needed to restore the directory service.
      return 0
      ;;
  esac
  content="$(mktemp)"
  if ! tar -xOf "$archive" >"$content" 2>/dev/null; then
    rm -f -- "$content"
    return 1
  fi
  rc=0
  for secret in \
    "${HARNESS_LDAP_ADMIN_PASSWORD:-}" \
    "${HARNESS_LDAP_CONFIG_PASSWORD:-}" \
    "${HARNESS_LDAP_BIND_PASSWORD:-}"; do
    [ -n "$secret" ] || continue
    if grep -aFq -- "$secret" "$content"; then
      rc=1
      break
    fi
  done
  rm -f -- "$content"
  return "$rc"
}

__docker_baseline_capture_archive() {
  local key service container_path host_path archive tmp
  key="${1:?archive key required}"
  service="${2:?service required}"
  container_path="${3:?container path required}"
  host_path="${4:?host path required}"
  archive="$HARNESS_BASELINE_ARCHIVE_DIR/$key.tar"
  tmp="$archive.tmp"
  rm -f -- "$tmp"
  docker cp "$(container_name_for_service "$service"):$container_path/." - >"$tmp" || {
    rm -f -- "$tmp"
    return 1
  }
  [ -s "$tmp" ] || {
    rm -f -- "$tmp"
    die "Docker baseline archive is empty: $key"
  }
  __docker_baseline_archive_is_safe "$tmp" || {
    rm -f -- "$tmp"
    die "Docker baseline archive contains prohibited or unsafe paths: $key"
  }
  __docker_baseline_archive_excludes_secrets "$tmp" "$key" || {
    rm -f -- "$tmp"
    die "Docker baseline archive contains an execution-time credential: $key"
  }
  chmod "$LF_MODE_PUBLIC_FILE" "$tmp"
  mv -- "$tmp" "$archive"
  printf 'baseline-archive=%s source=%s:%s sha256=%s root=%s\n' \
    "$key" "$service" "$container_path" "$(sha256_file "$archive")" \
    "$(stat -Lc '%u:%g:%a' "$host_path")"
}

__docker_baseline_capture_ssh_identities_to() {
  local output service key_type public_key fingerprint
  output="${1:?SSH identity output required}"
  : >"$output"
  for service in gerrit-target jenkins-controller-target jenkins-agent-target; do
    for key_type in ed25519 ecdsa rsa; do
      public_key="${output}.${service}.${key_type}.pub"
      docker cp \
        "$(container_name_for_service "$service"):/etc/ssh/ssh_host_${key_type}_key.pub" \
        "$public_key" >/dev/null || return $?
      fingerprint="$(ssh-keygen -lf "$public_key" -E sha256 | awk '{print $2}')" || return $?
      printf '%s\n' "$fingerprint" | grep -Eq '^SHA256:[A-Za-z0-9+/]{43}$' ||
        die "Docker target SSH fingerprint is malformed: $service $key_type"
      printf 'service=%s key_type=%s fingerprint=%s\n' \
        "$service" "$key_type" "$fingerprint" >>"$output"
      rm -f -- "$public_key"
    done
  done
  chmod "$LF_MODE_PUBLIC_FILE" "$output"
}

__docker_baseline_write_manifest() {
  local key service service_key container_path host_path archive metadata
  local -a fields
  fields=(
    schema_version=1
    backend=docker
    "set_id=$HARNESS_SET_ID"
    "resource_namespace=$HARNESS_PROJECT_NAME"
    "implementation_revision=$(__docker_baseline_implementation_revision)"
    "compose_fingerprint=$(compose_definition_fingerprint)"
    "network_id=$(docker_network_inspect_value "$(docker_network_name)" '{{.Id}}')"
    "ssh_identities_sha256=$(sha256_file "$HARNESS_BASELINE_SSH_IDENTITIES")"
  )
  for service in "${services[@]}"; do
    service_key="$(__docker_baseline_service_key "$service")"
    fields+=(
      "image_$service_key=$(docker_container_image_id_by_name "$(container_name_for_service "$service")")"
      "storage_driver_$service_key=$(docker_container_storage_driver_by_name "$(container_name_for_service "$service")")"
    )
  done
  while IFS=$'\t' read -r key service container_path host_path; do
    archive="$HARNESS_BASELINE_ARCHIVE_DIR/$key.tar"
    metadata="$(stat -Lc '%u:%g:%a' "$host_path")"
    fields+=(
      "archive_${key}_file=archives/$key.tar"
      "archive_${key}_sha256=$(sha256_file "$archive")"
      "archive_${key}_root_metadata=$metadata"
    )
  done <<EOF
$(__docker_baseline_archive_specs)
EOF
  atomic_write_record "$HARNESS_BASELINE_MANIFEST" "$LF_MODE_PUBLIC_FILE" "${fields[@]}"
}

docker_baseline_fingerprint() {
  sha256_file "$HARNESS_BASELINE_MANIFEST"
}

docker_baseline_capture() {
  local log key service container_path host_path ssh_tmp
  log="${1:?create log required}"
  require_command cmp
  require_command sha256sum
  require_command ssh-keygen
  require_command tar
  [ ! -e "$HARNESS_BASELINE_DIR" ] ||
    die "Docker baseline state already exists without an exact reusable set"
  __docker_baseline_require_clean_bind_state
  mkdir -p "$HARNESS_BASELINE_ARCHIVE_DIR"
  chmod "$LF_MODE_PUBLIC_DIR" "$HARNESS_BASELINE_DIR" "$HARNESS_BASELINE_ARCHIVE_DIR"
  while IFS=$'\t' read -r key service container_path host_path; do
    __docker_baseline_capture_archive "$key" "$service" "$container_path" "$host_path" \
      >>"$log" || return $?
  done <<EOF
$(__docker_baseline_archive_specs)
EOF
  ssh_tmp="$HARNESS_BASELINE_SSH_IDENTITIES.tmp"
  __docker_baseline_capture_ssh_identities_to "$ssh_tmp" || return $?
  mv -- "$ssh_tmp" "$HARNESS_BASELINE_SSH_IDENTITIES"
  __docker_baseline_write_manifest || return $?
  publish_lifecycle_baseline_binding \
    "$HARNESS_ACTIVE_RUN_FILE" "$HARNESS_WORKFLOW_STATE_FILE" \
    "$(docker_baseline_fingerprint)" "$HARNESS_RUN_MARKER"
  printf 'baseline-capture=complete manifest=%s fingerprint=%s\n' \
    "$HARNESS_BASELINE_MANIFEST" "$(docker_baseline_fingerprint)" >>"$log"
}

__docker_baseline_verify_manifest_identity() {
  [ "$(strict_record_value "$HARNESS_BASELINE_MANIFEST" schema_version)" = 1 ] ||
    die "Docker baseline manifest schema is unsupported"
  [ "$(strict_record_value "$HARNESS_BASELINE_MANIFEST" backend)" = docker ] ||
    die "Docker baseline manifest backend does not match"
  [ "$(strict_record_value "$HARNESS_BASELINE_MANIFEST" set_id)" = "$HARNESS_SET_ID" ] ||
    die "Docker baseline manifest set ID does not match"
  [ "$(strict_record_value "$HARNESS_BASELINE_MANIFEST" resource_namespace)" = "$HARNESS_PROJECT_NAME" ] ||
    die "Docker baseline manifest namespace does not match"
  [ "$(strict_record_value "$HARNESS_BASELINE_MANIFEST" implementation_revision)" = \
    "$(__docker_baseline_implementation_revision)" ] ||
    die "Docker baseline implementation revision drifted"
  [ "$(strict_record_value "$HARNESS_BASELINE_MANIFEST" compose_fingerprint)" = \
    "$(compose_definition_fingerprint)" ] ||
    die "Docker baseline Compose definition drifted"
}

__docker_baseline_verify_archives() {
  local key service container_path host_path archive expected
  while IFS=$'\t' read -r key service container_path host_path; do
    [ "$(strict_record_value "$HARNESS_BASELINE_MANIFEST" "archive_${key}_file")" = \
      "archives/$key.tar" ] || die "Docker baseline archive path drifted: $key"
    archive="$HARNESS_BASELINE_ARCHIVE_DIR/$key.tar"
    [ -f "$archive" ] || die "Docker baseline archive is missing: $archive"
    expected="$(strict_record_value "$HARNESS_BASELINE_MANIFEST" "archive_${key}_sha256")"
    [ "$(sha256_file "$archive")" = "$expected" ] ||
      die "Docker baseline archive checksum drifted: $key"
    printf '%s\n' "$(strict_record_value "$HARNESS_BASELINE_MANIFEST" "archive_${key}_root_metadata")" |
      grep -Eq '^[0-9]+:[0-9]+:[0-7]{3,4}$' ||
      die "Docker baseline root metadata is malformed: $key"
    __docker_baseline_archive_is_safe "$archive" ||
      die "Docker baseline archive contains prohibited or unsafe paths: $key"
    __docker_baseline_archive_excludes_secrets "$archive" "$key" ||
      die "Docker baseline archive contains an execution-time credential: $key"
  done <<EOF
$(__docker_baseline_archive_specs)
EOF
  [ "$(sha256_file "$HARNESS_BASELINE_SSH_IDENTITIES")" = \
    "$(strict_record_value "$HARNESS_BASELINE_MANIFEST" ssh_identities_sha256)" ] ||
    die "Docker baseline target SSH identity record drifted"
}

__docker_baseline_verify_resource_identity() {
  local service service_key expected actual current_ssh
  expected="$(strict_record_value "$HARNESS_BASELINE_MANIFEST" network_id)"
  actual="$(docker_network_inspect_value "$(docker_network_name)" '{{.Id}}')"
  [ "$actual" = "$expected" ] || die "Docker baseline network identity drifted"
  for service in "${services[@]}"; do
    service_key="$(__docker_baseline_service_key "$service")"
    expected="$(strict_record_value "$HARNESS_BASELINE_MANIFEST" "image_$service_key")"
    actual="$(docker_container_image_id_by_name "$(container_name_for_service "$service")")"
    [ "$actual" = "$expected" ] || die "Docker baseline image identity drifted: $service"
    expected="$(strict_record_value "$HARNESS_BASELINE_MANIFEST" "storage_driver_$service_key")"
    actual="$(docker_container_storage_driver_by_name "$(container_name_for_service "$service")")"
    [ "$actual" = "$expected" ] || die "Docker baseline storage driver drifted: $service"
  done
  current_ssh="$(mktemp "$HARNESS_BASELINE_DIR/target-ssh-identities.verify.XXXXXX")"
  __docker_baseline_capture_ssh_identities_to "$current_ssh" || {
    rm -f -- "$current_ssh"
    return 1
  }
  cmp -s "$HARNESS_BASELINE_SSH_IDENTITIES" "$current_ssh" || {
    rm -f -- "$current_ssh"
    die "Docker baseline target SSH identity drifted"
  }
  rm -f -- "$current_ssh"
}

docker_baseline_verify() {
  local fingerprint
  require_command cmp
  require_command sha256sum
  require_command ssh-keygen
  require_command tar
  __docker_baseline_manifest_is_strict "$HARNESS_BASELINE_MANIFEST" ||
    die "Docker baseline manifest is missing, malformed, or has unexpected fields"
  __docker_baseline_verify_manifest_identity
  __docker_baseline_verify_archives
  fingerprint="$(docker_baseline_fingerprint)"
  if [ "$(strict_record_value "$HARNESS_ACTIVE_RUN_FILE" baseline_fingerprint)" != "$fingerprint" ] ||
    [ "$(strict_record_value "$HARNESS_WORKFLOW_STATE_FILE" baseline_fingerprint)" != "$fingerprint" ]; then
    die "Docker baseline binding does not match active-run and workflow state"
  fi
  [ "${1:-}" != resources ] || __docker_baseline_verify_resource_identity
}

__docker_baseline_restore_bind_data() {
  local image
  image="$(strict_record_value "$HARNESS_BASELINE_MANIFEST" image_gerrit_target)"
  docker run --rm --network none --read-only --user 0:0 \
    --mount "type=bind,source=$HARNESS_BASELINE_DIR,target=/baseline,readonly" \
    --mount "type=bind,source=$HARNESS_SET_RUNTIME_DIR,target=/runtime" \
    "$image" sh -c '
      set -eu
      restore_one() {
        archive="$1"
        target="$2"
        metadata="$3"
        uid=${metadata%%:*}
        rest=${metadata#*:}
        gid=${rest%%:*}
        mode=${metadata##*:}
        find "$target" -mindepth 1 -xdev -delete
        tar --numeric-owner -xpf "/baseline/$archive" -C "$target"
        chown "$uid:$gid" "$target"
        chmod "$mode" "$target"
        tar --numeric-owner --compare -f "/baseline/$archive" -C "$target"
      }
      shift
      while [ "$#" -gt 0 ]; do
        restore_one "$1" "$2" "$3"
        shift 3
      done
    ' sh \
    archives/ldap_data.tar /runtime/ldap/data "$(strict_record_value "$HARNESS_BASELINE_MANIFEST" archive_ldap_data_root_metadata)" \
    archives/ldap_config.tar /runtime/ldap/config "$(strict_record_value "$HARNESS_BASELINE_MANIFEST" archive_ldap_config_root_metadata)" \
    archives/gerrit_home.tar /runtime/product-homes/gerrit "$(strict_record_value "$HARNESS_BASELINE_MANIFEST" archive_gerrit_home_root_metadata)" \
    archives/jenkins_controller_home.tar /runtime/product-homes/jenkins-controller "$(strict_record_value "$HARNESS_BASELINE_MANIFEST" archive_jenkins_controller_home_root_metadata)" \
    archives/jenkins_agent_home.tar /runtime/product-homes/jenkins-agent "$(strict_record_value "$HARNESS_BASELINE_MANIFEST" archive_jenkins_agent_home_root_metadata)" \
    archives/shared_jenkins_storage.tar /runtime/shared-jenkins-storage "$(strict_record_value "$HARNESS_BASELINE_MANIFEST" archive_shared_jenkins_storage_root_metadata)"
}

__docker_baseline_remove_selected_containers() {
  local service name id
  for service in "${services[@]}"; do
    name="$(container_name_for_service "$service")"
    id="$(docker_container_id_by_name "$name")" || return $?
    docker rm "$id" || return $?
  done
}

docker_baseline_restore() {
  local log evidence presence power classification
  bootstrap_harness_env
  docker_set_require_runtime || return $?
  require_command docker
  require_command cmp
  require_command sha256sum
  require_command ssh-keygen
  require_command tar
  detect_compose
  __docker_set_require_normal_reset_gate
  presence="$(__docker_set_presence)"
  [ "$presence" = present ] ||
    die "Docker restore-baseline requires the complete selected retained set; resource state is $presence"
  __docker_set_require_runtime_dirs
  __docker_set_verify_record
  power="$(selected_container_power_state)"
  [ "$power" = stopped ] ||
    die "Docker restore-baseline requires the selected set to be stopped; current power state is $power"
  classification="$(__docker_set_classification)"
  case "$classification" in
    baseline|exact-bound|active-incomplete) ;;
    *) die "Docker restore-baseline blocks durable state classified as $classification" ;;
  esac
  docker_baseline_verify resources

  log="$(bounded_log_path restore-baseline)"
  : >"$log"
  if ! __docker_baseline_remove_selected_containers >>"$log" 2>&1; then
    evidence="$(write_evidence restore-baseline harness fail "simulate.sh restore-baseline" "$log" "Selected Docker container removal failed")"
    print_command_failure restore-baseline "" failed "$log" "$evidence"
    return 1
  fi
  [ "$(__docker_set_presence)" = partial ] ||
    die "Docker restore-baseline removed resources outside the selected containers"
  __docker_baseline_restore_bind_data >>"$log" 2>&1 || {
    evidence="$(write_evidence restore-baseline harness fail "simulate.sh restore-baseline" "$log" "Selected Docker bind restoration failed")"
    print_command_failure restore-baseline "" failed "$log" "$evidence"
    return 1
  }
  if ! compose up --no-start --no-build >>"$log" 2>&1; then
    evidence="$(write_evidence restore-baseline harness fail "simulate.sh restore-baseline" "$log" "Selected Docker container recreation failed")"
    print_command_failure restore-baseline "" failed "$log" "$evidence"
    return 1
  fi
  [ "$(selected_container_power_state)" = stopped ] ||
    die "Docker restore-baseline did not leave recreated containers stopped"
  docker_baseline_verify resources
  __docker_set_write_record
  __docker_set_verify_record
  evidence="$(write_evidence restore-baseline harness pass "simulate.sh restore-baseline" "$log" "Recreated only the selected containers and restored the checksummed clean bind baseline")"
  publish_lifecycle_restore_gate \
    "$HARNESS_ACTIVE_RUN_FILE" "$HARNESS_WORKFLOW_STATE_FILE" "$evidence" \
    "$HARNESS_RUN_MARKER"
  print_command_summary restore-baseline "" \
    "ok state=restored-pending-clean durable=baseline resources=stopped"
}
