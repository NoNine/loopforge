#!/usr/bin/env bash

set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
repo_root="$(CDPATH= cd -- "$script_dir/../.." && pwd)"
docker_dir="$script_dir"
compose_file="$docker_dir/compose.yaml"
docker_env_example="$docker_dir/examples/docker.env.example"
integration_helper="${HARNESS_TEST_INTEGRATION_HELPER:-$repo_root/scripts/integration-setup.sh}"
roles=(gerrit jenkins-controller jenkins-agent)

usage() {
  cat <<'USAGE'
Usage:
  simulation/docker/simulate.sh <command> [options]

Commands:
  preflight
  render-config
  up
  status
  prepare-artifacts [--role <gerrit|jenkins-controller|jenkins-agent>]
  stage-artifacts [--role <gerrit|jenkins-controller|jenkins-agent>]
  run-role-gate --role <gerrit|jenkins-controller|jenkins-agent>
  check
  full-verify
  down

Options:
  --env FILE        Harness env file for bootstrap and render-config.
  --role ROLE       Role for role-scoped commands.
  -h, --help        Show this help.

The harness is the Docker simulation CLI. It owns role gates and cross-role
integration orchestration. Public internet fallback on target hosts is
simulation-only.
USAGE
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

print_command_summary() {
  local command_name role message
  command_name="${1:?command required}"
  role="${2-}"
  message="${3:?message required}"
  if [ -n "$role" ]; then
    printf '%s[%s]: %s\n' "$command_name" "$role" "$message"
  else
    printf '%s: %s\n' "$command_name" "$message"
  fi
}

print_command_failure() {
  local command_name role message log evidence
  command_name="${1:?command required}"
  role="${2-}"
  message="${3:?message required}"
  log="${4-}"
  evidence="${5-}"
  print_command_summary "$command_name" "$role" "$message"
  [ -n "$log" ] && printf 'log=%s\n' "$log"
  [ -n "$evidence" ] && printf 'evidence=%s\n' "$evidence"
}

validate_compose_name() {
  local name value
  name="${1:?name required}"
  value="${2:?value required}"

  case "$value" in
    [a-z0-9]*)
      ;;
    *)
      die "$name must start with a lowercase letter or digit"
      ;;
  esac

  case "$value" in
    *[!a-z0-9_-]*)
      die "$name may contain only lowercase letters, digits, underscores, and dashes"
      ;;
  esac

  if [ "${#value}" -gt 63 ]; then
    die "$name must be 63 characters or fewer"
  fi
}

validate_harness_inputs() {
  validate_compose_name "HARNESS_RUN_ID" "$HARNESS_RUN_ID"
  validate_compose_name "HARNESS_PROJECT_NAME" "$HARNESS_PROJECT_NAME"
}

timestamp_utc() {
  date -u +%Y%m%dT%H%M%SZ
}

iso_timestamp_utc() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

HARNESS_PROJECT_NAME_OPERATOR_SET="${HARNESS_PROJECT_NAME+x}"
HARNESS_RUN_ID_OPERATOR_SET="${HARNESS_RUN_ID+x}"
HARNESS_STATE_DIR_OPERATOR_SET="${HARNESS_STATE_DIR+x}"
HARNESS_PRODUCT_HOME_DIR_OPERATOR_SET="${HARNESS_PRODUCT_HOME_DIR+x}"
HARNESS_STAGING_DIR_OPERATOR_SET="${HARNESS_STAGING_DIR+x}"
HARNESS_EVIDENCE_DIR_OPERATOR_SET="${HARNESS_EVIDENCE_DIR+x}"
HARNESS_LOG_DIR_OPERATOR_SET="${HARNESS_LOG_DIR+x}"
HARNESS_RENDERED_ENV_OPERATOR_SET="${HARNESS_RENDERED_ENV+x}"
HARNESS_BASELINE_CONTRACT_OPERATOR_SET="${HARNESS_BASELINE_CONTRACT+x}"
HARNESS_ENV_FILE_OPERATOR_SET="${HARNESS_ENV_FILE+x}"
HARNESS_GERRIT_ENV_FILE_OPERATOR_SET="${HARNESS_GERRIT_ENV_FILE+x}"
HARNESS_JENKINS_CONTROLLER_ENV_FILE_OPERATOR_SET="${HARNESS_JENKINS_CONTROLLER_ENV_FILE+x}"
HARNESS_JENKINS_AGENT_ENV_FILE_OPERATOR_SET="${HARNESS_JENKINS_AGENT_ENV_FILE+x}"
HARNESS_INTEGRATION_ENV_FILE_OPERATOR_SET="${HARNESS_INTEGRATION_ENV_FILE+x}"
HARNESS_RUN_ID_OPERATOR_VALUE="${HARNESS_RUN_ID-}"
HARNESS_PROJECT_NAME_OPERATOR_VALUE="${HARNESS_PROJECT_NAME-}"
HARNESS_STATE_DIR_OPERATOR_VALUE="${HARNESS_STATE_DIR-}"
HARNESS_PRODUCT_HOME_DIR_OPERATOR_VALUE="${HARNESS_PRODUCT_HOME_DIR-}"
HARNESS_STAGING_DIR_OPERATOR_VALUE="${HARNESS_STAGING_DIR-}"
HARNESS_EVIDENCE_DIR_OPERATOR_VALUE="${HARNESS_EVIDENCE_DIR-}"
HARNESS_LOG_DIR_OPERATOR_VALUE="${HARNESS_LOG_DIR-}"
HARNESS_RENDERED_ENV_OPERATOR_VALUE="${HARNESS_RENDERED_ENV-}"
HARNESS_BASELINE_CONTRACT_OPERATOR_VALUE="${HARNESS_BASELINE_CONTRACT-}"
HARNESS_ENV_FILE_OPERATOR_VALUE="${HARNESS_ENV_FILE-}"
HARNESS_GERRIT_ENV_FILE_OPERATOR_VALUE="${HARNESS_GERRIT_ENV_FILE-}"
HARNESS_JENKINS_CONTROLLER_ENV_FILE_OPERATOR_VALUE="${HARNESS_JENKINS_CONTROLLER_ENV_FILE-}"
HARNESS_JENKINS_AGENT_ENV_FILE_OPERATOR_VALUE="${HARNESS_JENKINS_AGENT_ENV_FILE-}"
HARNESS_INTEGRATION_ENV_FILE_OPERATOR_VALUE="${HARNESS_INTEGRATION_ENV_FILE-}"
HARNESS_GERRIT_HTTP_HOST_PORT_OPERATOR_SET="${HARNESS_GERRIT_HTTP_HOST_PORT+x}"
HARNESS_JENKINS_HTTP_HOST_PORT_OPERATOR_SET="${HARNESS_JENKINS_HTTP_HOST_PORT+x}"
HARNESS_GERRIT_HTTP_HOST_PORT_OPERATOR_VALUE="${HARNESS_GERRIT_HTTP_HOST_PORT-}"
HARNESS_JENKINS_HTTP_HOST_PORT_OPERATOR_VALUE="${HARNESS_JENKINS_HTTP_HOST_PORT-}"

HARNESS_MODE="${HARNESS_MODE:-docker-simulation}"
HARNESS_RUN_ID="${HARNESS_RUN_ID:-manual}"
HARNESS_PROJECT_NAME="${HARNESS_PROJECT_NAME:-gerrit-jenkins-harness-${HARNESS_RUN_ID}}"
HARNESS_UBUNTU_IMAGE="${HARNESS_UBUNTU_IMAGE:-ubuntu:24.04}"
HARNESS_UBUNTU_BASELINE_VERSION="${HARNESS_UBUNTU_BASELINE_VERSION:-24.04.4}"
HARNESS_UBUNTU_BASELINE_RELEASE="${HARNESS_UBUNTU_BASELINE_RELEASE:-24.04}"
HARNESS_UBUNTU_BASELINE_CODENAME="${HARNESS_UBUNTU_BASELINE_CODENAME:-noble}"
HARNESS_JAVA_BASELINE="${HARNESS_JAVA_BASELINE:-21}"
HARNESS_GERRIT_BASELINE="${HARNESS_GERRIT_BASELINE:-3.13.6}"
HARNESS_JENKINS_BASELINE="${HARNESS_JENKINS_BASELINE:-2.555.3}"
HARNESS_JENKINS_PLUGIN_MANAGER_BASELINE="${HARNESS_JENKINS_PLUGIN_MANAGER_BASELINE:-2.15.0}"
HARNESS_LDAP_IMAGE="${HARNESS_LDAP_IMAGE:-osixia/openldap:1.5.0}"
HARNESS_LDAP_DOMAIN="${HARNESS_LDAP_DOMAIN:-example.test}"
HARNESS_LDAP_BASE_DN="${HARNESS_LDAP_BASE_DN:-dc=example,dc=test}"
HARNESS_LDAP_ADMIN_PASSWORD="${HARNESS_LDAP_ADMIN_PASSWORD:-admin-password}"
HARNESS_LDAP_CONFIG_PASSWORD="${HARNESS_LDAP_CONFIG_PASSWORD:-config-password}"
HARNESS_LDAP_BIND_USER="${HARNESS_LDAP_BIND_USER:-readonly}"
HARNESS_LDAP_BIND_PASSWORD="${HARNESS_LDAP_BIND_PASSWORD:-readonly-password}"
HARNESS_PUBLIC_INTERNET_FALLBACK_LABEL="${HARNESS_PUBLIC_INTERNET_FALLBACK_LABEL:-simulation-only}"

HARNESS_STATE_DIR="${HARNESS_STATE_DIR:-$repo_root/simulation/state/docker/$HARNESS_RUN_ID}"
HARNESS_PRODUCT_HOME_DIR="${HARNESS_PRODUCT_HOME_DIR:-$repo_root/simulation/product-homes/docker/$HARNESS_RUN_ID}"
HARNESS_STAGING_DIR="${HARNESS_STAGING_DIR:-$repo_root/simulation/staging/docker/$HARNESS_RUN_ID}"
HARNESS_EVIDENCE_DIR="${HARNESS_EVIDENCE_DIR:-$repo_root/simulation/evidence/docker/$HARNESS_RUN_ID}"
HARNESS_LOG_DIR="${HARNESS_LOG_DIR:-$repo_root/logs/docker/$HARNESS_RUN_ID}"
HARNESS_INTEGRATION_ENV_FILE="${HARNESS_INTEGRATION_ENV_FILE:-$repo_root/examples/integration.env.example}"
HARNESS_GERRIT_ENV_FILE="${HARNESS_GERRIT_ENV_FILE:-$repo_root/examples/gerrit.env.example}"
HARNESS_JENKINS_CONTROLLER_ENV_FILE="${HARNESS_JENKINS_CONTROLLER_ENV_FILE:-$repo_root/examples/jenkins-controller.env.example}"
HARNESS_JENKINS_AGENT_ENV_FILE="${HARNESS_JENKINS_AGENT_ENV_FILE:-$repo_root/examples/jenkins-agent.env.example}"
HARNESS_JENKINS_SHARED_STORAGE_PATH="${HARNESS_JENKINS_SHARED_STORAGE_PATH:-}"
HARNESS_ENV_FILE="${HARNESS_ENV_FILE:-$HARNESS_ENV_FILE_OPERATOR_VALUE}"
HARNESS_RENDERED_ENV="${HARNESS_RENDERED_ENV:-$HARNESS_STATE_DIR/rendered/harness.env}"
HARNESS_RUNTIME_ENV="${HARNESS_RUNTIME_ENV:-${HARNESS_RENDERED_ENV%.env}.runtime.env}"
HARNESS_RUNTIME_INPUT_DIR="${HARNESS_RUNTIME_INPUT_DIR:-$HARNESS_STATE_DIR/rendered/runtime-inputs}"
HARNESS_BASELINE_CONTRACT="${HARNESS_BASELINE_CONTRACT:-$HARNESS_STATE_DIR/rendered/artifact-manifest-contract.txt}"

export HARNESS_MODE HARNESS_RUN_ID HARNESS_PROJECT_NAME
export HARNESS_UBUNTU_IMAGE HARNESS_LDAP_IMAGE
export HARNESS_LDAP_DOMAIN HARNESS_LDAP_BASE_DN
export HARNESS_LDAP_ADMIN_PASSWORD HARNESS_LDAP_CONFIG_PASSWORD
export HARNESS_LDAP_BIND_USER HARNESS_LDAP_BIND_PASSWORD
export HARNESS_PUBLIC_INTERNET_FALLBACK_LABEL
export HARNESS_STATE_DIR HARNESS_PRODUCT_HOME_DIR HARNESS_STAGING_DIR HARNESS_EVIDENCE_DIR HARNESS_LOG_DIR
export HARNESS_JENKINS_SHARED_STORAGE_PATH HARNESS_ENV_FILE
export HARNESS_GERRIT_ENV_FILE HARNESS_JENKINS_CONTROLLER_ENV_FILE
export HARNESS_JENKINS_AGENT_ENV_FILE HARNESS_INTEGRATION_ENV_FILE

compose_kind=""
compose_cmd=()

require_readable_file() {
  local name file
  name="${1:?name required}"
  file="${2:?file required}"
  [ -f "$file" ] || die "$name does not exist: $file"
  [ -r "$file" ] || die "$name is not readable: $file"
}

resolve_repo_relative_path() {
  local path
  path="${1:?path required}"
  case "$path" in
    /*) printf '%s\n' "$path" ;;
    *) printf '%s/%s\n' "$repo_root" "$path" ;;
  esac
}

normalize_operator_env_paths() {
  HARNESS_GERRIT_ENV_FILE="$(resolve_repo_relative_path "$HARNESS_GERRIT_ENV_FILE")"
  HARNESS_JENKINS_CONTROLLER_ENV_FILE="$(resolve_repo_relative_path "$HARNESS_JENKINS_CONTROLLER_ENV_FILE")"
  HARNESS_JENKINS_AGENT_ENV_FILE="$(resolve_repo_relative_path "$HARNESS_JENKINS_AGENT_ENV_FILE")"
  HARNESS_INTEGRATION_ENV_FILE="$(resolve_repo_relative_path "$HARNESS_INTEGRATION_ENV_FILE")"
  export HARNESS_GERRIT_ENV_FILE HARNESS_JENKINS_CONTROLLER_ENV_FILE
  export HARNESS_JENKINS_AGENT_ENV_FILE HARNESS_INTEGRATION_ENV_FILE
}

load_env_file() {
  local file
  file="${1:?env file required}"
  require_readable_file "Harness env file" "$file"
  [ -n "$HARNESS_PROJECT_NAME_OPERATOR_SET" ] || unset HARNESS_PROJECT_NAME
  [ -n "$HARNESS_STATE_DIR_OPERATOR_SET" ] || unset HARNESS_STATE_DIR
  [ -n "$HARNESS_PRODUCT_HOME_DIR_OPERATOR_SET" ] || unset HARNESS_PRODUCT_HOME_DIR
  [ -n "$HARNESS_STAGING_DIR_OPERATOR_SET" ] || unset HARNESS_STAGING_DIR
  [ -n "$HARNESS_EVIDENCE_DIR_OPERATOR_SET" ] || unset HARNESS_EVIDENCE_DIR
  [ -n "$HARNESS_LOG_DIR_OPERATOR_SET" ] || unset HARNESS_LOG_DIR
  HARNESS_INTEGRATION_ENV_FILE="$repo_root/examples/integration.env.example"
  HARNESS_GERRIT_ENV_FILE="$repo_root/examples/gerrit.env.example"
  HARNESS_JENKINS_CONTROLLER_ENV_FILE="$repo_root/examples/jenkins-controller.env.example"
  HARNESS_JENKINS_AGENT_ENV_FILE="$repo_root/examples/jenkins-agent.env.example"
  set -a
  # shellcheck disable=SC1090
  . "$file"
  set +a
  normalize_operator_env_paths
  if [ -n "$HARNESS_RUN_ID_OPERATOR_SET" ]; then
    HARNESS_RUN_ID="$HARNESS_RUN_ID_OPERATOR_VALUE"
  fi
  if [ -n "$HARNESS_PROJECT_NAME_OPERATOR_SET" ]; then
    HARNESS_PROJECT_NAME="$HARNESS_PROJECT_NAME_OPERATOR_VALUE"
  fi
  if [ -n "$HARNESS_STATE_DIR_OPERATOR_SET" ]; then
    HARNESS_STATE_DIR="$HARNESS_STATE_DIR_OPERATOR_VALUE"
  fi
  if [ -n "$HARNESS_PRODUCT_HOME_DIR_OPERATOR_SET" ]; then
    HARNESS_PRODUCT_HOME_DIR="$HARNESS_PRODUCT_HOME_DIR_OPERATOR_VALUE"
  fi
  if [ -n "$HARNESS_STAGING_DIR_OPERATOR_SET" ]; then
    HARNESS_STAGING_DIR="$HARNESS_STAGING_DIR_OPERATOR_VALUE"
  fi
  if [ -n "$HARNESS_EVIDENCE_DIR_OPERATOR_SET" ]; then
    HARNESS_EVIDENCE_DIR="$HARNESS_EVIDENCE_DIR_OPERATOR_VALUE"
  fi
  if [ -n "$HARNESS_LOG_DIR_OPERATOR_SET" ]; then
    HARNESS_LOG_DIR="$HARNESS_LOG_DIR_OPERATOR_VALUE"
  fi
  if [ -n "$HARNESS_GERRIT_HTTP_HOST_PORT_OPERATOR_SET" ]; then
    HARNESS_GERRIT_HTTP_HOST_PORT="$HARNESS_GERRIT_HTTP_HOST_PORT_OPERATOR_VALUE"
  fi
  if [ -n "$HARNESS_JENKINS_HTTP_HOST_PORT_OPERATOR_SET" ]; then
    HARNESS_JENKINS_HTTP_HOST_PORT="$HARNESS_JENKINS_HTTP_HOST_PORT_OPERATOR_VALUE"
  fi
  HARNESS_ENV_FILE="$file"
  if [ -z "$HARNESS_STATE_DIR_OPERATOR_SET" ]; then
    HARNESS_STATE_DIR="${HARNESS_STATE_DIR:-$repo_root/simulation/state/docker/$HARNESS_RUN_ID}"
  fi
  if [ -z "$HARNESS_PRODUCT_HOME_DIR_OPERATOR_SET" ]; then
    HARNESS_PRODUCT_HOME_DIR="${HARNESS_PRODUCT_HOME_DIR:-$repo_root/simulation/product-homes/docker/$HARNESS_RUN_ID}"
  fi
  if [ -z "$HARNESS_STAGING_DIR_OPERATOR_SET" ]; then
    HARNESS_STAGING_DIR="${HARNESS_STAGING_DIR:-$repo_root/simulation/staging/docker/$HARNESS_RUN_ID}"
  fi
  if [ -z "$HARNESS_EVIDENCE_DIR_OPERATOR_SET" ]; then
    HARNESS_EVIDENCE_DIR="${HARNESS_EVIDENCE_DIR:-$repo_root/simulation/evidence/docker/$HARNESS_RUN_ID}"
  fi
  if [ -z "$HARNESS_LOG_DIR_OPERATOR_SET" ]; then
    HARNESS_LOG_DIR="${HARNESS_LOG_DIR:-$repo_root/logs/docker/$HARNESS_RUN_ID}"
  fi
  if [ -n "$HARNESS_RENDERED_ENV_OPERATOR_SET" ]; then
    HARNESS_RENDERED_ENV="$HARNESS_RENDERED_ENV_OPERATOR_VALUE"
  else
    HARNESS_RENDERED_ENV="$HARNESS_STATE_DIR/rendered/harness.env"
  fi
  HARNESS_RUNTIME_ENV="${HARNESS_RENDERED_ENV%.env}.runtime.env"
  HARNESS_RUNTIME_INPUT_DIR="$HARNESS_STATE_DIR/rendered/runtime-inputs"
  if [ -n "$HARNESS_BASELINE_CONTRACT_OPERATOR_SET" ]; then
    HARNESS_BASELINE_CONTRACT="$HARNESS_BASELINE_CONTRACT_OPERATOR_VALUE"
  else
    HARNESS_BASELINE_CONTRACT="$HARNESS_STATE_DIR/rendered/artifact-manifest-contract.txt"
  fi
  export HARNESS_ENV_FILE HARNESS_PRODUCT_HOME_DIR HARNESS_RENDERED_ENV HARNESS_RUNTIME_ENV HARNESS_RUNTIME_INPUT_DIR HARNESS_BASELINE_CONTRACT
  export HARNESS_GERRIT_ENV_FILE HARNESS_JENKINS_CONTROLLER_ENV_FILE
  export HARNESS_JENKINS_AGENT_ENV_FILE HARNESS_INTEGRATION_ENV_FILE
}

reapply_operator_overrides() {
  if [ -n "$HARNESS_STATE_DIR_OPERATOR_SET" ]; then
    HARNESS_STATE_DIR="$HARNESS_STATE_DIR_OPERATOR_VALUE"
  fi
  if [ -n "$HARNESS_PRODUCT_HOME_DIR_OPERATOR_SET" ]; then
    HARNESS_PRODUCT_HOME_DIR="$HARNESS_PRODUCT_HOME_DIR_OPERATOR_VALUE"
  fi
  if [ -n "$HARNESS_STAGING_DIR_OPERATOR_SET" ]; then
    HARNESS_STAGING_DIR="$HARNESS_STAGING_DIR_OPERATOR_VALUE"
  fi
  if [ -n "$HARNESS_EVIDENCE_DIR_OPERATOR_SET" ]; then
    HARNESS_EVIDENCE_DIR="$HARNESS_EVIDENCE_DIR_OPERATOR_VALUE"
  fi
  if [ -n "$HARNESS_LOG_DIR_OPERATOR_SET" ]; then
    HARNESS_LOG_DIR="$HARNESS_LOG_DIR_OPERATOR_VALUE"
  fi
  if [ -n "$HARNESS_GERRIT_HTTP_HOST_PORT_OPERATOR_SET" ]; then
    HARNESS_GERRIT_HTTP_HOST_PORT="$HARNESS_GERRIT_HTTP_HOST_PORT_OPERATOR_VALUE"
  fi
  if [ -n "$HARNESS_JENKINS_HTTP_HOST_PORT_OPERATOR_SET" ]; then
    HARNESS_JENKINS_HTTP_HOST_PORT="$HARNESS_JENKINS_HTTP_HOST_PORT_OPERATOR_VALUE"
  fi
}

load_rendered_config_if_present() {
  local runtime
  runtime="${HARNESS_RUNTIME_ENV:-${HARNESS_RENDERED_ENV%.env}.runtime.env}"
  [ -f "$runtime" ] || return 1
  set -a
  # shellcheck disable=SC1090
  . "$runtime"
  set +a
  reapply_operator_overrides
  HARNESS_PRODUCT_HOME_DIR="${HARNESS_PRODUCT_HOME_DIR:-$repo_root/simulation/product-homes/docker/$HARNESS_RUN_ID}"
  if [ -n "$HARNESS_RENDERED_ENV_OPERATOR_SET" ]; then
    HARNESS_RENDERED_ENV="$HARNESS_RENDERED_ENV_OPERATOR_VALUE"
  else
    HARNESS_RENDERED_ENV="$HARNESS_STATE_DIR/rendered/harness.env"
  fi
  HARNESS_RUNTIME_ENV="${HARNESS_RENDERED_ENV%.env}.runtime.env"
  HARNESS_RUNTIME_INPUT_DIR="$HARNESS_STATE_DIR/rendered/runtime-inputs"
  if [ -n "$HARNESS_BASELINE_CONTRACT_OPERATOR_SET" ]; then
    HARNESS_BASELINE_CONTRACT="$HARNESS_BASELINE_CONTRACT_OPERATOR_VALUE"
  else
    HARNESS_BASELINE_CONTRACT="$HARNESS_STATE_DIR/rendered/artifact-manifest-contract.txt"
  fi
  export HARNESS_PRODUCT_HOME_DIR HARNESS_RENDERED_ENV HARNESS_RUNTIME_ENV HARNESS_RUNTIME_INPUT_DIR HARNESS_BASELINE_CONTRACT
}

ensure_runtime_config() {
  if [ -n "$HARNESS_RENDERED_ENV_OPERATOR_SET" ] && load_rendered_config_if_present; then
    return 0
  fi
  if load_rendered_config_if_present; then
    return 0
  fi
  die "Missing Docker harness runtime config: run render-config first"
}

bootstrap_harness_env() {
  load_env_file "$HARNESS_ENV_FILE"
}

load_harness_integration_env() {
  require_readable_file "Integration env file for Docker harness shared storage" "$HARNESS_INTEGRATION_ENV_FILE"
  set -a
  # shellcheck disable=SC1090
  . "$HARNESS_INTEGRATION_ENV_FILE"
  set +a
  HARNESS_JENKINS_SHARED_STORAGE_PATH="${JENKINS_SHARED_STORAGE_PATH:-}"
  validate_shared_storage_path "HARNESS_JENKINS_SHARED_STORAGE_PATH" "$HARNESS_JENKINS_SHARED_STORAGE_PATH"
  export HARNESS_JENKINS_SHARED_STORAGE_PATH
}

set_env_file_value() {
  local file name value tmp
  file="${1:?env file required}"
  name="${2:?env name required}"
  value="${3-}"
  tmp="$(mktemp "${file}.XXXXXX")"
  grep -v "^$name=" "$file" >"$tmp" || true
  printf '%s=%s\n' "$name" "$(shell_quote "$value")" >>"$tmp"
  chmod 0600 "$tmp"
  mv -- "$tmp" "$file"
}

copy_runtime_env_inputs_to() {
  local dest_dir
  dest_dir="${1:?destination required}"
  mkdir -p "$dest_dir"
  umask 077
  cp -- "$HARNESS_ENV_FILE" "$dest_dir/harness.env"
  cp -- "$HARNESS_GERRIT_ENV_FILE" "$dest_dir/gerrit.env"
  cp -- "$HARNESS_JENKINS_CONTROLLER_ENV_FILE" "$dest_dir/jenkins-controller.env"
  cp -- "$HARNESS_JENKINS_AGENT_ENV_FILE" "$dest_dir/jenkins-agent.env"
  cp -- "$HARNESS_INTEGRATION_ENV_FILE" "$dest_dir/integration.env"
  chmod 0600 "$dest_dir/"*.env
}

copy_runtime_env_inputs() {
  HARNESS_RUNTIME_INPUT_DIR="$HARNESS_STATE_DIR/rendered/runtime-inputs"
  rm -rf "$HARNESS_RUNTIME_INPUT_DIR"
  copy_runtime_env_inputs_to "$HARNESS_RUNTIME_INPUT_DIR"
  HARNESS_ENV_FILE="$HARNESS_RUNTIME_INPUT_DIR/harness.env"
  HARNESS_GERRIT_ENV_FILE="$HARNESS_RUNTIME_INPUT_DIR/gerrit.env"
  HARNESS_JENKINS_CONTROLLER_ENV_FILE="$HARNESS_RUNTIME_INPUT_DIR/jenkins-controller.env"
  HARNESS_JENKINS_AGENT_ENV_FILE="$HARNESS_RUNTIME_INPUT_DIR/jenkins-agent.env"
  HARNESS_INTEGRATION_ENV_FILE="$HARNESS_RUNTIME_INPUT_DIR/integration.env"
  set_env_file_value "$HARNESS_ENV_FILE" HARNESS_GERRIT_ENV_FILE "$HARNESS_GERRIT_ENV_FILE"
  set_env_file_value "$HARNESS_ENV_FILE" HARNESS_JENKINS_CONTROLLER_ENV_FILE "$HARNESS_JENKINS_CONTROLLER_ENV_FILE"
  set_env_file_value "$HARNESS_ENV_FILE" HARNESS_JENKINS_AGENT_ENV_FILE "$HARNESS_JENKINS_AGENT_ENV_FILE"
  set_env_file_value "$HARNESS_ENV_FILE" HARNESS_INTEGRATION_ENV_FILE "$HARNESS_INTEGRATION_ENV_FILE"
  export HARNESS_ENV_FILE HARNESS_RUNTIME_INPUT_DIR
  export HARNESS_GERRIT_ENV_FILE HARNESS_JENKINS_CONTROLLER_ENV_FILE
  export HARNESS_JENKINS_AGENT_ENV_FILE HARNESS_INTEGRATION_ENV_FILE
}

validate_render_config_inputs() {
  require_readable_file "HARNESS_ENV_FILE" "$HARNESS_ENV_FILE"
  require_readable_file "HARNESS_GERRIT_ENV_FILE" "$HARNESS_GERRIT_ENV_FILE"
  require_readable_file "HARNESS_JENKINS_CONTROLLER_ENV_FILE" "$HARNESS_JENKINS_CONTROLLER_ENV_FILE"
  require_readable_file "HARNESS_JENKINS_AGENT_ENV_FILE" "$HARNESS_JENKINS_AGENT_ENV_FILE"
  require_readable_file "HARNESS_INTEGRATION_ENV_FILE" "$HARNESS_INTEGRATION_ENV_FILE"
}

validate_absolute_mount_path() {
  local name value
  name="${1:?name required}"
  value="${2:?value required}"
  case "$value" in
    /*) ;;
    *) die "$name must be an absolute container mount path" ;;
  esac
  case "$value" in
    *[!A-Za-z0-9_./-]*|*"/../"*|*"/.."|"../"*|".."|*"//"*|*"/./"*|*"/.")
      die "$name contains unsafe mount path characters"
      ;;
  esac
}

validate_product_home_dir() {
  validate_absolute_mount_path HARNESS_PRODUCT_HOME_DIR "$HARNESS_PRODUCT_HOME_DIR"
  case "$HARNESS_PRODUCT_HOME_DIR" in
    "$HARNESS_STATE_DIR"|"$HARNESS_STATE_DIR"/*)
      die "HARNESS_PRODUCT_HOME_DIR must not be under HARNESS_STATE_DIR; product runtime homes are not harness state"
      ;;
  esac
}

validate_shared_storage_path() {
  local name value
  name="${1:?name required}"
  value="${2:?value required}"
  validate_absolute_mount_path "$name" "$value"
  case "$value" in
    /|/bin|/bin/*|/boot|/boot/*|/dev|/dev/*|/etc|/etc/*|/home|/home/*|/harness|/harness/*|/lib|/lib/*|/lib64|/lib64/*|/opt|/opt/*|/proc|/proc/*|/root|/root/*|/run|/run/*|/sbin|/sbin/*|/srv|/srv/*|/sys|/sys/*|/tmp|/tmp/*|/usr|/usr/*|/var|/var/*|/workspace|/workspace/*)
      die "$name must not target root, system, harness, workspace, or other reserved paths"
      ;;
  esac
  case "$value" in
    /mnt/*)
      [ "$value" != "/mnt/" ] || die "$name must include a directory below /mnt"
      ;;
    *)
      die "$name must use the approved /mnt/... prefix for v1 shared integration storage"
      ;;
  esac
}

detect_compose() {
  validate_harness_inputs
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

compose_v1_recreate_bug_detected() {
  local log
  log="${1:?log required}"
  [ "$compose_kind" = "docker-compose v1" ] || return 1
  grep -Eq "KeyError: 'ContainerConfig'|ERROR: .*'ContainerConfig'" "$log"
}

ensure_preflight_dirs() {
  validate_harness_inputs
  mkdir -p \
    "$HARNESS_EVIDENCE_DIR" \
    "$HARNESS_LOG_DIR"
}

ensure_dirs() {
  validate_harness_inputs
  validate_product_home_dir
  ensure_preflight_dirs
  mkdir -p \
    "$HARNESS_STATE_DIR" \
    "$HARNESS_PRODUCT_HOME_DIR" \
    "$HARNESS_PRODUCT_HOME_DIR/gerrit" \
    "$HARNESS_PRODUCT_HOME_DIR/jenkins-controller" \
    "$HARNESS_PRODUCT_HOME_DIR/jenkins-agent" \
    "$HARNESS_STAGING_DIR" \
    "$HARNESS_STATE_DIR/bundle-factory/artifacts" \
    "$HARNESS_STATE_DIR/bundle-factory/validation-public" \
    "$HARNESS_STATE_DIR/gerrit-validation-secrets" \
    "$HARNESS_STATE_DIR/shared-jenkins-storage" \
    "$HARNESS_STATE_DIR/rendered" \
    "$HARNESS_STAGING_DIR/gerrit" \
    "$HARNESS_STAGING_DIR/jenkins-controller" \
    "$HARNESS_STAGING_DIR/jenkins-agent"
  chmod 0700 "$HARNESS_STATE_DIR/gerrit-validation-secrets"
}

prepare_render_config() {
  validate_harness_inputs
  validate_render_config_inputs
  copy_runtime_env_inputs
  load_harness_integration_env
  ensure_dirs
  write_rendered_helper_envs
}

bounded_log_path() {
  local name
  name="${1:?log name required}"
  printf '%s/%s-%s.log' "$HARNESS_LOG_DIR" "$name" "$(timestamp_utc)"
}

validate_tcp_port_value() {
  local name value
  name="${1:?name required}"
  value="${2:?value required}"
  case "$value" in
    ''|*[!0-9]*)
      die "$name must be a numeric TCP port"
      ;;
  esac
  [ "$value" -ge 1 ] && [ "$value" -le 65535 ] ||
    die "$name must be between 1 and 65535"
}

loopback_port_owned_by_harness() {
  local service port container published
  service="${1:?service required}"
  port="${2:?port required}"
  command -v docker >/dev/null 2>&1 || return 1
  container="${HARNESS_PROJECT_NAME}-${service}"
  docker inspect "$container" >/dev/null 2>&1 || return 1
  published="$(docker inspect -f '{{range $p, $bindings := .NetworkSettings.Ports}}{{range $bindings}}{{if eq .HostIp "127.0.0.1"}}{{.HostPort}}{{"\n"}}{{end}}{{end}}{{end}}' "$container" 2>/dev/null || true)"
  printf '%s\n' "$published" | grep -Fxq "$port"
}

service_for_browser_port_name() {
  case "$1" in
    HARNESS_GERRIT_HTTP_HOST_PORT) printf '%s\n' gerrit-target ;;
    HARNESS_JENKINS_HTTP_HOST_PORT) printf '%s\n' jenkins-controller-target ;;
    *) die "Unknown browser port name: $1" ;;
  esac
}

can_bind_loopback_port() {
  local port
  port="${1:?port required}"
  python3 - "$port" <<'PY'
import socket
import sys

port = int(sys.argv[1])
with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(("127.0.0.1", port))
PY
}

require_loopback_port_available() {
  local name port
  name="${1:?name required}"
  port="${2:?port required}"
  validate_tcp_port_value "$name" "$port"
  can_bind_loopback_port "$port" ||
    die "$name is not available on 127.0.0.1: $port"
}

require_loopback_port_available_or_owned() {
  local name port service
  name="${1:?name required}"
  port="${2:?port required}"
  service="$(service_for_browser_port_name "$name")"
  validate_tcp_port_value "$name" "$port"
  if can_bind_loopback_port "$port" 2>/dev/null; then
    return 0
  fi
  loopback_port_owned_by_harness "$service" "$port" ||
    die "$name is not available on 127.0.0.1: $port"
}

choose_loopback_port() {
  python3 - <<'PY'
import socket

with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
    sock.bind(("127.0.0.1", 0))
    print(sock.getsockname()[1])
PY
}

rendered_env_value() {
  local name file
  name="${1:?name required}"
  file="${2:?file required}"
  [ -f "$file" ] || return 1
  sed -n "s/^$name=//p" "$file" | tail -1
}

resolve_browser_port() {
  local name requested persisted chosen other_port
  name="${1:?name required}"
  requested="${2:-}"
  other_port="${3:-}"

  if [ -n "$requested" ]; then
    require_loopback_port_available_or_owned "$name" "$requested"
    printf '%s\n' "$requested"
    return 0
  fi

  persisted="$(rendered_env_value "$name" "$HARNESS_RENDERED_ENV" || true)"
  if [ -n "$persisted" ]; then
    require_loopback_port_available_or_owned "$name" "$persisted"
    printf '%s\n' "$persisted"
    return 0
  fi

  while :; do
    chosen="$(choose_loopback_port)"
    require_loopback_port_available "$name" "$chosen"
    [ "$chosen" != "$other_port" ] || continue
    printf '%s\n' "$chosen"
    return 0
  done
}

resolve_browser_ports() {
  local gerrit_requested jenkins_requested
  gerrit_requested="${HARNESS_GERRIT_HTTP_HOST_PORT:-}"
  jenkins_requested="${HARNESS_JENKINS_HTTP_HOST_PORT:-}"

  HARNESS_GERRIT_HTTP_HOST_PORT="$(resolve_browser_port HARNESS_GERRIT_HTTP_HOST_PORT "$gerrit_requested" "")"
  HARNESS_JENKINS_HTTP_HOST_PORT="$(resolve_browser_port HARNESS_JENKINS_HTTP_HOST_PORT "$jenkins_requested" "$HARNESS_GERRIT_HTTP_HOST_PORT")"

  [ "$HARNESS_GERRIT_HTTP_HOST_PORT" != "$HARNESS_JENKINS_HTTP_HOST_PORT" ] ||
    die "HARNESS_GERRIT_HTTP_HOST_PORT and HARNESS_JENKINS_HTTP_HOST_PORT must be different"

  export HARNESS_GERRIT_HTTP_HOST_PORT HARNESS_JENKINS_HTTP_HOST_PORT
}

service_for_role() {
  case "${1:-}" in
    gerrit) printf '%s\n' gerrit-target ;;
    jenkins-controller) printf '%s\n' jenkins-controller-target ;;
    jenkins-agent) printf '%s\n' jenkins-agent-target ;;
    *) die "Unknown role '${1:-}'; expected gerrit, jenkins-controller, or jenkins-agent" ;;
  esac
}

helper_for_role() {
  case "${1:-}" in
    gerrit) printf '%s\n' scripts/gerrit-setup.sh ;;
    jenkins-controller) printf '%s\n' scripts/jenkins-controller-setup.sh ;;
    jenkins-agent) printf '%s\n' scripts/jenkins-agent-setup.sh ;;
    *) die "Unknown role '${1:-}'; expected gerrit, jenkins-controller, or jenkins-agent" ;;
  esac
}

parse_role() {
  local role=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --role)
        [ "$#" -ge 2 ] || die "--role requires a value"
        role="$2"
        shift 2
        ;;
      --role=*)
        role="${1#--role=}"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown option for role-scoped command: $1"
        ;;
    esac
  done

  [ -n "$role" ] || die "Missing --role; expected gerrit, jenkins-controller, or jenkins-agent"
  service_for_role "$role" >/dev/null
  printf '%s\n' "$role"
}

parse_optional_role() {
  local role=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --role)
        [ "$#" -ge 2 ] || die "--role requires a value"
        role="$2"
        shift 2
        ;;
      --role=*)
        role="${1#--role=}"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown option for role command: $1"
        ;;
    esac
  done

  if [ -n "$role" ]; then
    service_for_role "$role" >/dev/null
  fi
  printf '%s\n' "$role"
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
    run-role-gate) output="$(cmd_run_role_gate "$role")" || rc=$? ;;
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

json_quote() {
  local value
  value="${1-}"
  require_command python3
  python3 -c 'import json, sys; print(json.dumps(sys.argv[1]))' "$value"
}

shell_quote() {
  local value
  value="${1-}"
  printf '%q' "$value"
}

target_container_for_evidence() {
  local role
  role="${1:?role required}"
  case "$role" in
    gerrit|jenkins-controller|jenkins-agent)
      printf '%s-%s\n' "$HARNESS_PROJECT_NAME" "$(service_for_role "$role")"
      ;;
    *)
      printf '%s\n' "not-applicable"
      ;;
  esac
}

manifest_reference_for_evidence() {
  local role
  role="${1:?role required}"
  case "$role" in
    gerrit|jenkins-controller|jenkins-agent)
      printf '%s/bundle-factory/artifacts/%s/manifest.txt\n' "$HARNESS_STATE_DIR" "$role"
      ;;
    *)
      printf '%s\n' "not-applicable"
      ;;
  esac
}

checksum_reference_for_evidence() {
  local role
  role="${1:?role required}"
  case "$role" in
    gerrit|jenkins-controller|jenkins-agent)
      printf '%s/bundle-factory/artifacts/%s/checksums.sha256\n' "$HARNESS_STATE_DIR" "$role"
      ;;
    *)
      printf '%s\n' "not-applicable"
      ;;
  esac
}

ensure_gerrit_validation_key() {
  local log private_key public_key bundle_public_key secret_dir
  log="${1:?log required}"
  secret_dir="$HARNESS_STATE_DIR/gerrit-validation-secrets"
  private_key="$HARNESS_STATE_DIR/gerrit-validation-secrets/jenkins-gerrit"
  public_key="$HARNESS_STATE_DIR/gerrit-validation-secrets/jenkins-gerrit.pub"
  bundle_public_key="$HARNESS_STATE_DIR/bundle-factory/validation-public/jenkins-gerrit.pub"
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

ensure_gerrit_ldap_bind_secret() {
  local log secret_file secret_dir
  log="${1:?log required}"
  secret_dir="$HARNESS_STATE_DIR/gerrit-validation-secrets"
  secret_file="$HARNESS_STATE_DIR/gerrit-validation-secrets/ldap-bind-password"
  if [ -d "$secret_dir" ] && [ ! -w "$secret_dir" ]; then
    rm -rf "$secret_dir"
  fi
  mkdir -p "$secret_dir"
  chmod 0700 "$secret_dir"
  printf '%s' "$HARNESS_LDAP_BIND_PASSWORD" >"$secret_file"
  chmod 0600 "$secret_file"
  printf 'validation_secret_ready role=gerrit secret_kind=ldap-bind-password custody=harness-owned-simulation-not-gerrit-artifact public_value_redacted=true\n' >>"$log"
}

gerrit_target_secret_env() {
  printf '%s\n' "LDAP_BIND_PASSWORD_FILE=/harness/validation-secrets/ldap-bind-password"
}

reset_gerrit_site_state() {
  local service log
  service="${1:?service required}"
  log="${2:?log required}"
  compose exec -T -u root "$service" sh -lc '
    pidfile=/srv/gerrit/logs/gerrit.pid
    pids="$(ps -eo pid=,args= | awk '\''index($0, "/srv/gerrit") && (index($0, "GerritCodeReview") || index($0, "gerrit.war")) {print $1}'\'')"
    if [ -n "$pids" ]; then
      kill $pids 2>/dev/null || true
      sleep 2
      kill -9 $pids 2>/dev/null || true
    fi
    if [ -s "$pidfile" ]; then
      pid="$(cat "$pidfile" 2>/dev/null || true)"
      if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
        sleep 2
        kill -9 "$pid" 2>/dev/null || true
      fi
    fi
    if [ -x /srv/gerrit/bin/gerrit.sh ]; then
      timeout 10 su -s /bin/sh gerrit -c "/srv/gerrit/bin/gerrit.sh stop" >/dev/null 2>&1 || true
    fi
    rm -rf /srv/gerrit
    mkdir -p /srv/gerrit
  ' >>"$log" 2>&1
  printf 'site_reset role=gerrit path=%s reason=clean-step7-role-gate-runtime-state\n' "/srv/gerrit" >>"$log"
}

gerrit_bundle_factory_env_file() {
  printf '%s\n' "/harness/state/rendered/gerrit-bundle-factory.env"
}

jenkins_controller_bundle_factory_env_file() {
  printf '%s\n' "/harness/state/rendered/jenkins-controller-bundle-factory.env"
}

container_env_file_for_role() {
  local role
  role="${1:?role required}"
  printf '/harness/state/rendered/%s.env\n' "$role"
}

host_container_env_file_for_role() {
  local role service
  role="${1:?role required}"
  service="${2:?service required}"
  printf '%s/rendered/%s.env\n' "$(host_state_dir_for_service "$service")" "$role"
}

host_gerrit_bundle_factory_env_file() {
  printf '%s/bundle-factory/rendered/gerrit-bundle-factory.env\n' "$HARNESS_STATE_DIR"
}

host_jenkins_controller_bundle_factory_env_file() {
  printf '%s/bundle-factory/rendered/jenkins-controller-bundle-factory.env\n' "$HARNESS_STATE_DIR"
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
  local role service src host_env_file container_env_file
  role="${1:?role required}"
  service="${2:?service required}"
  src="$(source_env_file_for_role "$role")"
  require_readable_file "Harness $role env file" "$src"
  container_env_file="$(container_env_file_for_role "$role")"
  host_env_file="$(host_container_env_file_for_role "$role" "$service")"
  mkdir -p "$(dirname "$host_env_file")"
  case "$role" in
    gerrit)
      sed -e 's|^GERRIT_SITE_PATH=.*|GERRIT_SITE_PATH="/srv/gerrit"|' \
        "$src" >"$host_env_file"
      ;;
    jenkins-controller)
      sed -e 's|^JENKINS_HOME=.*|JENKINS_HOME="/var/lib/jenkins"|' \
        "$src" >"$host_env_file"
      ;;
    jenkins-agent)
      sed -e 's|^JENKINS_AGENT_REMOTE_FS=.*|JENKINS_AGENT_REMOTE_FS="/var/lib/jenkins-agent"|' \
        "$src" >"$host_env_file"
      ;;
    *)
      cp -- "$src" "$host_env_file"
      ;;
  esac
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
  sed \
    -e 's|^GERRIT_DOWNLOAD_ARTIFACTS=.*|GERRIT_DOWNLOAD_ARTIFACTS="1"|' \
    "$src" >"$host_env_file"
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
  sed \
    -e 's|^JENKINS_DOWNLOAD_ARTIFACTS=.*|JENKINS_DOWNLOAD_ARTIFACTS="1"|' \
    "$src" >"$host_env_file"
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
  require_readable_file "Rendered $role env file; run render-config first" "$host_env_file"
  printf '%s\n' "$(container_env_file_for_role "$role")"
}

prepare_product_home_ownership() {
  local role service host_env_file path account group log
  role="${1:?role required}"
  service="${2:?service required}"
  log="${3:?log required}"
  host_env_file="$(host_container_env_file_for_role "$role" "$service")"
  require_readable_file "Rendered $role env file; run render-config first" "$host_env_file"
  case "$role" in
    gerrit)
      path="/srv/gerrit"
      account="$(env_file_value "$host_env_file" GERRIT_RUNTIME_ACCOUNT)"
      group="$(env_file_value "$host_env_file" GERRIT_RUNTIME_GROUP)"
      ;;
    jenkins-controller)
      path="/var/lib/jenkins"
      account="$(env_file_value "$host_env_file" JENKINS_RUNTIME_ACCOUNT)"
      group="$(env_file_value "$host_env_file" JENKINS_RUNTIME_GROUP)"
      ;;
    jenkins-agent)
      path="/var/lib/jenkins-agent"
      account="$(env_file_value "$host_env_file" JENKINS_AGENT_ACCOUNT)"
      group="$(env_file_value "$host_env_file" JENKINS_AGENT_GROUP)"
      ;;
    *)
      die "Unknown role '$role'; expected gerrit, jenkins-controller, or jenkins-agent"
      ;;
  esac
  compose exec -T "$service" sh -c "mkdir -p $(shell_quote "$path") && chown -R $(shell_quote "$account:$group") $(shell_quote "$path")" >>"$log" 2>&1
  printf 'product_home_ownership_prepared role=%s service=%s path=%s owner=%s group=%s\n' \
    "$role" "$service" "$path" "$account" "$group" >>"$log"
}

require_gerrit_bundle_factory_env() {
  require_readable_file \
    "Rendered Gerrit bundle factory env file; run render-config first" \
    "$(host_gerrit_bundle_factory_env_file)"
  gerrit_bundle_factory_env_file
}

require_jenkins_controller_bundle_factory_env() {
  require_readable_file \
    "Rendered Jenkins controller bundle factory env file; run render-config first" \
    "$(host_jenkins_controller_bundle_factory_env_file)"
  jenkins_controller_bundle_factory_env_file
}

manifest_get() {
  local key manifest
  key="${1:?key required}"
  manifest="${2:?manifest required}"
  awk -F= -v key="$key" '
    $1 == key {
      print substr($0, length(key) + 2)
      found = 1
      exit
    }
    END {
      if (!found) {
        exit 1
      }
    }
  ' "$manifest"
}

env_file_value() {
  local file key
  file="${1:?file required}"
  key="${2:?key required}"
  awk -F= -v key="$key" '
    $1 == key {
      value = substr($0, length(key) + 2)
      gsub(/^"/, "", value)
      gsub(/"$/, "", value)
      print value
      found = 1
      exit
    }
    END {
      if (!found) {
        exit 1
      }
    }
  ' "$file"
}

validate_manifest_value() {
  local role manifest log key expected actual
  role="${1:?role required}"
  manifest="${2:?manifest required}"
  log="${3:?log required}"
  key="${4:?key required}"
  expected="${5:?expected required}"

  if ! actual="$(manifest_get "$key" "$manifest")"; then
    printf 'baseline_drift role=%s field=%s expected=%s actual=<missing> manifest=%s\n' \
      "$role" "$key" "$expected" "$manifest" >>"$log"
    return 1
  fi

  if [ "$actual" != "$expected" ]; then
    printf 'baseline_drift role=%s field=%s expected=%s actual=%s manifest=%s\n' \
      "$role" "$key" "$expected" "$actual" "$manifest" >>"$log"
    return 1
  fi
}

validate_role_baseline_manifest() {
  local role manifest log
  role="${1:?role required}"
  manifest="${2:?manifest required}"
  log="${3:?log required}"

  if [ ! -f "$manifest" ]; then
    printf 'baseline_drift role=%s field=manifest expected=present actual=missing manifest=%s\n' \
      "$role" "$manifest" >>"$log"
    return 1
  fi

  validate_manifest_value "$role" "$manifest" "$log" "harness_manifest_version" "1" || return 1
  validate_manifest_value "$role" "$manifest" "$log" "role" "$role" || return 1
  validate_manifest_value "$role" "$manifest" "$log" "ubuntu_release" "$HARNESS_UBUNTU_BASELINE_RELEASE" || return 1
  validate_manifest_value "$role" "$manifest" "$log" "ubuntu_codename" "$HARNESS_UBUNTU_BASELINE_CODENAME" || return 1
  validate_manifest_value "$role" "$manifest" "$log" "java_version" "$HARNESS_JAVA_BASELINE" || return 1
  validate_manifest_value "$role" "$manifest" "$log" "artifact_source" "curated-bundle-factory" || return 1
  validate_manifest_value "$role" "$manifest" "$log" "os_dependency_source" "approved-internal-os-repos" || return 1
  validate_manifest_value "$role" "$manifest" "$log" "public_internet_fallback" "simulation-only" || return 1
  validate_manifest_value "$role" "$manifest" "$log" "bundle_contains_keys" "no" || return 1

  case "$role" in
    gerrit)
      validate_manifest_value "$role" "$manifest" "$log" "gerrit_version" "$HARNESS_GERRIT_BASELINE" || return 1
      validate_manifest_value "$role" "$manifest" "$log" "jenkins_version" "not-applicable" || return 1
      validate_manifest_value "$role" "$manifest" "$log" "jenkins_plugin_manager_version" "not-applicable" || return 1
      ;;
    jenkins-controller)
      validate_manifest_value "$role" "$manifest" "$log" "gerrit_version" "not-applicable" || return 1
      validate_manifest_value "$role" "$manifest" "$log" "jenkins_version" "$HARNESS_JENKINS_BASELINE" || return 1
      validate_manifest_value "$role" "$manifest" "$log" "jenkins_plugin_manager_version" "$HARNESS_JENKINS_PLUGIN_MANAGER_BASELINE" || return 1
      ;;
    jenkins-agent)
      validate_manifest_value "$role" "$manifest" "$log" "gerrit_version" "not-applicable" || return 1
      validate_manifest_value "$role" "$manifest" "$log" "jenkins_version" "not-applicable" || return 1
      validate_manifest_value "$role" "$manifest" "$log" "jenkins_plugin_manager_version" "not-applicable" || return 1
      ;;
    *)
      die "Unknown role '$role'; expected gerrit, jenkins-controller, or jenkins-agent"
      ;;
  esac

  printf 'baseline_ok role=%s manifest=%s\n' "$role" "$manifest" >>"$log"
}

write_evidence() {
  local checkpoint role status command_name log_ref message file
  local manifest_ref checksum_ref target_container
  local q_mode q_timestamp q_role q_checkpoint q_command q_status q_input
  local q_manifest q_checksum q_message q_log_ref q_redaction q_role_name
  local q_bundle_container q_ldap_container q_target_container
  local q_ubuntu_target q_ubuntu_release q_ubuntu_codename q_java q_gerrit
  local q_jenkins q_plugin_manager q_source_boundary
  checkpoint="${1:?checkpoint required}"
  role="${2:?role required}"
  status="${3:?status required}"
  command_name="${4:?command required}"
  log_ref="${5:-not-applicable}"
  message="${6:-}"

  validate_harness_inputs
  if [ "$checkpoint" = "preflight" ]; then
    ensure_preflight_dirs
  else
    ensure_dirs
  fi
  file="$HARNESS_EVIDENCE_DIR/${checkpoint}-${role}-$(timestamp_utc).json"
  manifest_ref="$(manifest_reference_for_evidence "$role")"
  checksum_ref="$(checksum_reference_for_evidence "$role")"
  target_container="$(target_container_for_evidence "$role")"
  q_mode="$(json_quote "$HARNESS_MODE")"
  q_timestamp="$(json_quote "$(iso_timestamp_utc)")"
  q_role="$(json_quote "$role")"
  q_checkpoint="$(json_quote "$checkpoint")"
  q_command="$(json_quote "$command_name")"
  q_status="$(json_quote "$status")"
  q_input="$(json_quote "not-applicable")"
  q_manifest="$(json_quote "$manifest_ref")"
  q_checksum="$(json_quote "$checksum_ref")"
  q_message="$(json_quote "$message")"
  q_log_ref="$(json_quote "$log_ref")"
  q_redaction="$(json_quote "secrets-not-recorded")"
  q_role_name="$(json_quote "$role")"
  q_bundle_container="$(json_quote "$HARNESS_PROJECT_NAME-bundle-factory")"
  q_ldap_container="$(json_quote "$HARNESS_PROJECT_NAME-ldap")"
  q_target_container="$(json_quote "$target_container")"
  q_ubuntu_target="$(json_quote "$HARNESS_UBUNTU_BASELINE_VERSION")"
  q_ubuntu_release="$(json_quote "$HARNESS_UBUNTU_BASELINE_RELEASE")"
  q_ubuntu_codename="$(json_quote "$HARNESS_UBUNTU_BASELINE_CODENAME")"
  q_java="$(json_quote "$HARNESS_JAVA_BASELINE")"
  q_gerrit="$(json_quote "$HARNESS_GERRIT_BASELINE")"
  q_jenkins="$(json_quote "$HARNESS_JENKINS_BASELINE")"
  q_plugin_manager="$(json_quote "$HARNESS_JENKINS_PLUGIN_MANAGER_BASELINE")"
  q_source_boundary="$(json_quote "Application artifacts are prepared in bundle factory and staged to targets; target-host public internet fallback is simulation-only for Ubuntu/OS dependencies.")"

  cat >"$file" <<EOF
{
  "verification_mode": $q_mode,
  "timestamp": $q_timestamp,
  "role_or_environment": $q_role,
  "checkpoint_name": $q_checkpoint,
  "command_name": $q_command,
  "status": $q_status,
  "reviewed_input_fingerprint": $q_input,
  "artifact_manifest_references": $q_manifest,
  "checksum_references": $q_checksum,
  "observed_checks": $q_message,
  "bounded_log_references": $q_log_ref,
  "redaction_status": $q_redaction,
  "mode_labels": ["docker-simulation", "simulation-only"],
  "role_name": $q_role_name,
  "container_names": {
    "bundle_factory": $q_bundle_container,
    "ldap": $q_ldap_container,
    "target": $q_target_container
  },
  "version_baseline": {
    "ubuntu_target": $q_ubuntu_target,
    "ubuntu_release": $q_ubuntu_release,
    "ubuntu_codename": $q_ubuntu_codename,
    "java": $q_java,
    "gerrit": $q_gerrit,
    "jenkins_controller": $q_jenkins,
    "jenkins_plugin_manager": $q_plugin_manager
  },
  "source_boundary": $q_source_boundary
}
EOF
  printf '%s\n' "$file"
}

write_rendered_env() {
  prepare_render_config
  require_command python3
  resolve_browser_ports
  cat >"$HARNESS_RENDERED_ENV" <<EOF
HARNESS_ENV_FILE=$(shell_quote "$HARNESS_ENV_FILE")
HARNESS_MODE=$(shell_quote "$HARNESS_MODE")
HARNESS_RUN_ID=$(shell_quote "$HARNESS_RUN_ID")
HARNESS_PROJECT_NAME=$(shell_quote "$HARNESS_PROJECT_NAME")
HARNESS_UBUNTU_IMAGE=$(shell_quote "$HARNESS_UBUNTU_IMAGE")
HARNESS_UBUNTU_BASELINE_VERSION=$(shell_quote "$HARNESS_UBUNTU_BASELINE_VERSION")
HARNESS_UBUNTU_BASELINE_RELEASE=$(shell_quote "$HARNESS_UBUNTU_BASELINE_RELEASE")
HARNESS_UBUNTU_BASELINE_CODENAME=$(shell_quote "$HARNESS_UBUNTU_BASELINE_CODENAME")
HARNESS_JAVA_BASELINE=$(shell_quote "$HARNESS_JAVA_BASELINE")
HARNESS_GERRIT_BASELINE=$(shell_quote "$HARNESS_GERRIT_BASELINE")
HARNESS_JENKINS_BASELINE=$(shell_quote "$HARNESS_JENKINS_BASELINE")
HARNESS_JENKINS_PLUGIN_MANAGER_BASELINE=$(shell_quote "$HARNESS_JENKINS_PLUGIN_MANAGER_BASELINE")
HARNESS_LDAP_IMAGE=$(shell_quote "$HARNESS_LDAP_IMAGE")
HARNESS_LDAP_DOMAIN=$(shell_quote "$HARNESS_LDAP_DOMAIN")
HARNESS_LDAP_BASE_DN=$(shell_quote "$HARNESS_LDAP_BASE_DN")
HARNESS_LDAP_ADMIN_PASSWORD=$(shell_quote "<redacted>")
HARNESS_LDAP_CONFIG_PASSWORD=$(shell_quote "<redacted>")
HARNESS_LDAP_BIND_USER=$(shell_quote "$HARNESS_LDAP_BIND_USER")
HARNESS_LDAP_BIND_PASSWORD=$(shell_quote "<redacted>")
HARNESS_PUBLIC_INTERNET_FALLBACK_LABEL=$(shell_quote "$HARNESS_PUBLIC_INTERNET_FALLBACK_LABEL")
HARNESS_STATE_DIR=$(shell_quote "$HARNESS_STATE_DIR")
HARNESS_PRODUCT_HOME_DIR=$(shell_quote "$HARNESS_PRODUCT_HOME_DIR")
HARNESS_STAGING_DIR=$(shell_quote "$HARNESS_STAGING_DIR")
HARNESS_EVIDENCE_DIR=$(shell_quote "$HARNESS_EVIDENCE_DIR")
HARNESS_LOG_DIR=$(shell_quote "$HARNESS_LOG_DIR")
HARNESS_INTEGRATION_ENV_FILE=$(shell_quote "$HARNESS_INTEGRATION_ENV_FILE")
HARNESS_GERRIT_ENV_FILE=$(shell_quote "$HARNESS_GERRIT_ENV_FILE")
HARNESS_JENKINS_CONTROLLER_ENV_FILE=$(shell_quote "$HARNESS_JENKINS_CONTROLLER_ENV_FILE")
HARNESS_JENKINS_AGENT_ENV_FILE=$(shell_quote "$HARNESS_JENKINS_AGENT_ENV_FILE")
HARNESS_JENKINS_SHARED_STORAGE_PATH=$(shell_quote "$HARNESS_JENKINS_SHARED_STORAGE_PATH")
HARNESS_GERRIT_HTTP_HOST_PORT=$(shell_quote "$HARNESS_GERRIT_HTTP_HOST_PORT")
HARNESS_JENKINS_HTTP_HOST_PORT=$(shell_quote "$HARNESS_JENKINS_HTTP_HOST_PORT")
HARNESS_GERRIT_BROWSER_URL=$(shell_quote "http://127.0.0.1:$HARNESS_GERRIT_HTTP_HOST_PORT/")
HARNESS_JENKINS_BROWSER_URL=$(shell_quote "http://127.0.0.1:$HARNESS_JENKINS_HTTP_HOST_PORT/login")
public_internet_fallback=simulation-only
gerrit_env=$(shell_quote "$HARNESS_GERRIT_ENV_FILE")
jenkins_controller_env=$(shell_quote "$HARNESS_JENKINS_CONTROLLER_ENV_FILE")
jenkins_agent_env=$(shell_quote "$HARNESS_JENKINS_AGENT_ENV_FILE")
integration_env=$(shell_quote "$HARNESS_INTEGRATION_ENV_FILE")
EOF
  write_runtime_env
  write_manifest_contract
}

write_runtime_env() {
  umask 077
  cat >"$HARNESS_RUNTIME_ENV" <<EOF
HARNESS_ENV_FILE=$(shell_quote "$HARNESS_ENV_FILE")
HARNESS_MODE=$(shell_quote "$HARNESS_MODE")
HARNESS_RUN_ID=$(shell_quote "$HARNESS_RUN_ID")
HARNESS_PROJECT_NAME=$(shell_quote "$HARNESS_PROJECT_NAME")
HARNESS_UBUNTU_IMAGE=$(shell_quote "$HARNESS_UBUNTU_IMAGE")
HARNESS_UBUNTU_BASELINE_VERSION=$(shell_quote "$HARNESS_UBUNTU_BASELINE_VERSION")
HARNESS_UBUNTU_BASELINE_RELEASE=$(shell_quote "$HARNESS_UBUNTU_BASELINE_RELEASE")
HARNESS_UBUNTU_BASELINE_CODENAME=$(shell_quote "$HARNESS_UBUNTU_BASELINE_CODENAME")
HARNESS_JAVA_BASELINE=$(shell_quote "$HARNESS_JAVA_BASELINE")
HARNESS_GERRIT_BASELINE=$(shell_quote "$HARNESS_GERRIT_BASELINE")
HARNESS_JENKINS_BASELINE=$(shell_quote "$HARNESS_JENKINS_BASELINE")
HARNESS_JENKINS_PLUGIN_MANAGER_BASELINE=$(shell_quote "$HARNESS_JENKINS_PLUGIN_MANAGER_BASELINE")
HARNESS_LDAP_IMAGE=$(shell_quote "$HARNESS_LDAP_IMAGE")
HARNESS_LDAP_DOMAIN=$(shell_quote "$HARNESS_LDAP_DOMAIN")
HARNESS_LDAP_BASE_DN=$(shell_quote "$HARNESS_LDAP_BASE_DN")
HARNESS_LDAP_ADMIN_PASSWORD=$(shell_quote "$HARNESS_LDAP_ADMIN_PASSWORD")
HARNESS_LDAP_CONFIG_PASSWORD=$(shell_quote "$HARNESS_LDAP_CONFIG_PASSWORD")
HARNESS_LDAP_BIND_USER=$(shell_quote "$HARNESS_LDAP_BIND_USER")
HARNESS_LDAP_BIND_PASSWORD=$(shell_quote "$HARNESS_LDAP_BIND_PASSWORD")
HARNESS_PUBLIC_INTERNET_FALLBACK_LABEL=$(shell_quote "$HARNESS_PUBLIC_INTERNET_FALLBACK_LABEL")
HARNESS_STATE_DIR=$(shell_quote "$HARNESS_STATE_DIR")
HARNESS_PRODUCT_HOME_DIR=$(shell_quote "$HARNESS_PRODUCT_HOME_DIR")
HARNESS_STAGING_DIR=$(shell_quote "$HARNESS_STAGING_DIR")
HARNESS_EVIDENCE_DIR=$(shell_quote "$HARNESS_EVIDENCE_DIR")
HARNESS_LOG_DIR=$(shell_quote "$HARNESS_LOG_DIR")
HARNESS_INTEGRATION_ENV_FILE=$(shell_quote "$HARNESS_INTEGRATION_ENV_FILE")
HARNESS_GERRIT_ENV_FILE=$(shell_quote "$HARNESS_GERRIT_ENV_FILE")
HARNESS_JENKINS_CONTROLLER_ENV_FILE=$(shell_quote "$HARNESS_JENKINS_CONTROLLER_ENV_FILE")
HARNESS_JENKINS_AGENT_ENV_FILE=$(shell_quote "$HARNESS_JENKINS_AGENT_ENV_FILE")
HARNESS_JENKINS_SHARED_STORAGE_PATH=$(shell_quote "$HARNESS_JENKINS_SHARED_STORAGE_PATH")
HARNESS_GERRIT_HTTP_HOST_PORT=$(shell_quote "$HARNESS_GERRIT_HTTP_HOST_PORT")
HARNESS_JENKINS_HTTP_HOST_PORT=$(shell_quote "$HARNESS_JENKINS_HTTP_HOST_PORT")
HARNESS_GERRIT_BROWSER_URL=$(shell_quote "http://127.0.0.1:$HARNESS_GERRIT_HTTP_HOST_PORT/")
HARNESS_JENKINS_BROWSER_URL=$(shell_quote "http://127.0.0.1:$HARNESS_JENKINS_HTTP_HOST_PORT/login")
HARNESS_RENDERED_ENV=$(shell_quote "$HARNESS_RENDERED_ENV")
HARNESS_RUNTIME_ENV=$(shell_quote "$HARNESS_RUNTIME_ENV")
HARNESS_RUNTIME_INPUT_DIR=$(shell_quote "$HARNESS_RUNTIME_INPUT_DIR")
HARNESS_BASELINE_CONTRACT=$(shell_quote "$HARNESS_BASELINE_CONTRACT")
public_internet_fallback=simulation-only
gerrit_env=$(shell_quote "$HARNESS_GERRIT_ENV_FILE")
jenkins_controller_env=$(shell_quote "$HARNESS_JENKINS_CONTROLLER_ENV_FILE")
jenkins_agent_env=$(shell_quote "$HARNESS_JENKINS_AGENT_ENV_FILE")
integration_env=$(shell_quote "$HARNESS_INTEGRATION_ENV_FILE")
EOF
  chmod 0600 "$HARNESS_RUNTIME_ENV"
}

write_manifest_contract() {
  ensure_dirs
  cat >"$HARNESS_BASELINE_CONTRACT" <<EOF
# Required artifact manifest contract for Docker harness role gates.
# Format is exact key=value, one field per line.
# Missing or drifted fields block comparable readiness.

[common]
harness_manifest_version=1
role=<gerrit|jenkins-controller|jenkins-agent>
ubuntu_release=$HARNESS_UBUNTU_BASELINE_RELEASE
ubuntu_codename=$HARNESS_UBUNTU_BASELINE_CODENAME
java_version=$HARNESS_JAVA_BASELINE

[gerrit]
gerrit_version=$HARNESS_GERRIT_BASELINE
jenkins_version=not-applicable
jenkins_plugin_manager_version=not-applicable

[jenkins-controller]
gerrit_version=not-applicable
jenkins_version=$HARNESS_JENKINS_BASELINE
jenkins_plugin_manager_version=$HARNESS_JENKINS_PLUGIN_MANAGER_BASELINE

[jenkins-agent]
gerrit_version=not-applicable
jenkins_version=not-applicable
jenkins_plugin_manager_version=not-applicable
EOF
}

require_baseline_label() {
  [ "$HARNESS_PUBLIC_INTERNET_FALLBACK_LABEL" = "simulation-only" ] ||
    die "Public internet fallback label must be simulation-only"
  [ "$HARNESS_UBUNTU_BASELINE_RELEASE" = "24.04" ] ||
    die "Ubuntu baseline release drifted from 24.04"
  [ "$HARNESS_UBUNTU_BASELINE_CODENAME" = "noble" ] ||
    die "Ubuntu baseline codename drifted from noble"
  [ "$HARNESS_JAVA_BASELINE" = "21" ] ||
    die "Java baseline drifted from OpenJDK 21"
  [ "$HARNESS_GERRIT_BASELINE" = "3.13.6" ] ||
    die "Gerrit baseline drifted from 3.13.6"
  [ "$HARNESS_JENKINS_BASELINE" = "2.555.3" ] ||
    die "Jenkins baseline drifted from 2.555.3"
  [ "$HARNESS_JENKINS_PLUGIN_MANAGER_BASELINE" = "2.15.0" ] ||
    die "Jenkins Plugin Installation Manager baseline drifted from 2.15.0"
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
  [ -n "$container_id" ] || die "Harness service '$service' is not created; run up first"
  running="$(docker inspect -f '{{.State.Running}}' "$container_id" 2>/dev/null || true)"
  [ "$running" = "true" ] || die "Harness service '$service' is not running; run up first"
}

running_loopback_port_for_service() {
  local service container_id port
  service="${1:?service required}"
  container_id="$(container_id_for_service "$service")"
  [ -n "$container_id" ] || die "Harness service '$service' is not created; run up first"
  port="$(docker inspect -f '{{range $p, $bindings := .NetworkSettings.Ports}}{{range $bindings}}{{if eq .HostIp "127.0.0.1"}}{{.HostPort}}{{"\n"}}{{end}}{{end}}{{end}}' "$container_id" 2>/dev/null | sed -n '1p')"
  [ -n "$port" ] || die "Harness service '$service' has no published loopback port"
  printf '%s\n' "$port"
}

ensure_harness_up_for_role() {
  local service
  service="${1:?service required}"
  if ! container_id_for_service "$service" >/dev/null 2>&1 ||
    [ -z "$(container_id_for_service "$service")" ]; then
    cmd_up >/dev/null
    return 0
  fi
  if ! docker inspect -f '{{.State.Running}}' "$(container_id_for_service "$service")" 2>/dev/null | grep -qx true; then
    cmd_up >/dev/null
  fi
}

check_target_os_release() {
  local role service log os_release os_codename evidence
  role="${1:?role required}"
  service="$(service_for_role "$role")"
  log="$(bounded_log_path "os-release-$role")"

  if ! compose exec -T "$service" sh -c '. /etc/os-release && printf "%s %s\n" "$VERSION_ID" "$VERSION_CODENAME"' >"$log" 2>&1; then
    evidence="$(write_evidence os-release "$role" fail "simulate.sh run-role-gate" "$log" "Could not read target OS release")"
    die "Failed to read OS release for $role; evidence=$evidence log=$log"
  fi

  os_release="$(awk '{print $1}' "$log")"
  os_codename="$(awk '{print $2}' "$log")"
  if [ "$os_release" != "$HARNESS_UBUNTU_BASELINE_RELEASE" ] || [ "$os_codename" != "$HARNESS_UBUNTU_BASELINE_CODENAME" ]; then
    evidence="$(write_evidence os-release "$role" blocked "simulate.sh run-role-gate" "$log" "Target OS $os_release $os_codename does not match Version Baseline")"
    die "Target OS drift for $role; expected $HARNESS_UBUNTU_BASELINE_RELEASE $HARNESS_UBUNTU_BASELINE_CODENAME, evidence=$evidence log=$log"
  fi

  write_evidence os-release "$role" pass "simulate.sh run-role-gate" "$log" "Target OS release matches Version Baseline" >/dev/null
}

check_ubuntu_service_baseline() {
  local service label log os_release os_codename image_id evidence
  service="${1:?service required}"
  label="${2:?label required}"
  log="$(bounded_log_path "baseline-$label")"

  require_running_service "$service"
  if ! compose exec -T "$service" sh -c '. /etc/os-release && printf "release=%s codename=%s pretty=%s\n" "$VERSION_ID" "$VERSION_CODENAME" "$PRETTY_NAME"' >"$log" 2>&1; then
    evidence="$(write_evidence baseline "$label" fail "simulate.sh up" "$log" "Could not read container OS release")"
    die "Failed to read OS release for $label; evidence=$evidence log=$log"
  fi

  os_release="$(sed -n 's/^release=\([^ ]*\).*/\1/p' "$log")"
  os_codename="$(sed -n 's/^.*codename=\([^ ]*\).*/\1/p' "$log")"
  image_id="$(docker inspect -f '{{.Image}}' "$(container_id_for_service "$service")" 2>/dev/null || printf 'unknown')"
  printf 'image_id=%s\n' "$image_id" >>"$log"

  if [ "$os_release" != "$HARNESS_UBUNTU_BASELINE_RELEASE" ] || [ "$os_codename" != "$HARNESS_UBUNTU_BASELINE_CODENAME" ]; then
    evidence="$(write_evidence baseline "$label" blocked "simulate.sh up" "$log" "Container OS does not match Version Baseline")"
    die "Container OS drift for $label; expected $HARNESS_UBUNTU_BASELINE_RELEASE $HARNESS_UBUNTU_BASELINE_CODENAME, evidence=$evidence log=$log"
  fi

  write_evidence baseline "$label" pass "simulate.sh up" "$log" "Container OS release matches Version Baseline; resolved image id recorded" >/dev/null
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

cmd_render_config() {
  bootstrap_harness_env
  require_baseline_label
  write_rendered_env
  write_evidence render-config harness pass "simulate.sh render-config" "not-applicable" "Rendered redacted harness configuration with Version Baseline values" >/dev/null
  printf 'render-config: ok run-id=%s\n' "$HARNESS_RUN_ID"
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
        printf 'compose_recovery=docker-compose-v1-containerconfig\n'
        printf 'recovery_action=down-remove-orphans-and-retry-up\n'
      } >>"$log"
      compose down --remove-orphans >>"$log" 2>&1 || true
      if compose up -d --build >>"$log" 2>&1; then
        rc=0
      else
        rc=$?
      fi
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
  prepare_product_home_ownership gerrit gerrit-target "$log"
  prepare_product_home_ownership jenkins-controller jenkins-controller-target "$log"
  prepare_product_home_ownership jenkins-agent jenkins-agent-target "$log"
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
  gerrit_port="$(running_loopback_port_for_service gerrit-target)"
  jenkins_port="$(running_loopback_port_for_service jenkins-controller-target)"

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
  printf '  %-18s  %-14s  %-20s  %-40s\n' 'Gerrit integration' 'jenkins-gerrit' 'integration-password' 'Jenkins-to-Gerrit integration account'
  printf '  %-18s  %-14s  %-20s  %-40s\n' '------------------' '--------------' '--------------------' '----------------------------------------'
}

role_helper_present_in_container() {
  local service helper
  service="${1:?service required}"
  helper="${2:?helper required}"
  compose exec -T "$service" test -x "/workspace/$helper" >/dev/null 2>&1
}

cmd_prepare_artifacts() {
  local role helper service log rc evidence artifact_dir gerrit_env_file jenkins_env_file
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
  ensure_harness_up_for_role "$service"
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
  if [ "$role" = "gerrit" ]; then
    ensure_gerrit_ldap_bind_secret "$log"
    gerrit_env_file="$(require_gerrit_bundle_factory_env)"
  elif [ "$role" = "jenkins-controller" ]; then
    jenkins_env_file="$(require_jenkins_controller_bundle_factory_env)"
  elif [ "$role" = "jenkins-agent" ]; then
    jenkins_env_file="$(require_container_role_env jenkins-agent "$service")"
  fi

  if [ "$role" = "gerrit" ]; then
    if compose exec -T "$service" "/workspace/$helper" --env "$gerrit_env_file" --yes prepare-artifacts >>"$log" 2>&1; then
      rc=0
    else
      rc=$?
    fi
  elif [ "$role" = "jenkins-controller" ]; then
    if compose exec -T "$service" "/workspace/$helper" --env "$jenkins_env_file" --yes prepare-artifacts >>"$log" 2>&1; then
      rc=0
    else
      rc=$?
    fi
  elif [ "$role" = "jenkins-agent" ]; then
    if compose exec -T "$service" "/workspace/$helper" --env "$jenkins_env_file" prepare-artifacts >>"$log" 2>&1; then
      rc=0
    else
      rc=$?
    fi
  elif compose exec -T "$service" "/workspace/$helper" prepare-artifacts >>"$log" 2>&1; then
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

  artifact_dir="$HARNESS_STATE_DIR/bundle-factory/artifacts/$role"
  if [ ! -f "$artifact_dir/manifest.txt" ] || [ ! -f "$artifact_dir/checksums.sha256" ]; then
    evidence="$(write_evidence prepare-artifacts "$role" fail "simulate.sh prepare-artifacts" "$log" "Role helper did not produce manifest.txt and checksums.sha256")"
    print_command_failure prepare-artifacts "$role" failed "$log" "$evidence"
    return 1
  fi

  if ! validate_role_baseline_manifest "$role" "$artifact_dir/manifest.txt" "$log"; then
    evidence="$(write_evidence prepare-artifacts "$role" blocked "simulate.sh prepare-artifacts" "$log" "Artifact manifest baseline metadata is missing or drifted; comparable readiness is blocked")"
    printf 'ERROR: Artifact baseline metadata for %s is missing or drifted; log=%s evidence=%s\n' "$role" "$log" "$evidence" >&2
    print_command_failure prepare-artifacts "$role" blocked "$log" "$evidence" >&2
    return 1
  fi

  evidence="$(write_evidence prepare-artifacts "$role" pass "simulate.sh prepare-artifacts" "$log" "Role artifacts produced in bundle factory with manifest and checksums")"
  print_command_summary prepare-artifacts "$role" ok
}

cmd_stage_artifacts() {
  local role service artifact_dir stage_dir log rc evidence
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
  artifact_dir="$HARNESS_STATE_DIR/bundle-factory/artifacts/$role"
  stage_dir="$HARNESS_STAGING_DIR/$role"
  log="$(bounded_log_path "stage-artifacts-$role")"

  ensure_harness_up_for_role "$service"
  require_running_service "$service"
  [ -f "$artifact_dir/manifest.txt" ] || die "Missing bundle factory manifest for $role: $artifact_dir/manifest.txt"
  [ -f "$artifact_dir/checksums.sha256" ] || die "Missing bundle factory checksums for $role: $artifact_dir/checksums.sha256"

  : >"$log"
  if ! validate_role_baseline_manifest "$role" "$artifact_dir/manifest.txt" "$log"; then
    evidence="$(write_evidence stage-artifacts "$role" blocked "simulate.sh stage-artifacts" "$log" "Bundle factory manifest baseline metadata is missing or drifted; staging cannot report comparable readiness")"
    printf 'ERROR: Bundle factory baseline metadata for %s is missing or drifted; log=%s evidence=%s\n' "$role" "$log" "$evidence" >&2
    return 1
  fi

  mkdir -p "$stage_dir"
  if ! compose exec -T "$service" sh -c 'mkdir -p /harness/staged && find /harness/staged -mindepth 1 -maxdepth 1 -exec rm -rf {} +' >>"$log" 2>&1; then
    evidence="$(write_evidence stage-artifacts "$role" fail "simulate.sh stage-artifacts" "$log" "Failed to prepare target staging path in container")"
    print_command_failure stage-artifacts "$role" failed "$log" "$evidence"
    return 1
  fi

  if tar -C "$artifact_dir" -cf - . | compose exec -T "$service" tar -C /harness/staged -xf - >>"$log" 2>&1; then
    rc=0
  else
    rc=$?
  fi
  if [ "$rc" -ne 0 ]; then
    evidence="$(write_evidence stage-artifacts "$role" fail "simulate.sh stage-artifacts" "$log" "Failed to copy artifacts to target staging path")"
    print_command_failure stage-artifacts "$role" failed "$log" "$evidence"
    return "$rc"
  fi

  if (cd "$stage_dir" && sha256sum -c checksums.sha256) >>"$log" 2>&1; then
    rc=0
  else
    rc=$?
  fi
  if [ "$rc" -ne 0 ]; then
    evidence="$(write_evidence stage-artifacts "$role" fail "simulate.sh stage-artifacts" "$log" "Target-side checksum verification failed")"
    print_command_failure stage-artifacts "$role" failed "$log" "$evidence"
    return "$rc"
  fi

  if ! validate_role_baseline_manifest "$role" "$stage_dir/manifest.txt" "$log"; then
    evidence="$(write_evidence stage-artifacts "$role" blocked "simulate.sh stage-artifacts" "$log" "Target staged manifest baseline metadata is missing or drifted; comparable readiness is blocked")"
    printf 'ERROR: Target staged baseline metadata for %s is missing or drifted; log=%s evidence=%s\n' "$role" "$log" "$evidence" >&2
    print_command_failure stage-artifacts "$role" blocked "$log" "$evidence" >&2
    return 1
  fi

  if ! compose exec -T "$service" sh -c 'test -f /harness/staged/manifest.txt && test -f /harness/staged/checksums.sha256 && cd /harness/staged && sha256sum -c checksums.sha256' >>"$log" 2>&1; then
    evidence="$(write_evidence stage-artifacts "$role" fail "simulate.sh stage-artifacts" "$log" "Container target-side manifest/checksum verification failed")"
    print_command_failure stage-artifacts "$role" failed "$log" "$evidence"
    return 1
  fi

  evidence="$(write_evidence stage-artifacts "$role" pass "simulate.sh stage-artifacts" "$log" "Artifacts staged to target and verified by manifest/checksum before mutation")"
  print_command_summary stage-artifacts "$role" ok
}

assert_no_placeholder_success() {
  local log
  log="${1:?log required}"
    if grep -Eiq "dummy success|operation-plan-only|planned-checks-only|placeholder success|would validate|would run|target-local observable" "$log"; then
    return 1
  fi
  if grep -Eiq "proof=modeled|proof_scope=step8-modeled|real_execution=false|modeled_(scheduling|patchset|agent_build|verified)" "$log"; then
    return 1
  fi
  return 0
}

assert_no_forbidden_success_markers() {
  local log
  log="${1:?log required}"
  if grep -Eiq 'dummy success|operation-plan-only|planned-checks-only|synthetic transcript|marker WAR|marker JAR|local responder|would verify|would validate|fake stream-events|fake scheduling|fake Verified' "$log"; then
    return 1
  fi
  if grep -Eiq 'proof[[:space:]]*=[[:space:]]*modeled|proof_scope[[:space:]]*=[[:space:]]*step[0-9]+-modeled|real_execution[[:space:]]*=[[:space:]]*false' "$log"; then
    return 1
  fi
  if grep -Eiq 'modeled[_ -]?(stream-events|trigger|scheduling|agent|agent-build|agent_execution|verified|vote|verified-vote)|simulated[_ -]?(stream-events|trigger|scheduling|agent-build|verified-vote)' "$log"; then
    return 1
  fi
  return 0
}

normalize_role_evidence_logs() {
  local log role pattern state_dir latest
  log="${1:?log required}"
  role="${2:?role required}"
  pattern="${3:?pattern required}"
  state_dir="${4:?state dir required}"
  latest="$(find "$HARNESS_EVIDENCE_DIR" -maxdepth 1 -type f -name "$pattern" -print | sort | tail -1)"
  [ -n "$latest" ] || {
    printf 'missing_role_evidence role=%s expected=%s\n' "$role" "$pattern" >>"$log"
    return 1
  }

  require_command python3
  python3 - "$latest" "$latest.host.json" "$HARNESS_LOG_DIR" "$state_dir" <<'PY' >>"$log" 2>&1
import json
import pathlib
import sys

evidence = pathlib.Path(sys.argv[1])
normalized = pathlib.Path(sys.argv[2])
host_log = pathlib.Path(sys.argv[3])
host_state = pathlib.Path(sys.argv[4])
data = json.loads(evidence.read_text())
refs = data.get("bounded_log_references", "")
mapped = []
for ref in refs.split(";"):
    if ref.startswith("/harness/logs/"):
        mapped_ref = str(host_log / ref.removeprefix("/harness/logs/"))
        path = pathlib.Path(mapped_ref)
        if not path.is_file() or path.stat().st_size == 0:
            raise SystemExit(f"bounded log reference missing or empty: {mapped_ref}")
        mapped.append(mapped_ref)
    elif ref.startswith("/harness/state/"):
        mapped_ref = str(host_state / ref.removeprefix("/harness/state/"))
        path = pathlib.Path(mapped_ref)
        if not path.is_file() or path.stat().st_size == 0:
            raise SystemExit(f"bounded log reference missing or empty: {mapped_ref}")
        mapped.append(mapped_ref)
    else:
        path = pathlib.Path(ref)
        if not path.is_file() or path.stat().st_size == 0:
            raise SystemExit(f"bounded log reference missing or empty: {ref}")
        mapped.append(ref)

data["bounded_log_references"] = ";".join(mapped)
normalized.write_text(json.dumps(data, indent=2) + "\n")
print("normalized_role_evidence=" + str(normalized))
print("normalized_bounded_log_references=" + data["bounded_log_references"])
PY
}

normalize_gerrit_role_evidence_logs() {
  local log
  log="${1:?log required}"
  normalize_role_evidence_logs \
    "$log" \
    gerrit \
    'gerrit-readiness-*.json' \
    "$HARNESS_STATE_DIR/gerrit"
}

normalize_jenkins_controller_role_evidence_logs() {
  local log
  log="${1:?log required}"
  normalize_role_evidence_logs \
    "$log" \
    jenkins-controller \
    'jenkins-controller-readiness-*.json' \
    "$HARNESS_STATE_DIR/jenkins-controller"
}

normalize_jenkins_agent_role_evidence_logs() {
  local log
  log="${1:?log required}"
  normalize_role_evidence_logs \
    "$log" \
    jenkins-agent \
    'jenkins-agent-readiness-*.json' \
    "$HARNESS_STATE_DIR/jenkins-agent"
}

ensure_gerrit_ready_for_jenkins_controller() {
  local log gerrit_helper gerrit_service gerrit_env_file
  log="${1:?log required}"
  gerrit_helper="$(helper_for_role gerrit)"
  gerrit_service="$(service_for_role gerrit)"

  ensure_harness_up_for_role "$gerrit_service"
  require_running_service "$gerrit_service"
  gerrit_env_file="$(require_container_role_env gerrit "$gerrit_service")"

  if compose exec -T "$gerrit_service" env "$(gerrit_target_secret_env)" "/workspace/$gerrit_helper" --env "$gerrit_env_file" --yes validate >>"$log" 2>&1; then
    printf 'dependency_ready role=gerrit reason=real-gerrit-validation-already-passing\n' >>"$log"
    normalize_gerrit_role_evidence_logs "$log"
    return 0
  fi

  printf 'dependency_prepare role=gerrit reason=jenkins-controller-real-gerrit-ssh-validation\n' >>"$log"
    cmd_prepare_artifacts gerrit >>"$log" 2>&1 &&
    cmd_stage_artifacts gerrit >>"$log" 2>&1 &&
    ensure_gerrit_ldap_bind_secret "$log" &&
    compose exec -T "$gerrit_service" env "$(gerrit_target_secret_env)" "/workspace/$gerrit_helper" --env "$gerrit_env_file" --yes install >>"$log" 2>&1 &&
    compose exec -T "$gerrit_service" env "$(gerrit_target_secret_env)" "/workspace/$gerrit_helper" --env "$gerrit_env_file" --yes configure >>"$log" 2>&1 &&
    compose exec -T "$gerrit_service" env "$(gerrit_target_secret_env)" "/workspace/$gerrit_helper" --env "$gerrit_env_file" --yes validate >>"$log" 2>&1 &&
    compose exec -T "$gerrit_service" env "$(gerrit_target_secret_env)" "/workspace/$gerrit_helper" --env "$gerrit_env_file" --yes collect-evidence >>"$log" 2>&1 &&
    normalize_gerrit_role_evidence_logs "$log"
}

cmd_run_role_gate() {
  local role helper service log rc evidence role_env_file
  bootstrap_harness_env
  ensure_runtime_config
  role="${1:?role required}"
  helper="$(helper_for_role "$role")"
  service="$(service_for_role "$role")"
  ensure_harness_up_for_role "$service"
  require_running_service "$service"
  check_target_os_release "$role"

  log="$(bounded_log_path "run-role-gate-$role")"
  : >"$log"
  if ! role_helper_present_in_container "$service" "$helper"; then
    evidence="$(write_evidence run-role-gate "$role" blocked "simulate.sh run-role-gate" "$log" "Missing executable role helper /workspace/$helper in target container")"
    printf 'ERROR: Missing role helper for %s in target container: /workspace/%s\n' "$role" "$helper" >>"$log"
    printf 'exit=1 log=%s evidence=%s\n' "$log" "$evidence" >&2
    return 1
  fi
  role_env_file="$(require_container_role_env "$role" "$service")"

  case "$role" in
    gerrit)
      ensure_gerrit_ldap_bind_secret "$log"
      if cmd_prepare_artifacts gerrit >>"$log" 2>&1 &&
        cmd_stage_artifacts gerrit >>"$log" 2>&1 &&
        reset_gerrit_site_state "$service" "$log" &&
        prepare_product_home_ownership gerrit "$service" "$log" &&
        compose exec -T "$service" env "$(gerrit_target_secret_env)" "/workspace/$helper" --env "$role_env_file" --yes install >>"$log" 2>&1 &&
        compose exec -T "$service" env "$(gerrit_target_secret_env)" "/workspace/$helper" --env "$role_env_file" --yes configure >>"$log" 2>&1 &&
        compose exec -T "$service" env "$(gerrit_target_secret_env)" "/workspace/$helper" --env "$role_env_file" --yes validate >>"$log" 2>&1 &&
        compose exec -T "$service" env "$(gerrit_target_secret_env)" "/workspace/$helper" --env "$role_env_file" --yes collect-evidence >>"$log" 2>&1 &&
        normalize_gerrit_role_evidence_logs "$log"; then
        rc=0
      else
        rc=$?
      fi
      ;;
    jenkins-controller)
      if cmd_prepare_artifacts jenkins-controller >>"$log" 2>&1 &&
        cmd_stage_artifacts jenkins-controller >>"$log" 2>&1 &&
        prepare_product_home_ownership jenkins-controller "$service" "$log" &&
        compose exec -T "$service" env LDAP_BIND_PASSWORD="$HARNESS_LDAP_BIND_PASSWORD" "/workspace/$helper" --env "$role_env_file" --yes install >>"$log" 2>&1 &&
        compose exec -T "$service" env LDAP_BIND_PASSWORD="$HARNESS_LDAP_BIND_PASSWORD" "/workspace/$helper" --env "$role_env_file" --yes configure-service >>"$log" 2>&1 &&
        compose exec -T "$service" env LDAP_BIND_PASSWORD="$HARNESS_LDAP_BIND_PASSWORD" "/workspace/$helper" --env "$role_env_file" --yes install-plugins >>"$log" 2>&1 &&
        compose exec -T "$service" env LDAP_BIND_PASSWORD="$HARNESS_LDAP_BIND_PASSWORD" "/workspace/$helper" --env "$role_env_file" --yes configure-jcasc >>"$log" 2>&1 &&
        compose exec -T "$service" env LDAP_BIND_PASSWORD="$HARNESS_LDAP_BIND_PASSWORD" "/workspace/$helper" --env "$role_env_file" validate >>"$log" 2>&1 &&
        compose exec -T "$service" env LDAP_BIND_PASSWORD="$HARNESS_LDAP_BIND_PASSWORD" "/workspace/$helper" --env "$role_env_file" collect-evidence >>"$log" 2>&1 &&
        normalize_jenkins_controller_role_evidence_logs "$log"; then
        rc=0
      else
        rc=$?
      fi
      ;;
    jenkins-agent)
      if cmd_prepare_artifacts jenkins-agent >>"$log" 2>&1 &&
        cmd_stage_artifacts jenkins-agent >>"$log" 2>&1 &&
        prepare_product_home_ownership jenkins-agent "$service" "$log" &&
        compose exec -T "$service" "/workspace/$helper" --env "$role_env_file" --yes install >>"$log" 2>&1 &&
        compose exec -T "$service" "/workspace/$helper" --env "$role_env_file" --yes configure-runtime >>"$log" 2>&1 &&
        compose exec -T "$service" "/workspace/$helper" --env "$role_env_file" validate >>"$log" 2>&1 &&
        compose exec -T "$service" "/workspace/$helper" --env "$role_env_file" collect-evidence >>"$log" 2>&1 &&
        normalize_jenkins_agent_role_evidence_logs "$log"; then
        rc=0
      else
        rc=$?
      fi
      ;;
    *)
      if compose exec -T "$service" "/workspace/$helper" --env "$role_env_file" validate >>"$log" 2>&1; then
        rc=0
      else
        rc=$?
      fi
      ;;
  esac

  if [ "$rc" -eq 0 ]; then
    if ! validate_role_baseline_manifest "$role" "$HARNESS_STAGING_DIR/$role/manifest.txt" "$log"; then
      evidence="$(write_evidence run-role-gate "$role" blocked "simulate.sh run-role-gate" "$log" "Staged artifact baseline metadata is missing or drifted; role readiness cannot be comparable")"
      print_command_failure run-role-gate "$role" blocked "$log" "$evidence" >&2
      return 1
    fi

    if ! assert_no_placeholder_success "$log"; then
      evidence="$(write_evidence run-role-gate "$role" fail "simulate.sh run-role-gate" "$log" "Role gate produced dummy, placeholder, operation-plan-only, planned-checks-only, or modeled success")"
      print_command_failure run-role-gate "$role" failed "$log" "$evidence"
      return 1
    fi
    evidence="$(write_evidence run-role-gate "$role" pass "simulate.sh run-role-gate" "$log" "Role helper validated required real behavior without placeholder success markers")"
    print_command_summary run-role-gate "$role" ok
    return 0
  fi

  if grep -Eq "BLOCKED:" "$log"; then
    evidence="$(write_evidence run-role-gate "$role" blocked "simulate.sh run-role-gate" "$log" "Role helper reported a blocked runtime behavior requirement")"
    printf 'ERROR: Role helper for %s reported blocked runtime behavior\n' "$role" >&2
  elif grep -Eq "is not implemented in this repository step|is a placeholder" "$log"; then
    evidence="$(write_evidence run-role-gate "$role" blocked "simulate.sh run-role-gate" "$log" "Role helper exists but validate is not implemented yet")"
    printf 'ERROR: Role helper for %s exists but validate is not implemented yet\n' "$role" >&2
  else
    evidence="$(write_evidence run-role-gate "$role" fail "simulate.sh run-role-gate" "$log" "Role helper validate failed; readiness is not proven")"
  fi
  print_command_failure run-role-gate "$role" failed "$log" "$evidence"
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

cmd_check() {
  local integration_log rc evidence
  bootstrap_harness_env
  ensure_runtime_config
  refresh_integration_args
  run_all_roles run-role-gate || rc=$?
  rc="${rc:-0}"
  if [ "$rc" -ne 0 ]; then
    evidence="$(write_evidence check roles fail "simulate.sh check" "not-applicable" "One or more role gates failed; cross-role integration was not attempted")"
    print_command_summary check "" "role gates failed"
    return "$rc"
  fi
  unset rc

  [ -x "$integration_helper" ] || die "Missing executable integration helper: $integration_helper"
  integration_log="$(bounded_log_path configure-and-validate-integration)"
  {
    "$integration_helper" "${integration_args[@]}" --yes configure-gerrit-ssh &&
      "$integration_helper" "${integration_args[@]}" --yes configure-agent-ssh &&
      "$integration_helper" "${integration_args[@]}" --yes configure-trigger &&
      "$integration_helper" "${integration_args[@]}" --yes validate-integration
  } >"$integration_log" 2>&1 || rc=$?
  rc="${rc:-0}"
  if [ "$rc" -eq 0 ]; then
    if ! assert_no_forbidden_success_markers "$integration_log"; then
      evidence="$(write_evidence check integration fail "simulate.sh check" "$integration_log" "Forbidden success marker found in integration validation log")"
      print_command_failure check "" failed "$integration_log" "$evidence"
      return 1
    fi
    evidence="$(write_evidence check integration pass "simulate.sh check" "$integration_log" "Shared integration helper proved Jenkins-to-Gerrit SSH, stream-events, Jenkins-to-agent SSH, node readiness, and agent scheduling")"
    print_command_summary check "" "integration ok"
    return 0
  fi

  write_blocked_integration_evidence jenkins-to-gerrit-ssh "$integration_log" "Blocked: shared integration helper has not implemented real Jenkins-to-Gerrit SSH setup and validation"
  write_blocked_integration_evidence stream-events "$integration_log" "Blocked: shared integration helper has not implemented real Gerrit stream-events validation"
  write_blocked_integration_evidence agent-connection "$integration_log" "Blocked: shared integration helper has not implemented real Jenkins-to-agent SSH connection validation"
  write_blocked_integration_evidence scheduling "$integration_log" "Blocked: shared integration helper has not implemented real Jenkins agent scheduling validation"
  evidence="$(write_evidence check integration blocked "simulate.sh check" "$integration_log" "Shared integration helper reported blocked cross-role validation; Docker simulation cannot claim readiness")"
  print_command_summary check "" "blocked"
  return "$rc"
}

cmd_full_verify() {
  local log rc evidence
  bootstrap_harness_env
  ensure_runtime_config
  refresh_integration_args
  cmd_check || rc=$?
  rc="${rc:-0}"
  if [ "$rc" -ne 0 ]; then
    log="$(bounded_log_path full-verify-blocked)"
    printf 'full_verify_blocked=check_failed_or_blocked\n' >"$log"
    write_blocked_integration_evidence job-execution "$log" "Blocked: readiness check did not prove real cross-role integration, so job execution was not attempted"
    write_blocked_integration_evidence verified-vote "$log" "Blocked: readiness check did not prove real cross-role integration, so Verified +1 was not attempted"
    evidence="$(write_evidence full-verify integration blocked "simulate.sh full-verify" "$log" "Full verification blocked before end-to-end trigger execution")"
    print_command_summary full-verify "" "blocked"
    return "$rc"
  fi
  unset rc

  [ -x "$integration_helper" ] || die "Missing executable integration helper: $integration_helper"
  log="$(bounded_log_path verify-trigger)"
  "$integration_helper" "${integration_args[@]}" --yes verify-trigger >"$log" 2>&1 || rc=$?
  rc="${rc:-0}"
  if [ "$rc" -eq 0 ]; then
    if ! assert_no_forbidden_success_markers "$log"; then
      evidence="$(write_evidence full-verify integration fail "simulate.sh full-verify" "$log" "Forbidden success marker found in trigger verification log")"
      print_command_failure full-verify "" failed "$log" "$evidence"
      return 1
    fi
    evidence="$(write_evidence full-verify integration pass "simulate.sh full-verify" "$log" "Shared integration helper proved disposable change, Gerrit event receipt, Jenkins job scheduling, agent execution, and Verified +1")"
    print_command_summary full-verify "" "integration ok"
    return 0
  fi

  write_blocked_integration_evidence job-execution "$log" "Blocked: shared integration helper has not implemented real disposable Jenkins job execution proof"
  write_blocked_integration_evidence verified-vote "$log" "Blocked: shared integration helper has not implemented real Gerrit Verified +1 vote proof"
  evidence="$(write_evidence full-verify integration blocked "simulate.sh full-verify" "$log" "Shared integration helper reported blocked trigger verification; Docker simulation cannot claim end-to-end success")"
  print_command_summary full-verify "" "blocked"
  return "$rc"
}

cmd_down() {
  local log rc evidence
  bootstrap_harness_env
  ensure_runtime_config
  detect_compose
  log="$(bounded_log_path down)"
  if compose down >"$log" 2>&1; then
    rc=0
  else
    rc=$?
  fi
  if [ "$rc" -ne 0 ]; then
    evidence="$(write_evidence down harness fail "simulate.sh down" "$log" "Compose down failed")"
    print_command_failure down "" failed "$log" "$evidence"
    return "$rc"
  fi
  evidence="$(write_evidence down harness pass "simulate.sh down" "$log" "Stopped harness containers without deleting retained evidence")"
  print_command_summary down "" "stopped harness containers"
}

parse_env_and_role_args() {
  local role_required role
  role_required="${1:?role_required required}"
  shift
  role=""
  HARNESS_ENV_FILE="${HARNESS_ENV_FILE:-$docker_env_example}"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --env)
        [ "$#" -ge 2 ] || die "--env requires a file"
        HARNESS_ENV_FILE="$2"
        shift 2
        ;;
      --env=*)
        HARNESS_ENV_FILE="${1#--env=}"
        [ -n "$HARNESS_ENV_FILE" ] || die "--env requires a file"
        shift
        ;;
      --role)
        [ "$#" -ge 2 ] || die "--role requires a value"
        role="$2"
        shift 2
        ;;
      --role=*)
        role="${1#--role=}"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown option for Docker harness command: $1"
        ;;
    esac
  done
  if [ "$role_required" -eq 1 ] && [ -z "$role" ]; then
    die "Missing --role; expected gerrit, jenkins-controller, or jenkins-agent"
  fi
  PARSED_ROLE="$role"
}

parse_env_only_args() {
  local env_file
  env_file="${HARNESS_ENV_FILE:-$docker_env_example}"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --env)
        [ "$#" -ge 2 ] || die "--env requires a file"
        env_file="$2"
        shift 2
        ;;
      --env=*)
        env_file="${1#--env=}"
        [ -n "$env_file" ] || die "--env requires a file"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown option for Docker harness command: $1"
        ;;
    esac
  done
  HARNESS_ENV_FILE="$env_file"
}

main() {
  local command_name env_file
  env_file="$docker_env_example"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --env)
        [ "$#" -ge 2 ] || die "--env requires a file"
        env_file="$2"
        shift 2
        ;;
      --env=*)
        env_file="${1#--env=}"
        [ -n "$env_file" ] || die "--env requires a file"
        shift
        ;;
      -h|--help|help)
        usage
        exit 0
        ;;
      *)
        break
        ;;
    esac
  done
  HARNESS_ENV_FILE="$env_file"
  command_name="${1:-}"
  case "$command_name" in
    preflight)
      shift
      parse_env_only_args "$@"
      cmd_preflight
      ;;
    render-config)
      shift
      parse_env_only_args "$@"
      cmd_render_config
      ;;
    up)
      shift
      parse_env_only_args "$@"
      cmd_up
      ;;
    status)
      shift
      parse_env_only_args "$@"
      cmd_status
      ;;
    prepare-artifacts)
      shift
      parse_env_and_role_args 0 "$@"
      cmd_prepare_artifacts "$PARSED_ROLE"
      ;;
    stage-artifacts)
      shift
      parse_env_and_role_args 0 "$@"
      cmd_stage_artifacts "$PARSED_ROLE"
      ;;
    run-role-gate)
      shift
      parse_env_and_role_args 1 "$@"
      cmd_run_role_gate "$PARSED_ROLE"
      ;;
    check)
      shift
      parse_env_only_args "$@"
      cmd_check
      ;;
    full-verify)
      shift
      parse_env_only_args "$@"
      cmd_full_verify
      ;;
    down)
      shift
      parse_env_only_args "$@"
      cmd_down
      ;;
    "")
      usage
      exit 1
      ;;
    *)
      die "Unknown command: $command_name"
      ;;
  esac
}

main "$@"
