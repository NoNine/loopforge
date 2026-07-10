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
  chmod 0700 "$secret_dir"
  if [ ! -s "$private_key" ]; then
    ssh-keygen -q -t ed25519 -N '' -C jenkins-gerrit-validation-simulation \
      -f "$private_key" >>"$log" 2>&1
  fi
  chmod 0600 "$private_key"
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
  printf '%s/helper-envs/%s/%s.env\n' "$HARNESS_RUNTIME_INPUT_DIR" "$service" "$role"
}

host_gerrit_bundle_factory_env_file() {
  printf '%s/helper-envs/bundle-factory/gerrit-bundle-factory.env\n' "$HARNESS_RUNTIME_INPUT_DIR"
}

host_jenkins_controller_bundle_factory_env_file() {
  printf '%s/helper-envs/bundle-factory/jenkins-controller-bundle-factory.env\n' "$HARNESS_RUNTIME_INPUT_DIR"
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

render_container_role_env() {
  local role service src host_env_file container_env_file canonical_web_url
  role="${1:?role required}"
  service="${2:?service required}"
  src="$(source_env_file_for_role "$role")"
  require_readable_file "Harness $role env file" "$src"
  container_env_file="$(container_env_file_for_role "$role" "$service")"
  host_env_file="$(host_container_env_file_for_role "$role" "$service")"
  mkdir -p "$(dirname "$host_env_file")"
  cp -- "$src" "$host_env_file"
  if [ "$role" = "gerrit" ]; then
    canonical_web_url="http://127.0.0.1:$HARNESS_GERRIT_HTTP_HOST_PORT/"
    set_env_file_value "$host_env_file" GERRIT_CANONICAL_WEB_URL "$canonical_web_url"
  fi
  chmod 0600 "$host_env_file"
  printf '%s\n' "$container_env_file"
}

render_gerrit_bundle_factory_env() {
  local env_file host_env_file src
  env_file="$(gerrit_bundle_factory_env_file)"
  host_env_file="$(host_gerrit_bundle_factory_env_file)"
  src="$(source_env_file_for_role gerrit)"
  require_readable_file "Harness gerrit env file" "$src"
  mkdir -p "$(dirname "$host_env_file")"
  cp -- "$src" "$host_env_file"
  set_env_file_value "$host_env_file" GERRIT_DOWNLOAD_ARTIFACTS "1"
  chmod 0600 "$host_env_file"
  printf '%s\n' "$env_file"
}

render_jenkins_controller_bundle_factory_env() {
  local env_file host_env_file src
  env_file="$(jenkins_controller_bundle_factory_env_file)"
  host_env_file="$(host_jenkins_controller_bundle_factory_env_file)"
  src="$(source_env_file_for_role jenkins-controller)"
  require_readable_file "Harness jenkins-controller env file" "$src"
  mkdir -p "$(dirname "$host_env_file")"
  cp -- "$src" "$host_env_file"
  set_env_file_value "$host_env_file" JENKINS_DOWNLOAD_ARTIFACTS "1"
  chmod 0600 "$host_env_file"
  printf '%s\n' "$env_file"
}

write_rendered_helper_envs() {
  render_gerrit_bundle_factory_env >/dev/null
  render_jenkins_controller_bundle_factory_env >/dev/null
  render_container_role_env jenkins-agent bundle-factory >/dev/null
  render_container_role_env gerrit gerrit-target >/dev/null
  render_container_role_env jenkins-controller jenkins-controller-target >/dev/null
  render_container_role_env jenkins-agent jenkins-agent-target >/dev/null
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
  chmod 0600 "$tmp"
  ssh-keyscan -T 5 -p "$HARNESS_GERRIT_TARGET_SSH_HOST_PORT" 127.0.0.1 >>"$tmp" 2>>"$log"
  ssh-keyscan -T 5 -p "$HARNESS_JENKINS_CONTROLLER_TARGET_SSH_HOST_PORT" 127.0.0.1 >>"$tmp" 2>>"$log"
  ssh-keyscan -T 5 -p "$HARNESS_JENKINS_AGENT_TARGET_SSH_HOST_PORT" 127.0.0.1 >>"$tmp" 2>>"$log"
  mv -- "$tmp" "$HARNESS_TARGET_SSH_KNOWN_HOSTS_FILE"
  chmod 0600 "$HARNESS_TARGET_SSH_KNOWN_HOSTS_FILE"
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
  command="$command && chmod 0600 /home/ci-operator/.ssh/authorized_keys"
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
