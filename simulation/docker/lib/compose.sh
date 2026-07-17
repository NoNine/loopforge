#!/usr/bin/env bash

detect_compose() {
  validate_harness_inputs
  if [ "${HARNESS_FORCE_COMPOSE_V1_FOR_TESTS:-0}" = "1" ]; then
    command -v docker-compose >/dev/null 2>&1 ||
      die "Docker Compose v1 test hook requested but docker-compose is missing"
    compose_kind="docker-compose v1"
    compose_cmd=(docker-compose)
    return 0
  fi

  if docker compose version >/dev/null 2>&1; then
    compose_kind="docker compose v2"
    compose_cmd=(docker compose)
    return 0
  fi

  if command -v docker-compose >/dev/null 2>&1; then
    compose_kind="docker-compose v1"
    compose_cmd=(docker-compose)
    return 0
  fi

  die "Docker Compose is required: install Docker Compose v2 or docker-compose v1"
}

compose() {
  if [ "${#compose_cmd[@]}" -eq 0 ]; then
    detect_compose
  fi
  "${compose_cmd[@]}" --project-name "$HARNESS_PROJECT_NAME" --file "$compose_file" "$@"
}

compose_exec_with_ldap_password() {
  local service
  service="${1:?service required}"
  shift
  [ -n "${HARNESS_LDAP_BIND_PASSWORD:-}" ] ||
    die "Missing HARNESS_LDAP_BIND_PASSWORD for execution-time LDAP bind secret injection"
  LDAP_BIND_PASSWORD="$HARNESS_LDAP_BIND_PASSWORD" compose exec -T -u ci-operator -e LDAP_BIND_PASSWORD "$service" "$@"
}

compose_v1_recreate_bug_detected() {
  local log
  log="${1:?log required}"
  [ "$compose_kind" = "docker-compose v1" ] || return 1
  grep -Eq "KeyError: 'ContainerConfig'|ERROR: .*'ContainerConfig'" "$log"
}

container_running_by_name() {
  local name running
  name="${1:?container name required}"
  running="$(docker inspect -f '{{.State.Running}}' "$name" 2>/dev/null || true)"
  [ "$running" = "true" ]
}

container_mount_source_for_destination() {
  local name destination
  name="${1:?container name required}"
  destination="${2:?destination required}"
  docker inspect -f '{{range .Mounts}}{{printf "%s\t%s\n" .Source .Destination}}{{end}}' "$name" 2>/dev/null |
    awk -F '\t' -v destination="$destination" '$2 == destination { print $1; found = 1; exit } END { exit !found }'
}

require_mount_source_under_run_root() {
  local service container destination expected source expected_real source_real
  service="${1:?service required}"
  destination="${2:?destination required}"
  expected="${3:?expected source required}"
  container="$(container_name_for_service "$service")"
  docker_container_name_exists "$container" || return 0
  source="$(container_mount_source_for_destination "$container" "$destination" || true)"
  [ -n "$source" ] ||
    die "Inconsistent Docker container state: $container is missing mount destination $destination; use stop and explicit recovery before resuming"
  [ -e "$source" ] ||
    die "Stale Docker bind mount for $container:$destination: host source is missing ($source); use stop and explicit recovery before resuming"
  [ -e "$expected" ] ||
    die "Inconsistent Docker generated state: expected bind source is missing: $expected"
  source_real="$(realpath "$source")"
  expected_real="$(realpath "$expected")"
  [ "$source_real" = "$expected_real" ] ||
    die "Stale Docker bind mount for $container:$destination: source $source is not selected run path $expected; use stop and explicit recovery before resuming"
  case "$source_real" in
    "$HARNESS_GENERATED_RUN_DIR"|"$HARNESS_GENERATED_RUN_DIR"/*) ;;
    *)
      die "Stale Docker bind mount for $container:$destination: source is outside selected run root; use stop and explicit recovery before resuming"
      ;;
  esac
}

require_mount_source_matches() {
  local service container destination expected source expected_real source_real
  service="${1:?service required}"
  destination="${2:?destination required}"
  expected="${3:?expected source required}"
  container="$(container_name_for_service "$service")"
  docker_container_name_exists "$container" || return 0
  source="$(container_mount_source_for_destination "$container" "$destination" || true)"
  [ -n "$source" ] ||
    die "Inconsistent Docker container state: $container is missing mount destination $destination; use stop and explicit recovery before resuming"
  [ -e "$source" ] ||
    die "Stale Docker bind mount for $container:$destination: host source is missing ($source); use stop and explicit recovery before resuming"
  [ -e "$expected" ] ||
    die "Inconsistent Docker generated state: expected bind source is missing: $expected"
  source_real="$(realpath "$source")"
  expected_real="$(realpath "$expected")"
  [ "$source_real" = "$expected_real" ] ||
    die "Stale Docker bind mount for $container:$destination: source $source is not expected path $expected; use stop and explicit recovery before resuming"
}

mount_identity() {
  local path
  path="${1:?path required}"
  stat -Lc '%d:%i' "$path"
}

require_mount_identity_visible() {
  local service container host_dir destination host_identity container_identity
  service="${1:?service required}"
  host_dir="${2:?host dir required}"
  destination="${3:?destination required}"
  container="$(container_name_for_service "$service")"
  docker_container_name_exists "$container" || return 0
  container_running_by_name "$container" || return 0
  host_identity="$(mount_identity "$host_dir")"
  container_identity="$(compose exec -T "$service" stat -Lc '%d:%i' "$destination" 2>/dev/null || true)"
  if [ -z "$container_identity" ]; then
    die "Stale Docker bind mount for $container:$destination: destination is not visible in the container; use stop and explicit recovery before resuming"
  fi
  [ "$container_identity" = "$host_identity" ] ||
    die "Stale Docker bind mount for $container:$destination: host and container mount identity differ; use stop and explicit recovery before resuming"
}

validate_container_mount() {
  local service host_dir destination scope
  service="${1:?service required}"
  host_dir="${2:?host dir required}"
  destination="${3:?destination required}"
  scope="${4:-generated}"
  if [ "$scope" = "generated" ]; then
    require_mount_source_under_run_root "$service" "$destination" "$host_dir"
  else
    require_mount_source_matches "$service" "$destination" "$host_dir"
  fi
  require_mount_identity_visible "$service" "$host_dir" "$destination"
}

validate_selected_container_mounts() {
  selected_containers_exist || return 0
  require_command docker
  detect_compose
  validate_container_mount bundle-factory "$repo_root" /workspace repo
  validate_container_mount ldap "$HARNESS_LDAP_DATA_DIR" /var/lib/ldap
  validate_container_mount ldap "$HARNESS_LDAP_CONFIG_DIR" /etc/ldap/slapd.d
  validate_container_mount gerrit-target "$repo_root" /workspace repo
  validate_container_mount gerrit-target "$HARNESS_PRODUCT_HOME_DIR/gerrit" /srv/gerrit
  validate_container_mount jenkins-controller-target "$repo_root" /workspace repo
  validate_container_mount jenkins-controller-target "$HARNESS_PRODUCT_HOME_DIR/jenkins-controller" /var/lib/jenkins
  validate_container_mount jenkins-controller-target "$HARNESS_SHARED_JENKINS_STORAGE_DIR" "$HARNESS_JENKINS_SHARED_STORAGE_PATH"
  validate_container_mount jenkins-agent-target "$repo_root" /workspace repo
  validate_container_mount jenkins-agent-target "$HARNESS_PRODUCT_HOME_DIR/jenkins-agent" /var/lib/jenkins-agent
  validate_container_mount jenkins-agent-target "$HARNESS_SHARED_JENKINS_STORAGE_DIR" "$HARNESS_JENKINS_SHARED_STORAGE_PATH"
}
container_id_for_service() {
  local service
  service="${1:?service required}"
  compose ps -q "$service"
}

require_running_service() {
  local service container_id running
  service="${1:?service required}"
  container_id="$(container_id_for_service "$service")"
  [ -n "$container_id" ] || die "Harness service '$service' is not created; run start first"
  running="$(docker inspect -f '{{.State.Running}}' "$container_id" 2>/dev/null || true)"
  [ "$running" = "true" ] || die "Harness service '$service' is not running; run start first"
}

running_loopback_port_for_service_port() {
  local service container_port container_id port
  service="${1:?service required}"
  container_port="${2:?container port required}"
  container_id="$(container_id_for_service "$service")"
  [ -n "$container_id" ] || die "Harness service '$service' is not created; run start first"
  port="$(docker inspect -f "{{with index .NetworkSettings.Ports \"$container_port\"}}{{range .}}{{if eq .HostIp \"127.0.0.1\"}}{{.HostPort}}{{\"\\n\"}}{{end}}{{end}}{{end}}" "$container_id" 2>/dev/null | sed -n '1p')"
  [ -n "$port" ] || die "Harness service '$service' has no published loopback port for $container_port"
  printf '%s\n' "$port"
}
