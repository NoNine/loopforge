#!/usr/bin/env bash

set -euo pipefail

tool_script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
docker_dir="$(CDPATH= cd -- "$tool_script_dir/.." && pwd)"
repo_root="$(CDPATH= cd -- "$docker_dir/../.." && pwd)"
compose_file="$docker_dir/compose.yaml"
dry_run=0
known_services=(bundle-factory ldap gerrit-target jenkins-controller-target jenkins-agent-target)

usage() {
  cat <<'USAGE'
Usage:
  simulation/docker/tools/cleanup-docker-resources.sh [--dry-run]

Options:
  --dry-run  Print the resources and ordered cleanup actions without mutation.
  -h, --help Show this help.

Without --dry-run, this tool removes LoopForge Docker simulation containers,
Compose harness networks, and project-built images discoverable from
LoopForge ownership labels. It does not remove generated workspaces,
bind-mounted data, base images, artifacts, logs, or evidence.
USAGE
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --dry-run)
        dry_run=1
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        usage >&2
        die "Unknown option: $1"
        ;;
    esac
    shift
  done
}

label_value() {
  local value
  value="${1:-}"
  case "$value" in
    '<no value>'|'<nil>') value="" ;;
  esac
  printf '%s\n' "$value"
}

is_known_service() {
  local service known
  service="${1:-}"
  for known in "${known_services[@]}"; do
    [ "$service" != "$known" ] || return 0
  done
  return 1
}

source_matches_repo() {
  local config_files working_dir
  config_files="${1:-}"
  working_dir="${2:-}"
  [ -z "$config_files" ] && [ -z "$working_dir" ] && return 1
  case "$config_files" in
    *"$compose_file"*) return 0 ;;
  esac
  [ "$working_dir" = "$docker_dir" ] && return 0
  [ "$working_dir" = "$repo_root/simulation/docker" ] && return 0
  return 1
}

append_unique() {
  local -n target_array="${1:?array name required}"
  local value existing
  value="${2:-}"
  [ -n "$value" ] || return 0
  for existing in "${target_array[@]}"; do
    [ "$existing" != "$value" ] || return 0
  done
  target_array+=("$value")
}

docker_ids() {
  local kind filter output
  kind="${1:?kind required}"
  filter="${2:?filter required}"
  case "$kind" in
    container) output="$(docker ps -a -q --filter "$filter")" ;;
    network) output="$(docker network ls -q --filter "$filter")" ;;
    image) output="$(docker images -q --filter "$filter")" ;;
    *) die "Internal error: unknown Docker id kind: $kind" ;;
  esac || return $?
  printf '%s\n' "$output" | awk 'NF && !seen[$0]++'
}

inspect_container() {
  docker container inspect -f '{{.Id}}	{{.Name}}	{{with (index .Config "Labels")}}{{index . "org.loopforge.resource"}}{{end}}	{{with (index .Config "Labels")}}{{index . "org.loopforge.project"}}{{end}}	{{with (index .Config "Labels")}}{{index . "org.loopforge.run-id"}}{{end}}	{{with (index .Config "Labels")}}{{index . "org.loopforge.service"}}{{end}}	{{with (index .Config "Labels")}}{{index . "com.docker.compose.project"}}{{end}}	{{with (index .Config "Labels")}}{{index . "com.docker.compose.service"}}{{end}}	{{with (index .Config "Labels")}}{{index . "com.docker.compose.project.config_files"}}{{end}}	{{with (index .Config "Labels")}}{{index . "com.docker.compose.project.working_dir"}}{{end}}' "${1:?container required}"
}

inspect_network() {
  docker network inspect -f '{{.Id}}	{{.Name}}	{{index .Labels "org.loopforge.resource"}}	{{index .Labels "org.loopforge.project"}}	{{index .Labels "org.loopforge.run-id"}}	{{index .Labels "org.loopforge.network"}}	{{index .Labels "com.docker.compose.project"}}	{{index .Labels "com.docker.compose.network"}}	{{index .Labels "com.docker.compose.project.config_files"}}	{{index .Labels "com.docker.compose.project.working_dir"}}' "${1:?network required}"
}

inspect_image() {
  docker image inspect -f '{{.Id}}	{{with (index .Config "Labels")}}{{index . "org.loopforge.resource"}}{{end}}	{{with (index .Config "Labels")}}{{index . "org.loopforge.project"}}{{end}}	{{with (index .Config "Labels")}}{{index . "org.loopforge.run-id"}}{{end}}	{{with (index .Config "Labels")}}{{index . "org.loopforge.service"}}{{end}}	{{with (index .Config "Labels")}}{{index . "com.docker.compose.project"}}{{end}}	{{with (index .Config "Labels")}}{{index . "com.docker.compose.service"}}{{end}}	{{with (index .Config "Labels")}}{{index . "com.docker.compose.project.config_files"}}{{end}}	{{with (index .Config "Labels")}}{{index . "com.docker.compose.project.working_dir"}}{{end}}' "${1:?image required}"
}

inventory_containers_by_filter() {
  local filter ids id record container_id name loopforge_resource loopforge_project loopforge_run_id
  local loopforge_service compose_project compose_service config_files working_dir project service
  filter="${1:?filter required}"
  ids="$(docker_ids container "$filter")" || die "Unable to inventory LoopForge Docker containers"
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    record="$(inspect_container "$id")" ||
      die "Unable to inspect Docker container: $id"
    IFS=$'\t' read -r container_id name loopforge_resource loopforge_project loopforge_run_id \
      loopforge_service compose_project compose_service config_files working_dir <<<"$record"
    name="${name#/}"
    loopforge_resource="$(label_value "$loopforge_resource")"
    loopforge_project="$(label_value "$loopforge_project")"
    loopforge_service="$(label_value "$loopforge_service")"
    compose_project="$(label_value "$compose_project")"
    compose_service="$(label_value "$compose_service")"
    config_files="$(label_value "$config_files")"
    working_dir="$(label_value "$working_dir")"
    if [ "$loopforge_resource" = docker-simulation ]; then
      project="$loopforge_project"
      service="$loopforge_service"
    else
      project="$compose_project"
      service="$compose_service"
      source_matches_repo "$config_files" "$working_dir" || continue
    fi
    is_known_service "$service" || continue
    containers+=("$container_id"$'\t'"$name"$'\t'"$project"$'\t'"$service")
    append_unique projects "$project"
  done <<<"$ids"
}

inventory_containers() {
  containers=()
  inventory_containers_by_filter 'label=org.loopforge.resource=docker-simulation'
  inventory_containers_by_filter 'label=com.docker.compose.project'
}

inventory_images_by_filter() {
  local filter ids id record image_id loopforge_resource loopforge_project loopforge_run_id
  local loopforge_service compose_project compose_service config_files working_dir project service
  filter="${1:?filter required}"
  ids="$(docker_ids image "$filter")" || die "Unable to inventory LoopForge Docker images"
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    record="$(inspect_image "$id")" ||
      die "Unable to inspect Docker image: $id"
    IFS=$'\t' read -r image_id loopforge_resource loopforge_project loopforge_run_id \
      loopforge_service compose_project compose_service config_files working_dir <<<"$record"
    loopforge_resource="$(label_value "$loopforge_resource")"
    loopforge_project="$(label_value "$loopforge_project")"
    loopforge_service="$(label_value "$loopforge_service")"
    compose_project="$(label_value "$compose_project")"
    compose_service="$(label_value "$compose_service")"
    config_files="$(label_value "$config_files")"
    working_dir="$(label_value "$working_dir")"
    if [ "$loopforge_resource" = docker-simulation ]; then
      project="$loopforge_project"
      service="$loopforge_service"
    else
      project="$compose_project"
      service="$compose_service"
      source_matches_repo "$config_files" "$working_dir" || continue
    fi
    is_known_service "$service" || continue
    image_specs+=("$image_id"$'\t'"$project"$'\t'"$service")
    append_unique projects "$project"
  done <<<"$ids"
}

inventory_images_by_label() {
  inventory_images_by_filter 'label=org.loopforge.resource=docker-simulation'
  inventory_images_by_filter 'label=com.docker.compose.project'
}

inventory_networks_by_filter() {
  local filter ids id record network_id name loopforge_resource loopforge_project loopforge_run_id
  local loopforge_network compose_project compose_network config_files working_dir project network
  filter="${1:?filter required}"
  ids="$(docker_ids network "$filter")" || die "Unable to inventory LoopForge Docker networks"
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    record="$(inspect_network "$id")" ||
      die "Unable to inspect Docker network: $id"
    IFS=$'\t' read -r network_id name loopforge_resource loopforge_project loopforge_run_id \
      loopforge_network compose_project compose_network config_files working_dir <<<"$record"
    loopforge_resource="$(label_value "$loopforge_resource")"
    loopforge_project="$(label_value "$loopforge_project")"
    loopforge_network="$(label_value "$loopforge_network")"
    compose_project="$(label_value "$compose_project")"
    compose_network="$(label_value "$compose_network")"
    config_files="$(label_value "$config_files")"
    working_dir="$(label_value "$working_dir")"
    if [ "$loopforge_resource" = docker-simulation ]; then
      project="$loopforge_project"
      network="$loopforge_network"
    else
      project="$compose_project"
      network="$compose_network"
      source_matches_repo "$config_files" "$working_dir" || continue
    fi
    [ "$network" = harness ] || continue
    networks+=("$network_id"$'\t'"$name"$'\t'"$project")
    append_unique projects "$project"
  done <<<"$ids"
}

inventory_networks() {
  networks=()
  inventory_networks_by_filter 'label=org.loopforge.resource=docker-simulation'
  inventory_networks_by_filter 'label=com.docker.compose.project'
}

dedupe_specs() {
  awk -F '\t' 'NF && !seen[$1]++'
}

inventory_resources() {
  projects=()
  image_specs=()
  inventory_containers
  inventory_images_by_label
  inventory_networks
  if [ "${#image_specs[@]}" -gt 0 ]; then
    mapfile -t image_specs < <(printf '%s\n' "${image_specs[@]}" | dedupe_specs)
  fi
  if [ "${#containers[@]}" -gt 0 ]; then
    mapfile -t containers < <(printf '%s\n' "${containers[@]}" | dedupe_specs)
  fi
  if [ "${#networks[@]}" -gt 0 ]; then
    mapfile -t networks < <(printf '%s\n' "${networks[@]}" | dedupe_specs)
  fi
}

print_dry_run() {
  local spec id name project service
  printf 'dry-run docker=available\n'
  for spec in "${containers[@]}"; do
    IFS=$'\t' read -r id name project service <<<"$spec"
    printf 'would-remove-container id=%s name=%s project=%s service=%s\n' "$id" "$name" "$project" "$service"
  done
  for spec in "${networks[@]}"; do
    IFS=$'\t' read -r id name project <<<"$spec"
    printf 'would-remove-network id=%s name=%s project=%s\n' "$id" "$name" "$project"
  done
  for spec in "${image_specs[@]}"; do
    IFS=$'\t' read -r id project service <<<"$spec"
    printf 'would-remove-image target=%s project=%s service=%s\n' "$id" "$project" "$service"
  done
  printf 'dry-run: ok containers=%s networks=%s images=%s\n' \
    "${#containers[@]}" "${#networks[@]}" "${#image_specs[@]}"
}

remove_containers() {
  local spec id name project service
  for spec in "${containers[@]}"; do
    IFS=$'\t' read -r id name project service <<<"$spec"
    docker rm -f "$id" >/dev/null
    printf 'removed container=%s name=%s\n' "$id" "$name"
  done
}

remove_networks() {
  local spec id name project
  for spec in "${networks[@]}"; do
    IFS=$'\t' read -r id name project <<<"$spec"
    docker network rm "$id" >/dev/null
    printf 'removed network=%s name=%s\n' "$id" "$name"
  done
}

remove_images() {
  local spec id project service
  for spec in "${image_specs[@]}"; do
    IFS=$'\t' read -r id project service <<<"$spec"
    docker image rm "$id" >/dev/null
    printf 'removed image=%s project=%s service=%s\n' "$id" "$project" "$service"
  done
}

verify_cleanup() {
  local remaining
  inventory_resources
  remaining=$(( ${#containers[@]} + ${#networks[@]} + ${#image_specs[@]} ))
  [ "$remaining" -eq 0 ] || die "LoopForge Docker resources remain after cleanup"
}

main() {
  local container_count network_count image_count
  parse_args "$@"
  require_command docker
  docker version >/dev/null 2>&1 || die "Unable to query Docker daemon"
  inventory_resources
  if [ "$dry_run" -eq 1 ]; then
    print_dry_run
    return 0
  fi
  container_count="${#containers[@]}"
  network_count="${#networks[@]}"
  image_count="${#image_specs[@]}"
  remove_containers
  remove_networks
  remove_images
  verify_cleanup
  printf 'cleanup: ok containers=%s networks=%s images=%s\n' \
    "$container_count" "$network_count" "$image_count"
}

main "$@"
