#!/usr/bin/env bash

__docker_ssh_env_prefix() {
  case "${1:-}" in
    gerrit) printf '%s\n' INTEGRATION_GERRIT_TARGET ;;
    jenkins-controller) printf '%s\n' INTEGRATION_JENKINS_CONTROLLER_TARGET ;;
    jenkins-agent) printf '%s\n' INTEGRATION_JENKINS_AGENT_TARGET ;;
    *) die "Unknown role '${1:-}'; expected gerrit, jenkins-controller, or jenkins-agent" ;;
  esac
}

__docker_ssh_inventory_value() {
  local role suffix prefix value
  role="${1:?role required}"
  suffix="${2:?suffix required}"
  prefix="$(__docker_ssh_env_prefix "$role")"
  eval "value=\${${prefix}_SSH_${suffix}:-}"
  printf '%s\n' "$value"
}

docker_ssh_interactive() {
  local role host port user identity_file known_hosts_file
  role="${1:?role required}"
  bootstrap_harness_env
  docker_set_require_runtime
  require_command ssh
  require_running_service "$(docker_compose_service_for_role "$role")"
  require_readable_file "Runtime integration env file" "$HARNESS_INTEGRATION_ENV_FILE"
  set -a
  # shellcheck disable=SC1090
  . "$HARNESS_INTEGRATION_ENV_FILE"
  set +a

  host="$(__docker_ssh_inventory_value "$role" HOST)"
  port="$(__docker_ssh_inventory_value "$role" PORT)"
  user="$(__docker_ssh_inventory_value "$role" USER)"
  identity_file="$(__docker_ssh_inventory_value "$role" IDENTITY_FILE)"
  known_hosts_file="$(__docker_ssh_inventory_value "$role" KNOWN_HOSTS_FILE)"

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

ensure_target_ssh_keypair() {
  require_command ssh-keygen
  mkdir -p "$HARNESS_TARGET_SSH_DIR"
  chmod "$LF_MODE_PRIVATE_DIR" "$HARNESS_TARGET_SSH_DIR"
  if [ ! -s "$HARNESS_TARGET_SSH_IDENTITY_FILE" ]; then
    ssh-keygen -q -t ed25519 -N '' -C "loopforge-$HARNESS_RUN_ID-target-ssh" \
      -f "$HARNESS_TARGET_SSH_IDENTITY_FILE"
  fi
  chmod "$LF_MODE_PRIVATE_FILE" "$HARNESS_TARGET_SSH_IDENTITY_FILE"
  ssh-keygen -y -f "$HARNESS_TARGET_SSH_IDENTITY_FILE" >"$HARNESS_TARGET_SSH_IDENTITY_FILE.pub"
  chmod "$LF_MODE_PUBLIC_FILE" "$HARNESS_TARGET_SSH_IDENTITY_FILE.pub"
  if [ ! -e "$HARNESS_TARGET_SSH_KNOWN_HOSTS_FILE" ]; then
    : >"$HARNESS_TARGET_SSH_KNOWN_HOSTS_FILE"
    chmod "$LF_MODE_PRIVATE_FILE" "$HARNESS_TARGET_SSH_KNOWN_HOSTS_FILE"
  fi
}

refresh_target_ssh_known_hosts() {
  local log tmp
  log="${1:?log required}"
  mkdir -p "$HARNESS_TARGET_SSH_DIR"
  tmp="$(mktemp "$HARNESS_TARGET_SSH_DIR/known_hosts.XXXXXX")"
  chmod "$LF_MODE_PRIVATE_FILE" "$tmp"
  ssh-keyscan -T 5 -p "$HARNESS_GERRIT_TARGET_SSH_HOST_PORT" 127.0.0.1 >>"$tmp" 2>>"$log"
  ssh-keyscan -T 5 -p "$HARNESS_JENKINS_CONTROLLER_TARGET_SSH_HOST_PORT" 127.0.0.1 >>"$tmp" 2>>"$log"
  ssh-keyscan -T 5 -p "$HARNESS_JENKINS_AGENT_TARGET_SSH_HOST_PORT" 127.0.0.1 >>"$tmp" 2>>"$log"
  mv -- "$tmp" "$HARNESS_TARGET_SSH_KNOWN_HOSTS_FILE"
  chmod "$LF_MODE_PRIVATE_FILE" "$HARNESS_TARGET_SSH_KNOWN_HOSTS_FILE"
  printf 'target_ssh_known_hosts=ready file=%s scope=docker-simulation\n' "$HARNESS_TARGET_SSH_KNOWN_HOSTS_FILE" >>"$log"
}

stage_target_ssh_authorized_key_for_service() {
  local service log public_key container_public_key command
  service="${1:?service required}"
  log="${2:?log required}"
  public_key="$HARNESS_TARGET_SSH_IDENTITY_FILE.pub"
  container_public_key="/home/ci-operator/loopforge-inputs/target-ssh/ci-operator.pub"
  stage_operator_input_file "$service" "$public_key" "$container_public_key" ci-operator ci-operator 0644 "$log" ||
    return 1
  command="$(owned_directory_command ci-operator ci-operator 0700 /home/ci-operator/.ssh 0)"
  command="$command && cp $(shell_quote "$container_public_key") /home/ci-operator/.ssh/authorized_keys"
  command="$command && chown ci-operator:ci-operator /home/ci-operator/.ssh/authorized_keys"
  command="$command && chmod $LF_MODE_PRIVATE_FILE /home/ci-operator/.ssh/authorized_keys"
  if ! compose exec -T -u root "$service" sh -c "$command" >>"$log" 2>&1; then
    return 1
  fi
  printf 'target_ssh_authorized_key_installed service=%s source=%s input=%s destination=/home/ci-operator/.ssh/authorized_keys transfer_mode=docker-cp-input-waiver custody=docker-simulation-control-plane scope=docker-simulation-control-plane\n' \
    "$service" "$public_key" "$container_public_key" >>"$log"
}

stage_target_ssh_authorized_keys() {
  local log service
  log="${1:?log required}"
  for service in gerrit-target jenkins-controller-target jenkins-agent-target; do
    stage_target_ssh_authorized_key_for_service "$service" "$log" || return 1
  done
}
