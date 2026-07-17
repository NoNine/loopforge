#!/usr/bin/env bash

ensure_gerrit_validation_key() {
  local log private_key public_key bundle_public_key secret_dir
  log="${1:?log required}"
  secret_dir="$HARNESS_GERRIT_VALIDATION_SECRET_DIR"
  private_key="$HARNESS_GERRIT_VALIDATION_SECRET_DIR/jenkins-gerrit"
  public_key="$HARNESS_GERRIT_VALIDATION_SECRET_DIR/jenkins-gerrit.pub"
  bundle_public_key="$HARNESS_BUNDLE_FACTORY_VALIDATION_PUBLIC_DIR/jenkins-gerrit.pub"
  if [ -d "$secret_dir" ] && [ ! -w "$secret_dir" ]; then
    rm -rf "$secret_dir"
  fi
  mkdir -p "$secret_dir" "$(dirname "$bundle_public_key")"
  chmod "$LF_MODE_PRIVATE_DIR" "$secret_dir"
  if [ ! -s "$private_key" ]; then
    ssh-keygen -q -t ed25519 -N '' -C jenkins-gerrit-validation-simulation \
      -f "$private_key" >>"$log" 2>&1
  fi
  chmod "$LF_MODE_PRIVATE_FILE" "$private_key"
  ssh-keygen -y -f "$private_key" >"$public_key"
  cp "$public_key" "$bundle_public_key"
  printf 'validation_secret_ready role=gerrit private_key_path=redacted public_key_path=%s custody=harness-owned-simulation-not-gerrit-artifact\n' \
    "$bundle_public_key" >>"$log"
}

gerrit_bundle_factory_env_file() {
  printf '%s\n' "/home/ci-operator/loopforge-inputs/gerrit.env"
}

jenkins_controller_bundle_factory_env_file() {
  printf '%s\n' "/home/ci-operator/loopforge-inputs/jenkins-controller.env"
}

container_env_file_for_role() {
  local role service
  role="${1:?role required}"
  service="${2:?service required}"
  case "$service" in
    bundle-factory|gerrit-target|jenkins-controller-target|jenkins-agent-target) ;;
    *) die "Unknown harness service for role env: $service" ;;
  esac
  printf '/home/ci-operator/loopforge-inputs/%s.env\n' "$role"
}

container_state_dir_for_service() {
  local service
  service="${1:?service required}"
  case "$service" in
    bundle-factory) printf '%s\n' "/var/lib/loopforge" ;;
    gerrit-target|jenkins-controller-target|jenkins-agent-target)
      printf '%s\n' "/var/lib/loopforge"
      ;;
    *) die "Unknown harness service for container state dir: $service" ;;
  esac
}

host_container_env_file_for_role() {
  local role service
  role="${1:?role required}"
  service="${2:?service required}"
  case "$service" in
    bundle-factory|gerrit-target|jenkins-controller-target|jenkins-agent-target) ;;
    *) die "Unknown harness service for role env: $service" ;;
  esac
  source_env_file_for_role "$role"
}

host_gerrit_bundle_factory_env_file() {
  printf '%s\n' "$HARNESS_GERRIT_ENV_FILE"
}

host_jenkins_controller_bundle_factory_env_file() {
  printf '%s\n' "$HARNESS_JENKINS_CONTROLLER_ENV_FILE"
}

host_state_dir_for_service() {
  local service
  service="${1:?service required}"
  case "$service" in
    bundle-factory) printf '%s/bundle-factory\n' "$HARNESS_STATE_DIR" ;;
    gerrit-target) printf '%s/gerrit\n' "$HARNESS_STATE_DIR" ;;
    jenkins-controller-target) printf '%s/jenkins-controller\n' "$HARNESS_STATE_DIR" ;;
    jenkins-agent-target) printf '%s/jenkins-agent\n' "$HARNESS_STATE_DIR" ;;
    *) die "Unknown harness service for state dir: $service" ;;
  esac
}

source_env_file_for_role() {
  local role
  role="${1:?role required}"
  case "$role" in
    gerrit) printf '%s\n' "$HARNESS_GERRIT_ENV_FILE" ;;
    jenkins-controller) printf '%s\n' "$HARNESS_JENKINS_CONTROLLER_ENV_FILE" ;;
    jenkins-agent) printf '%s\n' "$HARNESS_JENKINS_AGENT_ENV_FILE" ;;
    *) die "Unknown role for env file: $role" ;;
  esac
}

render_docker_effective_inputs() {
  local staged harness gerrit controller agent integration
  staged="${1:?effective input staging directory required}"
  copy_simulation_input_bundle "$staged" \
    "$HARNESS_SOURCE_INPUT_DIR/harness.env" \
    "$HARNESS_SOURCE_INPUT_DIR/gerrit.env" \
    "$HARNESS_SOURCE_INPUT_DIR/jenkins-controller.env" \
    "$HARNESS_SOURCE_INPUT_DIR/jenkins-agent.env" \
    "$HARNESS_SOURCE_INPUT_DIR/integration.env"
  harness="$staged/harness.env"
  gerrit="$staged/gerrit.env"
  controller="$staged/jenkins-controller.env"
  agent="$staged/jenkins-agent.env"
  integration="$staged/integration.env"
  remove_env_file_value "$integration" INTEGRATION_GERRIT_TARGET_SSH_HOST
  remove_env_file_value "$integration" INTEGRATION_JENKINS_CONTROLLER_TARGET_SSH_HOST
  remove_env_file_value "$integration" INTEGRATION_JENKINS_AGENT_TARGET_SSH_HOST
  set_env_file_value "$harness" HARNESS_GERRIT_ENV_FILE "$HARNESS_RUNTIME_INPUT_DIR/gerrit.env"
  set_env_file_value "$harness" HARNESS_JENKINS_CONTROLLER_ENV_FILE "$HARNESS_RUNTIME_INPUT_DIR/jenkins-controller.env"
  set_env_file_value "$harness" HARNESS_JENKINS_AGENT_ENV_FILE "$HARNESS_RUNTIME_INPUT_DIR/jenkins-agent.env"
  set_env_file_value "$harness" HARNESS_INTEGRATION_ENV_FILE "$HARNESS_RUNTIME_INPUT_DIR/integration.env"
  set_env_file_value "$gerrit" GERRIT_CANONICAL_WEB_URL "http://127.0.0.1:$HARNESS_GERRIT_HTTP_HOST_PORT/"
  set_env_file_value "$gerrit" GERRIT_VERIFICATION_MODE docker-simulation
  set_env_file_value "$controller" JENKINS_VERIFICATION_MODE docker-simulation
  set_env_file_value "$agent" JENKINS_AGENT_VERIFICATION_MODE docker-simulation
  set_env_file_value "$integration" INTEGRATION_MODE "$HARNESS_MODE"
  set_env_file_value "$integration" INTEGRATION_STATE_DIR "$HARNESS_STATE_DIR/integration"
  set_env_file_value "$integration" INTEGRATION_LOG_DIR "$HARNESS_HOST_DIR/logs/integration"
  set_env_file_value "$integration" INTEGRATION_EVIDENCE_DIR "$HARNESS_HOST_DIR/evidence/integration"
  set_env_file_value "$integration" INTEGRATION_GERRIT_TARGET_SSH_PORT "$HARNESS_GERRIT_TARGET_SSH_HOST_PORT"
  set_env_file_value "$integration" INTEGRATION_GERRIT_TARGET_SSH_USER ci-operator
  set_env_file_value "$integration" INTEGRATION_GERRIT_TARGET_SSH_IDENTITY_FILE "$HARNESS_TARGET_SSH_IDENTITY_FILE"
  set_env_file_value "$integration" INTEGRATION_GERRIT_TARGET_SSH_KNOWN_HOSTS_FILE "$HARNESS_TARGET_SSH_KNOWN_HOSTS_FILE"
  set_env_file_value "$integration" INTEGRATION_JENKINS_CONTROLLER_TARGET_SSH_PORT "$HARNESS_JENKINS_CONTROLLER_TARGET_SSH_HOST_PORT"
  set_env_file_value "$integration" INTEGRATION_JENKINS_CONTROLLER_TARGET_SSH_USER ci-operator
  set_env_file_value "$integration" INTEGRATION_JENKINS_CONTROLLER_TARGET_SSH_IDENTITY_FILE "$HARNESS_TARGET_SSH_IDENTITY_FILE"
  set_env_file_value "$integration" INTEGRATION_JENKINS_CONTROLLER_TARGET_SSH_KNOWN_HOSTS_FILE "$HARNESS_TARGET_SSH_KNOWN_HOSTS_FILE"
  set_env_file_value "$integration" INTEGRATION_JENKINS_AGENT_TARGET_SSH_PORT "$HARNESS_JENKINS_AGENT_TARGET_SSH_HOST_PORT"
  set_env_file_value "$integration" INTEGRATION_JENKINS_AGENT_TARGET_SSH_USER ci-operator
  set_env_file_value "$integration" INTEGRATION_JENKINS_AGENT_TARGET_SSH_IDENTITY_FILE "$HARNESS_TARGET_SSH_IDENTITY_FILE"
  set_env_file_value "$integration" INTEGRATION_JENKINS_AGENT_TARGET_SSH_KNOWN_HOSTS_FILE "$HARNESS_TARGET_SSH_KNOWN_HOSTS_FILE"
  set_env_file_value "$integration" INTEGRATION_GERRIT_ACL_MODE apply-direct
  set_env_file_value "$integration" INTEGRATION_ALLOW_SIMULATION_DIRECT_ACL_APPLY 1
}

docker_publish_or_verify_effective_inputs() {
  local staged
  staged="$(simulation_input_staging_dir "$HARNESS_RUNTIME_INPUT_DIR")" || return $?
  if ! render_docker_effective_inputs "$staged"; then
    rm -rf -- "$staged"
    return 1
  fi
  publish_or_verify_effective_inputs \
    "$HARNESS_WORKFLOW_STATE_FILE" "$HARNESS_RUN_MARKER" docker \
    "$HARNESS_SET_ID" "$HARNESS_RUN_ID" "$HARNESS_SOURCE_INPUT_DIR" \
    "$HARNESS_EFFECTIVE_INPUT_RECORD" "$HARNESS_RUNTIME_INPUT_DIR" "$staged"
}

require_container_role_env() {
  local role service host_env_file
  role="${1:?role required}"
  service="${2:?service required}"
  host_env_file="$(host_container_env_file_for_role "$role" "$service")"
  require_readable_file "Rendered $role env file; run init-run first" "$host_env_file"
  printf '%s\n' "$(container_env_file_for_role "$role" "$service")"
}

stage_container_role_env() {
  local role service log host_env_file container_env_file
  role="${1:?role required}"
  service="${2:?service required}"
  log="${3:?log required}"
  host_env_file="$(host_container_env_file_for_role "$role" "$service")"
  container_env_file="$(container_env_file_for_role "$role" "$service")"
  require_readable_file "Rendered $role env file; run init-run first" "$host_env_file"
  stage_operator_input_file "$service" "$host_env_file" "$container_env_file" ci-operator ci-operator 0600 "$log"
  printf '%s\n' "$container_env_file"
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
