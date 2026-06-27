#!/usr/bin/env bash

set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
repo_root="$(CDPATH= cd -- "$script_dir/../.." && pwd)"
docker_dir="$script_dir"
compose_file="$docker_dir/compose.yaml"
docker_env_example="$docker_dir/examples/docker.env.example"
integration_helper="${HARNESS_TEST_INTEGRATION_HELPER:-$repo_root/scripts/integration-setup.sh}"
roles=(gerrit jenkins-controller jenkins-agent)
services=(bundle-factory ldap gerrit-target jenkins-controller-target jenkins-agent-target)

usage() {
  cat <<'USAGE'
Usage:
  simulation/docker/simulate.sh <command> [options]

Commands:
  run
  ssh --role <gerrit|jenkins-controller|jenkins-agent>

Phases:
  preflight
  init-run
  up
  status
  ssh --role <gerrit|jenkins-controller|jenkins-agent>
  prepare-artifacts [--role <gerrit|jenkins-controller|jenkins-agent>]
  stage-artifacts [--role <gerrit|jenkins-controller|jenkins-agent>]
  configure-role [--role <gerrit|jenkins-controller|jenkins-agent>]
  validate-role [--role <gerrit|jenkins-controller|jenkins-agent>]
  configure-integration
  validate-integration
  prove-integration
  audit-state
  down
  clean

Options:
  --env FILE        Harness env file for bootstrap and init-run.
  --role ROLE       Role for role-scoped commands.
  -h, --help        Show this help.

The harness is the Docker simulation CLI. It owns strict role and cross-role
integration phases. Public internet fallback on target hosts is
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

canonical_generated_run_dir() {
  printf '%s/generated/simulation/docker/%s\n' "$repo_root" "$HARNESS_RUN_ID"
}

apply_canonical_output_paths() {
  HARNESS_GENERATED_RUN_DIR="$(canonical_generated_run_dir)"
  HARNESS_HOST_DIR="$HARNESS_GENERATED_RUN_DIR/host"
  HARNESS_TARGET_DIR="$HARNESS_GENERATED_RUN_DIR/target"
  HARNESS_STATE_DIR="$HARNESS_TARGET_DIR/helper-state"
  HARNESS_PRODUCT_HOME_DIR="$HARNESS_TARGET_DIR/product-homes"
  HARNESS_STAGING_DIR="$HARNESS_TARGET_DIR/artifacts/staging"
  HARNESS_EXPORTED_ARTIFACT_DIR="$HARNESS_TARGET_DIR/artifacts/exported"
  HARNESS_EVIDENCE_DIR="$HARNESS_HOST_DIR/evidence/harness"
  HARNESS_LOG_DIR="$HARNESS_HOST_DIR/logs/harness"
  HARNESS_RETAINED_OUTPUT_BACKUP_DIR="$HARNESS_HOST_DIR/retained-output-backups"
  HARNESS_RENDERED_ENV="$HARNESS_HOST_DIR/rendered/harness.env"
  HARNESS_RUNTIME_ENV="$HARNESS_HOST_DIR/rendered/harness.runtime.env"
  HARNESS_RUNTIME_INPUT_DIR="$HARNESS_HOST_DIR/runtime-inputs"
  HARNESS_BASELINE_CONTRACT="$HARNESS_HOST_DIR/rendered/artifact-manifest-contract.txt"
  HARNESS_RUN_MARKER="$HARNESS_GENERATED_RUN_DIR/.loopforge-docker-run.env"
  HARNESS_TARGET_SSH_DIR="$HARNESS_HOST_DIR/target-ssh"
  HARNESS_TARGET_SSH_IDENTITY_FILE="$HARNESS_TARGET_SSH_DIR/ci-operator"
  HARNESS_TARGET_SSH_KNOWN_HOSTS_FILE="$HARNESS_TARGET_SSH_DIR/known_hosts"
  HARNESS_GERRIT_VALIDATION_SECRET_DIR="$HARNESS_HOST_DIR/validation-secrets/gerrit"
  HARNESS_BUNDLE_FACTORY_RENDERED_DIR="$HARNESS_HOST_DIR/bundle-factory/rendered"
  HARNESS_BUNDLE_FACTORY_VALIDATION_PUBLIC_DIR="$HARNESS_HOST_DIR/bundle-factory/validation-public"
  HARNESS_LDAP_DATA_DIR="$HARNESS_TARGET_DIR/ldap/data"
  HARNESS_LDAP_CONFIG_DIR="$HARNESS_TARGET_DIR/ldap/config"
  HARNESS_SHARED_JENKINS_STORAGE_DIR="$HARNESS_TARGET_DIR/shared-jenkins-storage"
  HARNESS_GERRIT_EVIDENCE_DIR="$HARNESS_TARGET_DIR/evidence/gerrit"
  HARNESS_GERRIT_LOG_DIR="$HARNESS_TARGET_DIR/logs/gerrit"
  HARNESS_JENKINS_CONTROLLER_EVIDENCE_DIR="$HARNESS_TARGET_DIR/evidence/jenkins-controller"
  HARNESS_JENKINS_CONTROLLER_LOG_DIR="$HARNESS_TARGET_DIR/logs/jenkins-controller"
  HARNESS_JENKINS_AGENT_EVIDENCE_DIR="$HARNESS_TARGET_DIR/evidence/jenkins-agent"
  HARNESS_JENKINS_AGENT_LOG_DIR="$HARNESS_TARGET_DIR/logs/jenkins-agent"
  export HARNESS_GENERATED_RUN_DIR HARNESS_HOST_DIR HARNESS_TARGET_DIR
  export HARNESS_STATE_DIR HARNESS_PRODUCT_HOME_DIR
  export HARNESS_STAGING_DIR HARNESS_EXPORTED_ARTIFACT_DIR
  export HARNESS_EVIDENCE_DIR HARNESS_LOG_DIR HARNESS_RETAINED_OUTPUT_BACKUP_DIR
  export HARNESS_RENDERED_ENV HARNESS_RUNTIME_ENV HARNESS_RUNTIME_INPUT_DIR
  export HARNESS_BASELINE_CONTRACT HARNESS_RUN_MARKER
  export HARNESS_TARGET_SSH_DIR HARNESS_TARGET_SSH_IDENTITY_FILE
  export HARNESS_TARGET_SSH_KNOWN_HOSTS_FILE
  export HARNESS_GERRIT_VALIDATION_SECRET_DIR HARNESS_BUNDLE_FACTORY_RENDERED_DIR
  export HARNESS_BUNDLE_FACTORY_VALIDATION_PUBLIC_DIR HARNESS_LDAP_DATA_DIR
  export HARNESS_LDAP_CONFIG_DIR HARNESS_SHARED_JENKINS_STORAGE_DIR
  export HARNESS_GERRIT_EVIDENCE_DIR HARNESS_GERRIT_LOG_DIR
  export HARNESS_JENKINS_CONTROLLER_EVIDENCE_DIR HARNESS_JENKINS_CONTROLLER_LOG_DIR
  export HARNESS_JENKINS_AGENT_EVIDENCE_DIR HARNESS_JENKINS_AGENT_LOG_DIR
}

container_name_for_service() {
  local service
  service="${1:?service required}"
  printf '%s-%s\n' "$HARNESS_PROJECT_NAME" "$service"
}

selected_container_names() {
  local service
  for service in "${services[@]}"; do
    container_name_for_service "$service"
  done
}

docker_container_name_exists() {
  local name
  name="${1:?container name required}"
  command -v docker >/dev/null 2>&1 || return 1
  docker ps -a --format '{{.Names}}' 2>/dev/null | grep -Fxq "$name"
}

selected_containers_exist() {
  local name
  command -v docker >/dev/null 2>&1 || return 1
  while IFS= read -r name; do
    docker_container_name_exists "$name" && return 0
  done <<EOF
$(selected_container_names)
EOF
  return 1
}

existing_selected_container_names() {
  local name
  command -v docker >/dev/null 2>&1 || return 0
  while IFS= read -r name; do
    docker_container_name_exists "$name" && printf '%s\n' "$name"
  done <<EOF
$(selected_container_names)
EOF
}

reject_custom_output_paths() {
  local name value expected
  for name in \
    HARNESS_GENERATED_RUN_DIR \
    HARNESS_HOST_DIR \
    HARNESS_TARGET_DIR \
    HARNESS_STATE_DIR \
    HARNESS_PRODUCT_HOME_DIR \
    HARNESS_STAGING_DIR \
    HARNESS_EXPORTED_ARTIFACT_DIR \
    HARNESS_EVIDENCE_DIR \
    HARNESS_LOG_DIR \
    HARNESS_RETAINED_OUTPUT_BACKUP_DIR \
    HARNESS_RENDERED_ENV \
    HARNESS_BASELINE_CONTRACT \
    HARNESS_TARGET_SSH_DIR \
    HARNESS_GERRIT_VALIDATION_SECRET_DIR \
    HARNESS_BUNDLE_FACTORY_RENDERED_DIR \
    HARNESS_BUNDLE_FACTORY_VALIDATION_PUBLIC_DIR \
    HARNESS_LDAP_DATA_DIR \
    HARNESS_LDAP_CONFIG_DIR \
    HARNESS_SHARED_JENKINS_STORAGE_DIR \
    HARNESS_GERRIT_EVIDENCE_DIR \
    HARNESS_GERRIT_LOG_DIR \
    HARNESS_JENKINS_CONTROLLER_EVIDENCE_DIR \
    HARNESS_JENKINS_CONTROLLER_LOG_DIR \
    HARNESS_JENKINS_AGENT_EVIDENCE_DIR \
    HARNESS_JENKINS_AGENT_LOG_DIR
  do
    eval "value=\${$name-}"
    [ -n "$value" ] || continue
    case "$name" in
      HARNESS_GENERATED_RUN_DIR) expected="$(canonical_generated_run_dir)" ;;
      HARNESS_HOST_DIR) expected="$(canonical_generated_run_dir)/host" ;;
      HARNESS_TARGET_DIR) expected="$(canonical_generated_run_dir)/target" ;;
      HARNESS_STATE_DIR) expected="$(canonical_generated_run_dir)/target/helper-state" ;;
      HARNESS_PRODUCT_HOME_DIR) expected="$(canonical_generated_run_dir)/target/product-homes" ;;
      HARNESS_STAGING_DIR) expected="$(canonical_generated_run_dir)/target/artifacts/staging" ;;
      HARNESS_EXPORTED_ARTIFACT_DIR) expected="$(canonical_generated_run_dir)/target/artifacts/exported" ;;
      HARNESS_EVIDENCE_DIR) expected="$(canonical_generated_run_dir)/host/evidence/harness" ;;
      HARNESS_LOG_DIR) expected="$(canonical_generated_run_dir)/host/logs/harness" ;;
      HARNESS_RETAINED_OUTPUT_BACKUP_DIR) expected="$(canonical_generated_run_dir)/host/retained-output-backups" ;;
      HARNESS_RENDERED_ENV) expected="$(canonical_generated_run_dir)/host/rendered/harness.env" ;;
      HARNESS_BASELINE_CONTRACT) expected="$(canonical_generated_run_dir)/host/rendered/artifact-manifest-contract.txt" ;;
      HARNESS_TARGET_SSH_DIR) expected="$(canonical_generated_run_dir)/host/target-ssh" ;;
      HARNESS_GERRIT_VALIDATION_SECRET_DIR) expected="$(canonical_generated_run_dir)/host/validation-secrets/gerrit" ;;
      HARNESS_BUNDLE_FACTORY_RENDERED_DIR) expected="$(canonical_generated_run_dir)/host/bundle-factory/rendered" ;;
      HARNESS_BUNDLE_FACTORY_VALIDATION_PUBLIC_DIR) expected="$(canonical_generated_run_dir)/host/bundle-factory/validation-public" ;;
      HARNESS_LDAP_DATA_DIR) expected="$(canonical_generated_run_dir)/target/ldap/data" ;;
      HARNESS_LDAP_CONFIG_DIR) expected="$(canonical_generated_run_dir)/target/ldap/config" ;;
      HARNESS_SHARED_JENKINS_STORAGE_DIR) expected="$(canonical_generated_run_dir)/target/shared-jenkins-storage" ;;
      HARNESS_GERRIT_EVIDENCE_DIR) expected="$(canonical_generated_run_dir)/target/evidence/gerrit" ;;
      HARNESS_GERRIT_LOG_DIR) expected="$(canonical_generated_run_dir)/target/logs/gerrit" ;;
      HARNESS_JENKINS_CONTROLLER_EVIDENCE_DIR) expected="$(canonical_generated_run_dir)/target/evidence/jenkins-controller" ;;
      HARNESS_JENKINS_CONTROLLER_LOG_DIR) expected="$(canonical_generated_run_dir)/target/logs/jenkins-controller" ;;
      HARNESS_JENKINS_AGENT_EVIDENCE_DIR) expected="$(canonical_generated_run_dir)/target/evidence/jenkins-agent" ;;
      HARNESS_JENKINS_AGENT_LOG_DIR) expected="$(canonical_generated_run_dir)/target/logs/jenkins-agent" ;;
      *) die "Internal error: unknown output path $name" ;;
    esac
    [ "$value" = "$expected" ] ||
      die "$name must use the canonical repo-local generated path for v1: $expected"
  done
}

validate_canonical_run_root() {
  local expected actual_real expected_real child
  expected="$(canonical_generated_run_dir)"
  [ "$HARNESS_GENERATED_RUN_DIR" = "$expected" ] ||
    die "HARNESS_GENERATED_RUN_DIR must be $expected"
  [ -d "$HARNESS_GENERATED_RUN_DIR" ] || die "Missing generated run directory: $HARNESS_GENERATED_RUN_DIR"
  [ ! -L "$HARNESS_GENERATED_RUN_DIR" ] || die "Generated run directory must not be a symlink"
  actual_real="$(realpath "$HARNESS_GENERATED_RUN_DIR")"
  expected_real="$(realpath "$expected")"
  [ "$actual_real" = "$expected_real" ] ||
    die "Generated run directory resolved outside the canonical run root"
  for child in host target; do
    [ ! -L "$HARNESS_GENERATED_RUN_DIR/$child" ] ||
      die "Generated run child must not be a symlink: $HARNESS_GENERATED_RUN_DIR/$child"
  done
}

sha256_file() {
  sha256sum "$1" | awk '{print $1}'
}

runtime_env_fingerprint() {
  sha256_file "$HARNESS_RUNTIME_ENV"
}

marker_value() {
  local file key
  file="${1:?file required}"
  key="${2:?key required}"
  awk -F= -v key="$key" '$1 == key { print substr($0, length(key) + 2); found = 1; exit } END { exit !found }' "$file"
}

write_run_marker() {
  local fingerprint
  fingerprint="$(runtime_env_fingerprint)"
  cat >"$HARNESS_RUN_MARKER" <<EOF
mode=$HARNESS_MODE
run_id=$HARNESS_RUN_ID
project_name=$HARNESS_PROJECT_NAME
repo_root=$repo_root
generated_run_dir=$HARNESS_GENERATED_RUN_DIR
runtime_env_fingerprint=$fingerprint
EOF
  chmod 0600 "$HARNESS_RUN_MARKER"
}

verify_run_marker() {
  local marker fingerprint
  marker="${HARNESS_RUN_MARKER:-$HARNESS_GENERATED_RUN_DIR/.loopforge-docker-run.env}"
  validate_canonical_run_root
  [ -f "$marker" ] || die "Missing Docker harness run marker: $marker"
  [ "$(marker_value "$marker" mode)" = "$HARNESS_MODE" ] ||
    die "Run marker mode does not match selected runtime config"
  [ "$(marker_value "$marker" run_id)" = "$HARNESS_RUN_ID" ] ||
    die "Run marker run ID does not match selected runtime config"
  [ "$(marker_value "$marker" project_name)" = "$HARNESS_PROJECT_NAME" ] ||
    die "Run marker project name does not match selected runtime config"
  [ "$(marker_value "$marker" repo_root)" = "$repo_root" ] ||
    die "Run marker repo root does not match this checkout"
  [ "$(marker_value "$marker" generated_run_dir)" = "$HARNESS_GENERATED_RUN_DIR" ] ||
    die "Run marker generated run dir does not match selected runtime config"
  fingerprint="$(runtime_env_fingerprint)"
  [ "$(marker_value "$marker" runtime_env_fingerprint)" = "$fingerprint" ] ||
    die "Run marker runtime env fingerprint does not match selected runtime config"
}

require_generated_state_file() {
  local label file
  label="${1:?label required}"
  file="${2:?file required}"
  [ -f "$file" ] || die "Inconsistent Docker generated state: missing $label: $file"
  [ -r "$file" ] || die "Inconsistent Docker generated state: unreadable $label: $file"
}

require_generated_state_dir() {
  local label dir
  label="${1:?label required}"
  dir="${2:?dir required}"
  [ -d "$dir" ] || die "Inconsistent Docker generated state: missing $label: $dir"
  [ ! -L "$dir" ] || die "Inconsistent Docker generated state: $label must not be a symlink: $dir"
}

validate_core_generated_state() {
  local role service
  validate_canonical_run_root
  require_generated_state_file "rendered harness env" "$HARNESS_RENDERED_ENV"
  require_generated_state_file "runtime harness env" "$HARNESS_RUNTIME_ENV"
  require_generated_state_file "artifact manifest contract" "$HARNESS_BASELINE_CONTRACT"
  require_generated_state_dir "runtime input directory" "$HARNESS_RUNTIME_INPUT_DIR"
  require_generated_state_file "runtime input harness env" "$HARNESS_RUNTIME_INPUT_DIR/harness.env"
  require_generated_state_file "runtime input Gerrit env" "$HARNESS_RUNTIME_INPUT_DIR/gerrit.env"
  require_generated_state_file "runtime input Jenkins controller env" "$HARNESS_RUNTIME_INPUT_DIR/jenkins-controller.env"
  require_generated_state_file "runtime input Jenkins agent env" "$HARNESS_RUNTIME_INPUT_DIR/jenkins-agent.env"
  require_generated_state_file "runtime input integration env" "$HARNESS_RUNTIME_INPUT_DIR/integration.env"
  require_generated_state_file "bundle factory Gerrit helper env" "$(host_gerrit_bundle_factory_env_file)"
  require_generated_state_file "bundle factory Jenkins controller helper env" "$(host_jenkins_controller_bundle_factory_env_file)"
  require_generated_state_file "bundle factory Jenkins agent helper env" "$(host_container_env_file_for_role jenkins-agent bundle-factory)"
  for role in "${roles[@]}"; do
    service="$(service_for_role "$role")"
    require_generated_state_file "$role target helper env" "$(host_container_env_file_for_role "$role" "$service")"
  done
  require_generated_state_dir "state directory" "$HARNESS_STATE_DIR"
  require_generated_state_dir "host contribution directory" "$HARNESS_HOST_DIR"
  require_generated_state_dir "target contribution directory" "$HARNESS_TARGET_DIR"
  require_generated_state_dir "product home directory" "$HARNESS_PRODUCT_HOME_DIR"
  require_generated_state_dir "staging directory" "$HARNESS_STAGING_DIR"
  require_generated_state_dir "exported artifact directory" "$HARNESS_EXPORTED_ARTIFACT_DIR"
  require_generated_state_dir "evidence directory" "$HARNESS_EVIDENCE_DIR"
  require_generated_state_dir "log directory" "$HARNESS_LOG_DIR"
  require_generated_state_dir "bundle factory rendered bind source" "$HARNESS_BUNDLE_FACTORY_RENDERED_DIR"
  require_generated_state_dir "bundle factory evidence bind source" "$HARNESS_STATE_DIR/bundle-factory/evidence"
  require_generated_state_dir "bundle factory preparing bind source" "$HARNESS_STATE_DIR/bundle-factory/preparing"
  require_generated_state_dir "LDAP data bind source" "$HARNESS_LDAP_DATA_DIR"
  require_generated_state_dir "LDAP config bind source" "$HARNESS_LDAP_CONFIG_DIR"
  require_generated_state_dir "Gerrit helper state bind source" "$HARNESS_STATE_DIR/gerrit"
  require_generated_state_dir "Jenkins controller helper state bind source" "$HARNESS_STATE_DIR/jenkins-controller"
  require_generated_state_dir "Jenkins agent helper state bind source" "$HARNESS_STATE_DIR/jenkins-agent"
  require_generated_state_dir "Gerrit product home bind source" "$HARNESS_PRODUCT_HOME_DIR/gerrit"
  require_generated_state_dir "Jenkins controller product home bind source" "$HARNESS_PRODUCT_HOME_DIR/jenkins-controller"
  require_generated_state_dir "Jenkins agent product home bind source" "$HARNESS_PRODUCT_HOME_DIR/jenkins-agent"
  require_generated_state_dir "Gerrit validation secret bind source" "$HARNESS_GERRIT_VALIDATION_SECRET_DIR"
  require_generated_state_dir "shared Jenkins storage bind source" "$HARNESS_SHARED_JENKINS_STORAGE_DIR"
  require_generated_state_dir "Gerrit evidence bind source" "$HARNESS_GERRIT_EVIDENCE_DIR"
  require_generated_state_dir "Gerrit log bind source" "$HARNESS_GERRIT_LOG_DIR"
  require_generated_state_dir "Jenkins controller evidence bind source" "$HARNESS_JENKINS_CONTROLLER_EVIDENCE_DIR"
  require_generated_state_dir "Jenkins controller log bind source" "$HARNESS_JENKINS_CONTROLLER_LOG_DIR"
  require_generated_state_dir "Jenkins agent evidence bind source" "$HARNESS_JENKINS_AGENT_EVIDENCE_DIR"
  require_generated_state_dir "Jenkins agent log bind source" "$HARNESS_JENKINS_AGENT_LOG_DIR"
  require_generated_state_dir "target SSH state" "$HARNESS_TARGET_SSH_DIR"
  require_generated_state_file "target SSH identity file" "$HARNESS_TARGET_SSH_IDENTITY_FILE"
}

timestamp_utc() {
  date -u +%Y%m%dT%H%M%SZ
}

iso_timestamp_utc() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

HARNESS_PROJECT_NAME_OPERATOR_SET="${HARNESS_PROJECT_NAME+x}"
HARNESS_RUN_ID_OPERATOR_SET="${HARNESS_RUN_ID+x}"
HARNESS_GENERATED_RUN_DIR_OPERATOR_SET="${HARNESS_GENERATED_RUN_DIR+x}"
HARNESS_HOST_DIR_OPERATOR_SET="${HARNESS_HOST_DIR+x}"
HARNESS_TARGET_DIR_OPERATOR_SET="${HARNESS_TARGET_DIR+x}"
HARNESS_STATE_DIR_OPERATOR_SET="${HARNESS_STATE_DIR+x}"
HARNESS_PRODUCT_HOME_DIR_OPERATOR_SET="${HARNESS_PRODUCT_HOME_DIR+x}"
HARNESS_STAGING_DIR_OPERATOR_SET="${HARNESS_STAGING_DIR+x}"
HARNESS_EXPORTED_ARTIFACT_DIR_OPERATOR_SET="${HARNESS_EXPORTED_ARTIFACT_DIR+x}"
HARNESS_EVIDENCE_DIR_OPERATOR_SET="${HARNESS_EVIDENCE_DIR+x}"
HARNESS_LOG_DIR_OPERATOR_SET="${HARNESS_LOG_DIR+x}"
HARNESS_RETAINED_OUTPUT_BACKUP_DIR_OPERATOR_SET="${HARNESS_RETAINED_OUTPUT_BACKUP_DIR+x}"
HARNESS_RENDERED_ENV_OPERATOR_SET="${HARNESS_RENDERED_ENV+x}"
HARNESS_BASELINE_CONTRACT_OPERATOR_SET="${HARNESS_BASELINE_CONTRACT+x}"
HARNESS_TARGET_SSH_DIR_OPERATOR_SET="${HARNESS_TARGET_SSH_DIR+x}"
HARNESS_GERRIT_VALIDATION_SECRET_DIR_OPERATOR_SET="${HARNESS_GERRIT_VALIDATION_SECRET_DIR+x}"
HARNESS_BUNDLE_FACTORY_RENDERED_DIR_OPERATOR_SET="${HARNESS_BUNDLE_FACTORY_RENDERED_DIR+x}"
HARNESS_BUNDLE_FACTORY_VALIDATION_PUBLIC_DIR_OPERATOR_SET="${HARNESS_BUNDLE_FACTORY_VALIDATION_PUBLIC_DIR+x}"
HARNESS_LDAP_DATA_DIR_OPERATOR_SET="${HARNESS_LDAP_DATA_DIR+x}"
HARNESS_LDAP_CONFIG_DIR_OPERATOR_SET="${HARNESS_LDAP_CONFIG_DIR+x}"
HARNESS_SHARED_JENKINS_STORAGE_DIR_OPERATOR_SET="${HARNESS_SHARED_JENKINS_STORAGE_DIR+x}"
HARNESS_GERRIT_EVIDENCE_DIR_OPERATOR_SET="${HARNESS_GERRIT_EVIDENCE_DIR+x}"
HARNESS_GERRIT_LOG_DIR_OPERATOR_SET="${HARNESS_GERRIT_LOG_DIR+x}"
HARNESS_JENKINS_CONTROLLER_EVIDENCE_DIR_OPERATOR_SET="${HARNESS_JENKINS_CONTROLLER_EVIDENCE_DIR+x}"
HARNESS_JENKINS_CONTROLLER_LOG_DIR_OPERATOR_SET="${HARNESS_JENKINS_CONTROLLER_LOG_DIR+x}"
HARNESS_JENKINS_AGENT_EVIDENCE_DIR_OPERATOR_SET="${HARNESS_JENKINS_AGENT_EVIDENCE_DIR+x}"
HARNESS_JENKINS_AGENT_LOG_DIR_OPERATOR_SET="${HARNESS_JENKINS_AGENT_LOG_DIR+x}"
HARNESS_ENV_FILE_OPERATOR_SET="${HARNESS_ENV_FILE+x}"
HARNESS_GERRIT_ENV_FILE_OPERATOR_SET="${HARNESS_GERRIT_ENV_FILE+x}"
HARNESS_JENKINS_CONTROLLER_ENV_FILE_OPERATOR_SET="${HARNESS_JENKINS_CONTROLLER_ENV_FILE+x}"
HARNESS_JENKINS_AGENT_ENV_FILE_OPERATOR_SET="${HARNESS_JENKINS_AGENT_ENV_FILE+x}"
HARNESS_INTEGRATION_ENV_FILE_OPERATOR_SET="${HARNESS_INTEGRATION_ENV_FILE+x}"
HARNESS_RUN_ID_OPERATOR_VALUE="${HARNESS_RUN_ID-}"
HARNESS_PROJECT_NAME_OPERATOR_VALUE="${HARNESS_PROJECT_NAME-}"
HARNESS_GENERATED_RUN_DIR_OPERATOR_VALUE="${HARNESS_GENERATED_RUN_DIR-}"
HARNESS_HOST_DIR_OPERATOR_VALUE="${HARNESS_HOST_DIR-}"
HARNESS_TARGET_DIR_OPERATOR_VALUE="${HARNESS_TARGET_DIR-}"
HARNESS_STATE_DIR_OPERATOR_VALUE="${HARNESS_STATE_DIR-}"
HARNESS_PRODUCT_HOME_DIR_OPERATOR_VALUE="${HARNESS_PRODUCT_HOME_DIR-}"
HARNESS_STAGING_DIR_OPERATOR_VALUE="${HARNESS_STAGING_DIR-}"
HARNESS_EXPORTED_ARTIFACT_DIR_OPERATOR_VALUE="${HARNESS_EXPORTED_ARTIFACT_DIR-}"
HARNESS_EVIDENCE_DIR_OPERATOR_VALUE="${HARNESS_EVIDENCE_DIR-}"
HARNESS_LOG_DIR_OPERATOR_VALUE="${HARNESS_LOG_DIR-}"
HARNESS_RETAINED_OUTPUT_BACKUP_DIR_OPERATOR_VALUE="${HARNESS_RETAINED_OUTPUT_BACKUP_DIR-}"
HARNESS_RENDERED_ENV_OPERATOR_VALUE="${HARNESS_RENDERED_ENV-}"
HARNESS_BASELINE_CONTRACT_OPERATOR_VALUE="${HARNESS_BASELINE_CONTRACT-}"
HARNESS_TARGET_SSH_DIR_OPERATOR_VALUE="${HARNESS_TARGET_SSH_DIR-}"
HARNESS_GERRIT_VALIDATION_SECRET_DIR_OPERATOR_VALUE="${HARNESS_GERRIT_VALIDATION_SECRET_DIR-}"
HARNESS_BUNDLE_FACTORY_RENDERED_DIR_OPERATOR_VALUE="${HARNESS_BUNDLE_FACTORY_RENDERED_DIR-}"
HARNESS_BUNDLE_FACTORY_VALIDATION_PUBLIC_DIR_OPERATOR_VALUE="${HARNESS_BUNDLE_FACTORY_VALIDATION_PUBLIC_DIR-}"
HARNESS_LDAP_DATA_DIR_OPERATOR_VALUE="${HARNESS_LDAP_DATA_DIR-}"
HARNESS_LDAP_CONFIG_DIR_OPERATOR_VALUE="${HARNESS_LDAP_CONFIG_DIR-}"
HARNESS_SHARED_JENKINS_STORAGE_DIR_OPERATOR_VALUE="${HARNESS_SHARED_JENKINS_STORAGE_DIR-}"
HARNESS_ENV_FILE_OPERATOR_VALUE="${HARNESS_ENV_FILE-}"
HARNESS_GERRIT_ENV_FILE_OPERATOR_VALUE="${HARNESS_GERRIT_ENV_FILE-}"
HARNESS_JENKINS_CONTROLLER_ENV_FILE_OPERATOR_VALUE="${HARNESS_JENKINS_CONTROLLER_ENV_FILE-}"
HARNESS_JENKINS_AGENT_ENV_FILE_OPERATOR_VALUE="${HARNESS_JENKINS_AGENT_ENV_FILE-}"
HARNESS_INTEGRATION_ENV_FILE_OPERATOR_VALUE="${HARNESS_INTEGRATION_ENV_FILE-}"
HARNESS_GERRIT_HTTP_HOST_PORT_OPERATOR_SET="${HARNESS_GERRIT_HTTP_HOST_PORT+x}"
HARNESS_JENKINS_HTTP_HOST_PORT_OPERATOR_SET="${HARNESS_JENKINS_HTTP_HOST_PORT+x}"
HARNESS_GERRIT_HTTP_HOST_PORT_OPERATOR_VALUE="${HARNESS_GERRIT_HTTP_HOST_PORT-}"
HARNESS_JENKINS_HTTP_HOST_PORT_OPERATOR_VALUE="${HARNESS_JENKINS_HTTP_HOST_PORT-}"
HARNESS_GERRIT_TARGET_SSH_HOST_PORT_OPERATOR_SET="${HARNESS_GERRIT_TARGET_SSH_HOST_PORT+x}"
HARNESS_JENKINS_CONTROLLER_TARGET_SSH_HOST_PORT_OPERATOR_SET="${HARNESS_JENKINS_CONTROLLER_TARGET_SSH_HOST_PORT+x}"
HARNESS_JENKINS_AGENT_TARGET_SSH_HOST_PORT_OPERATOR_SET="${HARNESS_JENKINS_AGENT_TARGET_SSH_HOST_PORT+x}"
HARNESS_GERRIT_TARGET_SSH_HOST_PORT_OPERATOR_VALUE="${HARNESS_GERRIT_TARGET_SSH_HOST_PORT-}"
HARNESS_JENKINS_CONTROLLER_TARGET_SSH_HOST_PORT_OPERATOR_VALUE="${HARNESS_JENKINS_CONTROLLER_TARGET_SSH_HOST_PORT-}"
HARNESS_JENKINS_AGENT_TARGET_SSH_HOST_PORT_OPERATOR_VALUE="${HARNESS_JENKINS_AGENT_TARGET_SSH_HOST_PORT-}"

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

HARNESS_GENERATED_RUN_DIR="${HARNESS_GENERATED_RUN_DIR:-$repo_root/generated/simulation/docker/$HARNESS_RUN_ID}"
HARNESS_HOST_DIR="${HARNESS_HOST_DIR:-$HARNESS_GENERATED_RUN_DIR/host}"
HARNESS_TARGET_DIR="${HARNESS_TARGET_DIR:-$HARNESS_GENERATED_RUN_DIR/target}"
HARNESS_STATE_DIR="${HARNESS_STATE_DIR:-$HARNESS_TARGET_DIR/helper-state}"
HARNESS_PRODUCT_HOME_DIR="${HARNESS_PRODUCT_HOME_DIR:-$HARNESS_TARGET_DIR/product-homes}"
HARNESS_STAGING_DIR="${HARNESS_STAGING_DIR:-$HARNESS_TARGET_DIR/artifacts/staging}"
HARNESS_EXPORTED_ARTIFACT_DIR="${HARNESS_EXPORTED_ARTIFACT_DIR:-$HARNESS_TARGET_DIR/artifacts/exported}"
HARNESS_EVIDENCE_DIR="${HARNESS_EVIDENCE_DIR:-$HARNESS_HOST_DIR/evidence/harness}"
HARNESS_LOG_DIR="${HARNESS_LOG_DIR:-$HARNESS_HOST_DIR/logs/harness}"
HARNESS_RETAINED_OUTPUT_BACKUP_DIR="${HARNESS_RETAINED_OUTPUT_BACKUP_DIR:-$HARNESS_HOST_DIR/retained-output-backups}"
HARNESS_INTEGRATION_ENV_FILE="${HARNESS_INTEGRATION_ENV_FILE:-$repo_root/examples/integration.env.example}"
HARNESS_GERRIT_ENV_FILE="${HARNESS_GERRIT_ENV_FILE:-$repo_root/examples/gerrit.env.example}"
HARNESS_JENKINS_CONTROLLER_ENV_FILE="${HARNESS_JENKINS_CONTROLLER_ENV_FILE:-$repo_root/examples/jenkins-controller.env.example}"
HARNESS_JENKINS_AGENT_ENV_FILE="${HARNESS_JENKINS_AGENT_ENV_FILE:-$repo_root/examples/jenkins-agent.env.example}"
HARNESS_JENKINS_SHARED_STORAGE_PATH="${HARNESS_JENKINS_SHARED_STORAGE_PATH:-}"
HARNESS_ENV_FILE="${HARNESS_ENV_FILE:-$HARNESS_ENV_FILE_OPERATOR_VALUE}"
HARNESS_RENDERED_ENV="${HARNESS_RENDERED_ENV:-$HARNESS_HOST_DIR/rendered/harness.env}"
HARNESS_RUNTIME_ENV="${HARNESS_RUNTIME_ENV:-${HARNESS_RENDERED_ENV%.env}.runtime.env}"
HARNESS_RUNTIME_INPUT_DIR="${HARNESS_RUNTIME_INPUT_DIR:-$HARNESS_HOST_DIR/runtime-inputs}"
HARNESS_BASELINE_CONTRACT="${HARNESS_BASELINE_CONTRACT:-$HARNESS_HOST_DIR/rendered/artifact-manifest-contract.txt}"
HARNESS_TARGET_SSH_DIR="${HARNESS_TARGET_SSH_DIR:-$HARNESS_HOST_DIR/target-ssh}"
HARNESS_TARGET_SSH_IDENTITY_FILE="${HARNESS_TARGET_SSH_IDENTITY_FILE:-$HARNESS_TARGET_SSH_DIR/ci-operator}"
HARNESS_TARGET_SSH_KNOWN_HOSTS_FILE="${HARNESS_TARGET_SSH_KNOWN_HOSTS_FILE:-$HARNESS_TARGET_SSH_DIR/known_hosts}"
HARNESS_GERRIT_VALIDATION_SECRET_DIR="${HARNESS_GERRIT_VALIDATION_SECRET_DIR:-$HARNESS_HOST_DIR/validation-secrets/gerrit}"
HARNESS_BUNDLE_FACTORY_RENDERED_DIR="${HARNESS_BUNDLE_FACTORY_RENDERED_DIR:-$HARNESS_HOST_DIR/bundle-factory/rendered}"
HARNESS_BUNDLE_FACTORY_VALIDATION_PUBLIC_DIR="${HARNESS_BUNDLE_FACTORY_VALIDATION_PUBLIC_DIR:-$HARNESS_HOST_DIR/bundle-factory/validation-public}"
HARNESS_LDAP_DATA_DIR="${HARNESS_LDAP_DATA_DIR:-$HARNESS_TARGET_DIR/ldap/data}"
HARNESS_LDAP_CONFIG_DIR="${HARNESS_LDAP_CONFIG_DIR:-$HARNESS_TARGET_DIR/ldap/config}"
HARNESS_SHARED_JENKINS_STORAGE_DIR="${HARNESS_SHARED_JENKINS_STORAGE_DIR:-$HARNESS_TARGET_DIR/shared-jenkins-storage}"
HARNESS_GERRIT_EVIDENCE_DIR="${HARNESS_GERRIT_EVIDENCE_DIR:-$HARNESS_TARGET_DIR/evidence/gerrit}"
HARNESS_GERRIT_LOG_DIR="${HARNESS_GERRIT_LOG_DIR:-$HARNESS_TARGET_DIR/logs/gerrit}"
HARNESS_JENKINS_CONTROLLER_EVIDENCE_DIR="${HARNESS_JENKINS_CONTROLLER_EVIDENCE_DIR:-$HARNESS_TARGET_DIR/evidence/jenkins-controller}"
HARNESS_JENKINS_CONTROLLER_LOG_DIR="${HARNESS_JENKINS_CONTROLLER_LOG_DIR:-$HARNESS_TARGET_DIR/logs/jenkins-controller}"
HARNESS_JENKINS_AGENT_EVIDENCE_DIR="${HARNESS_JENKINS_AGENT_EVIDENCE_DIR:-$HARNESS_TARGET_DIR/evidence/jenkins-agent}"
HARNESS_JENKINS_AGENT_LOG_DIR="${HARNESS_JENKINS_AGENT_LOG_DIR:-$HARNESS_TARGET_DIR/logs/jenkins-agent}"

export HARNESS_MODE HARNESS_RUN_ID HARNESS_PROJECT_NAME
export HARNESS_UBUNTU_IMAGE HARNESS_LDAP_IMAGE
export HARNESS_LDAP_DOMAIN HARNESS_LDAP_BASE_DN
export HARNESS_LDAP_ADMIN_PASSWORD HARNESS_LDAP_CONFIG_PASSWORD
export HARNESS_LDAP_BIND_USER HARNESS_LDAP_BIND_PASSWORD
export HARNESS_PUBLIC_INTERNET_FALLBACK_LABEL
export HARNESS_GENERATED_RUN_DIR HARNESS_HOST_DIR HARNESS_TARGET_DIR
export HARNESS_STATE_DIR HARNESS_PRODUCT_HOME_DIR
export HARNESS_STAGING_DIR HARNESS_EXPORTED_ARTIFACT_DIR
export HARNESS_EVIDENCE_DIR HARNESS_LOG_DIR HARNESS_RETAINED_OUTPUT_BACKUP_DIR
export HARNESS_JENKINS_SHARED_STORAGE_PATH HARNESS_ENV_FILE
export HARNESS_GERRIT_ENV_FILE HARNESS_JENKINS_CONTROLLER_ENV_FILE
export HARNESS_JENKINS_AGENT_ENV_FILE HARNESS_INTEGRATION_ENV_FILE
export HARNESS_TARGET_SSH_DIR HARNESS_TARGET_SSH_IDENTITY_FILE
export HARNESS_TARGET_SSH_KNOWN_HOSTS_FILE
export HARNESS_GERRIT_VALIDATION_SECRET_DIR HARNESS_BUNDLE_FACTORY_RENDERED_DIR
export HARNESS_BUNDLE_FACTORY_VALIDATION_PUBLIC_DIR HARNESS_LDAP_DATA_DIR
export HARNESS_LDAP_CONFIG_DIR HARNESS_SHARED_JENKINS_STORAGE_DIR
export HARNESS_GERRIT_EVIDENCE_DIR HARNESS_GERRIT_LOG_DIR
export HARNESS_JENKINS_CONTROLLER_EVIDENCE_DIR HARNESS_JENKINS_CONTROLLER_LOG_DIR
export HARNESS_JENKINS_AGENT_EVIDENCE_DIR HARNESS_JENKINS_AGENT_LOG_DIR

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
  if [ -n "$HARNESS_GENERATED_RUN_DIR_OPERATOR_SET" ] ||
    [ -n "$HARNESS_HOST_DIR_OPERATOR_SET" ] ||
    [ -n "$HARNESS_TARGET_DIR_OPERATOR_SET" ] ||
    [ -n "$HARNESS_STATE_DIR_OPERATOR_SET" ] ||
    [ -n "$HARNESS_PRODUCT_HOME_DIR_OPERATOR_SET" ] ||
    [ -n "$HARNESS_STAGING_DIR_OPERATOR_SET" ] ||
    [ -n "$HARNESS_EXPORTED_ARTIFACT_DIR_OPERATOR_SET" ] ||
    [ -n "$HARNESS_EVIDENCE_DIR_OPERATOR_SET" ] ||
    [ -n "$HARNESS_LOG_DIR_OPERATOR_SET" ] ||
    [ -n "$HARNESS_RETAINED_OUTPUT_BACKUP_DIR_OPERATOR_SET" ] ||
    [ -n "$HARNESS_RENDERED_ENV_OPERATOR_SET" ] ||
    [ -n "$HARNESS_BASELINE_CONTRACT_OPERATOR_SET" ] ||
    [ -n "$HARNESS_TARGET_SSH_DIR_OPERATOR_SET" ] ||
    [ -n "$HARNESS_GERRIT_VALIDATION_SECRET_DIR_OPERATOR_SET" ] ||
    [ -n "$HARNESS_BUNDLE_FACTORY_RENDERED_DIR_OPERATOR_SET" ] ||
    [ -n "$HARNESS_BUNDLE_FACTORY_VALIDATION_PUBLIC_DIR_OPERATOR_SET" ] ||
    [ -n "$HARNESS_LDAP_DATA_DIR_OPERATOR_SET" ] ||
    [ -n "$HARNESS_LDAP_CONFIG_DIR_OPERATOR_SET" ] ||
    [ -n "$HARNESS_SHARED_JENKINS_STORAGE_DIR_OPERATOR_SET" ] ||
    [ -n "$HARNESS_GERRIT_EVIDENCE_DIR_OPERATOR_SET" ] ||
    [ -n "$HARNESS_GERRIT_LOG_DIR_OPERATOR_SET" ] ||
    [ -n "$HARNESS_JENKINS_CONTROLLER_EVIDENCE_DIR_OPERATOR_SET" ] ||
    [ -n "$HARNESS_JENKINS_CONTROLLER_LOG_DIR_OPERATOR_SET" ] ||
    [ -n "$HARNESS_JENKINS_AGENT_EVIDENCE_DIR_OPERATOR_SET" ] ||
    [ -n "$HARNESS_JENKINS_AGENT_LOG_DIR_OPERATOR_SET" ]; then
    die "Docker harness output paths are fixed under generated/simulation/docker/<run-id> for v1; unset HARNESS_* output path overrides"
  fi
  unset HARNESS_GENERATED_RUN_DIR HARNESS_HOST_DIR HARNESS_TARGET_DIR
  unset HARNESS_STATE_DIR HARNESS_PRODUCT_HOME_DIR
  unset HARNESS_STAGING_DIR HARNESS_EXPORTED_ARTIFACT_DIR
  unset HARNESS_EVIDENCE_DIR HARNESS_LOG_DIR HARNESS_RETAINED_OUTPUT_BACKUP_DIR
  unset HARNESS_RENDERED_ENV HARNESS_RUNTIME_ENV HARNESS_RUNTIME_INPUT_DIR HARNESS_BASELINE_CONTRACT HARNESS_RUN_MARKER
  unset HARNESS_TARGET_SSH_DIR HARNESS_TARGET_SSH_IDENTITY_FILE HARNESS_TARGET_SSH_KNOWN_HOSTS_FILE
  unset HARNESS_GERRIT_VALIDATION_SECRET_DIR HARNESS_BUNDLE_FACTORY_RENDERED_DIR
  unset HARNESS_BUNDLE_FACTORY_VALIDATION_PUBLIC_DIR HARNESS_LDAP_DATA_DIR
  unset HARNESS_LDAP_CONFIG_DIR HARNESS_SHARED_JENKINS_STORAGE_DIR
  unset HARNESS_GERRIT_EVIDENCE_DIR HARNESS_GERRIT_LOG_DIR
  unset HARNESS_JENKINS_CONTROLLER_EVIDENCE_DIR HARNESS_JENKINS_CONTROLLER_LOG_DIR
  unset HARNESS_JENKINS_AGENT_EVIDENCE_DIR HARNESS_JENKINS_AGENT_LOG_DIR
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
  if [ -n "$HARNESS_GERRIT_HTTP_HOST_PORT_OPERATOR_SET" ]; then
    HARNESS_GERRIT_HTTP_HOST_PORT="$HARNESS_GERRIT_HTTP_HOST_PORT_OPERATOR_VALUE"
  fi
  if [ -n "$HARNESS_JENKINS_HTTP_HOST_PORT_OPERATOR_SET" ]; then
    HARNESS_JENKINS_HTTP_HOST_PORT="$HARNESS_JENKINS_HTTP_HOST_PORT_OPERATOR_VALUE"
  fi
  if [ -n "$HARNESS_GERRIT_TARGET_SSH_HOST_PORT_OPERATOR_SET" ]; then
    HARNESS_GERRIT_TARGET_SSH_HOST_PORT="$HARNESS_GERRIT_TARGET_SSH_HOST_PORT_OPERATOR_VALUE"
  fi
  if [ -n "$HARNESS_JENKINS_CONTROLLER_TARGET_SSH_HOST_PORT_OPERATOR_SET" ]; then
    HARNESS_JENKINS_CONTROLLER_TARGET_SSH_HOST_PORT="$HARNESS_JENKINS_CONTROLLER_TARGET_SSH_HOST_PORT_OPERATOR_VALUE"
  fi
  if [ -n "$HARNESS_JENKINS_AGENT_TARGET_SSH_HOST_PORT_OPERATOR_SET" ]; then
    HARNESS_JENKINS_AGENT_TARGET_SSH_HOST_PORT="$HARNESS_JENKINS_AGENT_TARGET_SSH_HOST_PORT_OPERATOR_VALUE"
  fi
  HARNESS_ENV_FILE="$file"
  reject_custom_output_paths
  apply_canonical_output_paths
  export HARNESS_ENV_FILE
  export HARNESS_GERRIT_ENV_FILE HARNESS_JENKINS_CONTROLLER_ENV_FILE
  export HARNESS_JENKINS_AGENT_ENV_FILE HARNESS_INTEGRATION_ENV_FILE
}

reapply_operator_overrides() {
  if [ -n "$HARNESS_GERRIT_HTTP_HOST_PORT_OPERATOR_SET" ]; then
    HARNESS_GERRIT_HTTP_HOST_PORT="$HARNESS_GERRIT_HTTP_HOST_PORT_OPERATOR_VALUE"
  fi
  if [ -n "$HARNESS_JENKINS_HTTP_HOST_PORT_OPERATOR_SET" ]; then
    HARNESS_JENKINS_HTTP_HOST_PORT="$HARNESS_JENKINS_HTTP_HOST_PORT_OPERATOR_VALUE"
  fi
  if [ -n "$HARNESS_GERRIT_TARGET_SSH_HOST_PORT_OPERATOR_SET" ]; then
    HARNESS_GERRIT_TARGET_SSH_HOST_PORT="$HARNESS_GERRIT_TARGET_SSH_HOST_PORT_OPERATOR_VALUE"
  fi
  if [ -n "$HARNESS_JENKINS_CONTROLLER_TARGET_SSH_HOST_PORT_OPERATOR_SET" ]; then
    HARNESS_JENKINS_CONTROLLER_TARGET_SSH_HOST_PORT="$HARNESS_JENKINS_CONTROLLER_TARGET_SSH_HOST_PORT_OPERATOR_VALUE"
  fi
  if [ -n "$HARNESS_JENKINS_AGENT_TARGET_SSH_HOST_PORT_OPERATOR_SET" ]; then
    HARNESS_JENKINS_AGENT_TARGET_SSH_HOST_PORT="$HARNESS_JENKINS_AGENT_TARGET_SSH_HOST_PORT_OPERATOR_VALUE"
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
  reject_custom_output_paths
  apply_canonical_output_paths
  export HARNESS_HOST_DIR HARNESS_TARGET_DIR HARNESS_STATE_DIR
  export HARNESS_PRODUCT_HOME_DIR HARNESS_RENDERED_ENV HARNESS_RUNTIME_ENV
  export HARNESS_RUNTIME_INPUT_DIR HARNESS_BASELINE_CONTRACT
  export HARNESS_TARGET_SSH_DIR HARNESS_GERRIT_VALIDATION_SECRET_DIR
  export HARNESS_BUNDLE_FACTORY_RENDERED_DIR
  export HARNESS_BUNDLE_FACTORY_VALIDATION_PUBLIC_DIR
  export HARNESS_LDAP_DATA_DIR HARNESS_LDAP_CONFIG_DIR
  export HARNESS_SHARED_JENKINS_STORAGE_DIR
  export HARNESS_RETAINED_OUTPUT_BACKUP_DIR
}

ensure_runtime_config() {
  if [ -n "$HARNESS_RENDERED_ENV_OPERATOR_SET" ] && load_rendered_config_if_present; then
    verify_run_marker
    validate_core_generated_state
    return 0
  fi
  if load_rendered_config_if_present; then
    verify_run_marker
    validate_core_generated_state
    return 0
  fi
  if selected_containers_exist; then
    die "Docker generated state is missing while selected containers exist; run down or clean before resuming"
  fi
  die "Missing Docker harness runtime config: run init-run first"
}

runtime_config_valid() {
  (
    load_rendered_config_if_present &&
    verify_run_marker >/dev/null 2>&1 &&
    validate_core_generated_state >/dev/null 2>&1
  ) >/dev/null 2>&1
}

generated_runtime_state_present() {
  [ -e "$HARNESS_RUN_MARKER" ] ||
    [ -e "$HARNESS_RENDERED_ENV" ] ||
    [ -e "$HARNESS_RUNTIME_ENV" ] ||
    [ -e "$HARNESS_RUNTIME_INPUT_DIR" ] ||
    [ -e "$HARNESS_HOST_DIR/rendered" ]
}

verify_selected_container_mounts() {
  validate_selected_container_mounts
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

ensure_target_ssh_keypair() {
  require_command ssh-keygen
  mkdir -p "$HARNESS_TARGET_SSH_DIR"
  chmod 0700 "$HARNESS_TARGET_SSH_DIR"
  if [ ! -s "$HARNESS_TARGET_SSH_IDENTITY_FILE" ]; then
    ssh-keygen -q -t ed25519 -N '' -C "loopforge-$HARNESS_RUN_ID-target-ssh" \
      -f "$HARNESS_TARGET_SSH_IDENTITY_FILE"
  fi
  chmod 0600 "$HARNESS_TARGET_SSH_IDENTITY_FILE"
  ssh-keygen -y -f "$HARNESS_TARGET_SSH_IDENTITY_FILE" >"$HARNESS_TARGET_SSH_IDENTITY_FILE.pub"
  chmod 0644 "$HARNESS_TARGET_SSH_IDENTITY_FILE.pub"
  if [ ! -e "$HARNESS_TARGET_SSH_KNOWN_HOSTS_FILE" ]; then
    : >"$HARNESS_TARGET_SSH_KNOWN_HOSTS_FILE"
    chmod 0600 "$HARNESS_TARGET_SSH_KNOWN_HOSTS_FILE"
  fi
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
  HARNESS_RUNTIME_INPUT_DIR="$HARNESS_HOST_DIR/runtime-inputs"
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
  set_env_file_value "$HARNESS_INTEGRATION_ENV_FILE" INTEGRATION_MODE "$HARNESS_MODE"
  set_env_file_value "$HARNESS_INTEGRATION_ENV_FILE" INTEGRATION_STATE_DIR "$HARNESS_STATE_DIR/integration"
  set_env_file_value "$HARNESS_INTEGRATION_ENV_FILE" INTEGRATION_LOG_DIR "$HARNESS_HOST_DIR/logs/integration"
  set_env_file_value "$HARNESS_INTEGRATION_ENV_FILE" INTEGRATION_EVIDENCE_DIR "$HARNESS_HOST_DIR/evidence/integration"
  set_env_file_value "$HARNESS_INTEGRATION_ENV_FILE" INTEGRATION_GERRIT_TARGET_SSH_HOST "127.0.0.1"
  set_env_file_value "$HARNESS_INTEGRATION_ENV_FILE" INTEGRATION_GERRIT_TARGET_SSH_PORT "$HARNESS_GERRIT_TARGET_SSH_HOST_PORT"
  set_env_file_value "$HARNESS_INTEGRATION_ENV_FILE" INTEGRATION_GERRIT_TARGET_SSH_USER "ci-operator"
  set_env_file_value "$HARNESS_INTEGRATION_ENV_FILE" INTEGRATION_GERRIT_TARGET_SSH_IDENTITY_FILE "$HARNESS_TARGET_SSH_IDENTITY_FILE"
  set_env_file_value "$HARNESS_INTEGRATION_ENV_FILE" INTEGRATION_GERRIT_TARGET_SSH_KNOWN_HOSTS_FILE "$HARNESS_TARGET_SSH_KNOWN_HOSTS_FILE"
  set_env_file_value "$HARNESS_INTEGRATION_ENV_FILE" INTEGRATION_JENKINS_CONTROLLER_TARGET_SSH_HOST "127.0.0.1"
  set_env_file_value "$HARNESS_INTEGRATION_ENV_FILE" INTEGRATION_JENKINS_CONTROLLER_TARGET_SSH_PORT "$HARNESS_JENKINS_CONTROLLER_TARGET_SSH_HOST_PORT"
  set_env_file_value "$HARNESS_INTEGRATION_ENV_FILE" INTEGRATION_JENKINS_CONTROLLER_TARGET_SSH_USER "ci-operator"
  set_env_file_value "$HARNESS_INTEGRATION_ENV_FILE" INTEGRATION_JENKINS_CONTROLLER_TARGET_SSH_IDENTITY_FILE "$HARNESS_TARGET_SSH_IDENTITY_FILE"
  set_env_file_value "$HARNESS_INTEGRATION_ENV_FILE" INTEGRATION_JENKINS_CONTROLLER_TARGET_SSH_KNOWN_HOSTS_FILE "$HARNESS_TARGET_SSH_KNOWN_HOSTS_FILE"
  set_env_file_value "$HARNESS_INTEGRATION_ENV_FILE" INTEGRATION_JENKINS_AGENT_TARGET_SSH_HOST "127.0.0.1"
  set_env_file_value "$HARNESS_INTEGRATION_ENV_FILE" INTEGRATION_JENKINS_AGENT_TARGET_SSH_PORT "$HARNESS_JENKINS_AGENT_TARGET_SSH_HOST_PORT"
  set_env_file_value "$HARNESS_INTEGRATION_ENV_FILE" INTEGRATION_JENKINS_AGENT_TARGET_SSH_USER "ci-operator"
  set_env_file_value "$HARNESS_INTEGRATION_ENV_FILE" INTEGRATION_JENKINS_AGENT_TARGET_SSH_IDENTITY_FILE "$HARNESS_TARGET_SSH_IDENTITY_FILE"
  set_env_file_value "$HARNESS_INTEGRATION_ENV_FILE" INTEGRATION_JENKINS_AGENT_TARGET_SSH_KNOWN_HOSTS_FILE "$HARNESS_TARGET_SSH_KNOWN_HOSTS_FILE"
  set_env_file_value "$HARNESS_INTEGRATION_ENV_FILE" INTEGRATION_GERRIT_ACL_MODE "apply-direct"
  set_env_file_value "$HARNESS_INTEGRATION_ENV_FILE" INTEGRATION_ALLOW_SIMULATION_DIRECT_ACL_APPLY "1"
  export HARNESS_ENV_FILE HARNESS_RUNTIME_INPUT_DIR
  export HARNESS_GERRIT_ENV_FILE HARNESS_JENKINS_CONTROLLER_ENV_FILE
  export HARNESS_JENKINS_AGENT_ENV_FILE HARNESS_INTEGRATION_ENV_FILE
}

validate_init_run_inputs() {
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
    die "Inconsistent Docker container state: $container is missing mount destination $destination; run down or clean before resuming"
  [ -e "$source" ] ||
    die "Stale Docker bind mount for $container:$destination: host source is missing ($source); run down or clean before resuming"
  [ -e "$expected" ] ||
    die "Inconsistent Docker generated state: expected bind source is missing: $expected"
  source_real="$(realpath "$source")"
  expected_real="$(realpath "$expected")"
  [ "$source_real" = "$expected_real" ] ||
    die "Stale Docker bind mount for $container:$destination: source $source is not selected run path $expected; run down or clean before resuming"
  case "$source_real" in
    "$HARNESS_GENERATED_RUN_DIR"|"$HARNESS_GENERATED_RUN_DIR"/*) ;;
    *)
      die "Stale Docker bind mount for $container:$destination: source is outside selected run root; run down or clean before resuming"
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
    die "Inconsistent Docker container state: $container is missing mount destination $destination; run down or clean before resuming"
  [ -e "$source" ] ||
    die "Stale Docker bind mount for $container:$destination: host source is missing ($source); run down or clean before resuming"
  [ -e "$expected" ] ||
    die "Inconsistent Docker generated state: expected bind source is missing: $expected"
  source_real="$(realpath "$source")"
  expected_real="$(realpath "$expected")"
  [ "$source_real" = "$expected_real" ] ||
    die "Stale Docker bind mount for $container:$destination: source $source is not expected path $expected; run down or clean before resuming"
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
    die "Stale Docker bind mount for $container:$destination: destination is not visible in the container; run down or clean before resuming"
  fi
  [ "$container_identity" = "$host_identity" ] ||
    die "Stale Docker bind mount for $container:$destination: host and container mount identity differ; run down or clean before resuming"
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
  validate_container_mount bundle-factory "$HARNESS_BUNDLE_FACTORY_RENDERED_DIR" /var/lib/loopforge/rendered
  validate_container_mount bundle-factory "$HARNESS_STATE_DIR/bundle-factory/evidence" /var/lib/loopforge/evidence
  validate_container_mount bundle-factory "$HARNESS_STATE_DIR/bundle-factory/preparing" /var/lib/loopforge/preparing
  validate_container_mount ldap "$HARNESS_LDAP_DATA_DIR" /var/lib/ldap
  validate_container_mount ldap "$HARNESS_LDAP_CONFIG_DIR" /etc/ldap/slapd.d
  validate_container_mount gerrit-target "$repo_root" /workspace repo
  validate_container_mount gerrit-target "$HARNESS_STATE_DIR/gerrit" /var/lib/loopforge
  validate_container_mount gerrit-target "$HARNESS_PRODUCT_HOME_DIR/gerrit" /srv/gerrit
  validate_container_mount gerrit-target "$HARNESS_TARGET_SSH_DIR" /var/lib/loopforge/target-ssh generated
  validate_container_mount gerrit-target "$HARNESS_GERRIT_VALIDATION_SECRET_DIR" /var/lib/loopforge/validation-secrets
  validate_container_mount gerrit-target "$HARNESS_GERRIT_EVIDENCE_DIR" /var/lib/loopforge/evidence
  validate_container_mount gerrit-target "$HARNESS_GERRIT_LOG_DIR" /var/log/loopforge
  validate_container_mount jenkins-controller-target "$repo_root" /workspace repo
  validate_container_mount jenkins-controller-target "$HARNESS_STATE_DIR/jenkins-controller" /var/lib/loopforge
  validate_container_mount jenkins-controller-target "$HARNESS_PRODUCT_HOME_DIR/jenkins-controller" /var/lib/jenkins
  validate_container_mount jenkins-controller-target "$HARNESS_TARGET_SSH_DIR" /var/lib/loopforge/target-ssh generated
  validate_container_mount jenkins-controller-target "$HARNESS_SHARED_JENKINS_STORAGE_DIR" "$HARNESS_JENKINS_SHARED_STORAGE_PATH"
  validate_container_mount jenkins-controller-target "$HARNESS_JENKINS_CONTROLLER_EVIDENCE_DIR" /var/lib/loopforge/evidence
  validate_container_mount jenkins-controller-target "$HARNESS_JENKINS_CONTROLLER_LOG_DIR" /var/log/loopforge
  validate_container_mount jenkins-agent-target "$repo_root" /workspace repo
  validate_container_mount jenkins-agent-target "$HARNESS_STATE_DIR/jenkins-agent" /var/lib/loopforge
  validate_container_mount jenkins-agent-target "$HARNESS_PRODUCT_HOME_DIR/jenkins-agent" /var/lib/jenkins-agent
  validate_container_mount jenkins-agent-target "$HARNESS_TARGET_SSH_DIR" /var/lib/loopforge/target-ssh generated
  validate_container_mount jenkins-agent-target "$HARNESS_SHARED_JENKINS_STORAGE_DIR" "$HARNESS_JENKINS_SHARED_STORAGE_PATH"
  validate_container_mount jenkins-agent-target "$HARNESS_JENKINS_AGENT_EVIDENCE_DIR" /var/lib/loopforge/evidence
  validate_container_mount jenkins-agent-target "$HARNESS_JENKINS_AGENT_LOG_DIR" /var/log/loopforge
}

ensure_preflight_dirs() {
  validate_harness_inputs
  mkdir -p \
    "$HARNESS_EVIDENCE_DIR" \
    "$HARNESS_LOG_DIR" \
    "$HARNESS_RETAINED_OUTPUT_BACKUP_DIR"
}

ensure_dirs() {
  validate_harness_inputs
  validate_product_home_dir
  ensure_preflight_dirs
  mkdir -p \
    "$HARNESS_STATE_DIR" \
    "$HARNESS_HOST_DIR" \
    "$HARNESS_TARGET_DIR" \
    "$HARNESS_HOST_DIR/evidence" \
    "$HARNESS_HOST_DIR/logs" \
    "$HARNESS_RETAINED_OUTPUT_BACKUP_DIR" \
    "$HARNESS_PRODUCT_HOME_DIR" \
    "$HARNESS_PRODUCT_HOME_DIR/gerrit" \
    "$HARNESS_PRODUCT_HOME_DIR/jenkins-controller" \
    "$HARNESS_PRODUCT_HOME_DIR/jenkins-agent" \
    "$HARNESS_STAGING_DIR" \
    "$HARNESS_EXPORTED_ARTIFACT_DIR" \
    "$HARNESS_BUNDLE_FACTORY_RENDERED_DIR" \
    "$HARNESS_STATE_DIR/bundle-factory/evidence" \
    "$HARNESS_STATE_DIR/bundle-factory/preparing" \
    "$HARNESS_BUNDLE_FACTORY_VALIDATION_PUBLIC_DIR" \
    "$HARNESS_LDAP_DATA_DIR" \
    "$HARNESS_LDAP_CONFIG_DIR" \
    "$HARNESS_STATE_DIR/gerrit" \
    "$HARNESS_STATE_DIR/jenkins-controller" \
    "$HARNESS_STATE_DIR/jenkins-agent" \
    "$HARNESS_STATE_DIR/integration" \
    "$HARNESS_GERRIT_EVIDENCE_DIR" \
    "$HARNESS_GERRIT_LOG_DIR" \
    "$HARNESS_JENKINS_CONTROLLER_EVIDENCE_DIR" \
    "$HARNESS_JENKINS_CONTROLLER_LOG_DIR" \
    "$HARNESS_JENKINS_AGENT_EVIDENCE_DIR" \
    "$HARNESS_JENKINS_AGENT_LOG_DIR" \
    "$HARNESS_GERRIT_VALIDATION_SECRET_DIR" \
    "$HARNESS_SHARED_JENKINS_STORAGE_DIR" \
    "$HARNESS_TARGET_SSH_DIR" \
    "$(dirname "$HARNESS_RENDERED_ENV")" \
    "$HARNESS_STAGING_DIR/gerrit" \
    "$HARNESS_STAGING_DIR/jenkins-controller" \
    "$HARNESS_STAGING_DIR/jenkins-agent"
  chmod 0700 "$HARNESS_GERRIT_VALIDATION_SECRET_DIR"
}

prepare_init_run() {
  validate_harness_inputs
  validate_init_run_inputs
  resolve_browser_ports
  ensure_target_ssh_keypair
  copy_runtime_env_inputs
  load_harness_integration_env
  ensure_dirs
  write_rendered_helper_envs
}

role_evidence_dir() {
  case "${1:?role required}" in
    gerrit) printf '%s\n' "$HARNESS_GERRIT_EVIDENCE_DIR" ;;
    jenkins-controller) printf '%s\n' "$HARNESS_JENKINS_CONTROLLER_EVIDENCE_DIR" ;;
    jenkins-agent) printf '%s\n' "$HARNESS_JENKINS_AGENT_EVIDENCE_DIR" ;;
    *) printf '%s\n' "$HARNESS_EVIDENCE_DIR" ;;
  esac
}

role_log_dir() {
  case "${1:?role required}" in
    gerrit) printf '%s\n' "$HARNESS_GERRIT_LOG_DIR" ;;
    jenkins-controller) printf '%s\n' "$HARNESS_JENKINS_CONTROLLER_LOG_DIR" ;;
    jenkins-agent) printf '%s\n' "$HARNESS_JENKINS_AGENT_LOG_DIR" ;;
    *) printf '%s\n' "$HARNESS_LOG_DIR" ;;
  esac
}

evidence_dir_for_record() {
  local checkpoint role
  checkpoint="${1:?checkpoint required}"
  role="${2:?role required}"
  printf '%s\n' "$HARNESS_EVIDENCE_DIR"
}

bounded_log_dir_for_name() {
  local name
  name="${1:?log name required}"
  printf '%s\n' "$HARNESS_LOG_DIR"
}

bounded_log_path() {
  local name dir
  name="${1:?log name required}"
  dir="$(bounded_log_dir_for_name "$name")"
  mkdir -p "$dir"
  printf '%s/%s-%s.log' "$dir" "$name" "$(timestamp_utc)"
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

service_for_loopback_port_name() {
  case "$1" in
    HARNESS_GERRIT_HTTP_HOST_PORT) printf '%s\n' gerrit-target ;;
    HARNESS_JENKINS_HTTP_HOST_PORT) printf '%s\n' jenkins-controller-target ;;
    HARNESS_GERRIT_TARGET_SSH_HOST_PORT) printf '%s\n' gerrit-target ;;
    HARNESS_JENKINS_CONTROLLER_TARGET_SSH_HOST_PORT) printf '%s\n' jenkins-controller-target ;;
    HARNESS_JENKINS_AGENT_TARGET_SSH_HOST_PORT) printf '%s\n' jenkins-agent-target ;;
    *) die "Unknown loopback port name: $1" ;;
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
  service="$(service_for_loopback_port_name "$name")"
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
  local gerrit_requested jenkins_requested gerrit_ssh_requested jenkins_controller_ssh_requested jenkins_agent_ssh_requested
  gerrit_requested="${HARNESS_GERRIT_HTTP_HOST_PORT:-}"
  jenkins_requested="${HARNESS_JENKINS_HTTP_HOST_PORT:-}"
  gerrit_ssh_requested="${HARNESS_GERRIT_TARGET_SSH_HOST_PORT:-}"
  jenkins_controller_ssh_requested="${HARNESS_JENKINS_CONTROLLER_TARGET_SSH_HOST_PORT:-}"
  jenkins_agent_ssh_requested="${HARNESS_JENKINS_AGENT_TARGET_SSH_HOST_PORT:-}"

  HARNESS_GERRIT_HTTP_HOST_PORT="$(resolve_browser_port HARNESS_GERRIT_HTTP_HOST_PORT "$gerrit_requested" "")"
  HARNESS_JENKINS_HTTP_HOST_PORT="$(resolve_browser_port HARNESS_JENKINS_HTTP_HOST_PORT "$jenkins_requested" "$HARNESS_GERRIT_HTTP_HOST_PORT")"
  HARNESS_GERRIT_TARGET_SSH_HOST_PORT="$(resolve_browser_port HARNESS_GERRIT_TARGET_SSH_HOST_PORT "$gerrit_ssh_requested" "$HARNESS_JENKINS_HTTP_HOST_PORT")"
  HARNESS_JENKINS_CONTROLLER_TARGET_SSH_HOST_PORT="$(resolve_browser_port HARNESS_JENKINS_CONTROLLER_TARGET_SSH_HOST_PORT "$jenkins_controller_ssh_requested" "$HARNESS_GERRIT_TARGET_SSH_HOST_PORT")"
  HARNESS_JENKINS_AGENT_TARGET_SSH_HOST_PORT="$(resolve_browser_port HARNESS_JENKINS_AGENT_TARGET_SSH_HOST_PORT "$jenkins_agent_ssh_requested" "$HARNESS_JENKINS_CONTROLLER_TARGET_SSH_HOST_PORT")"

  [ "$HARNESS_GERRIT_HTTP_HOST_PORT" != "$HARNESS_JENKINS_HTTP_HOST_PORT" ] ||
    die "HARNESS_GERRIT_HTTP_HOST_PORT and HARNESS_JENKINS_HTTP_HOST_PORT must be different"
  [ "$HARNESS_GERRIT_TARGET_SSH_HOST_PORT" != "$HARNESS_JENKINS_CONTROLLER_TARGET_SSH_HOST_PORT" ] ||
    die "HARNESS_GERRIT_TARGET_SSH_HOST_PORT and HARNESS_JENKINS_CONTROLLER_TARGET_SSH_HOST_PORT must be different"
  [ "$HARNESS_GERRIT_TARGET_SSH_HOST_PORT" != "$HARNESS_JENKINS_AGENT_TARGET_SSH_HOST_PORT" ] ||
    die "HARNESS_GERRIT_TARGET_SSH_HOST_PORT and HARNESS_JENKINS_AGENT_TARGET_SSH_HOST_PORT must be different"
  [ "$HARNESS_JENKINS_CONTROLLER_TARGET_SSH_HOST_PORT" != "$HARNESS_JENKINS_AGENT_TARGET_SSH_HOST_PORT" ] ||
    die "HARNESS_JENKINS_CONTROLLER_TARGET_SSH_HOST_PORT and HARNESS_JENKINS_AGENT_TARGET_SSH_HOST_PORT must be different"
  [ "$HARNESS_GERRIT_HTTP_HOST_PORT" != "$HARNESS_GERRIT_TARGET_SSH_HOST_PORT" ] ||
    die "HARNESS_GERRIT_HTTP_HOST_PORT and HARNESS_GERRIT_TARGET_SSH_HOST_PORT must be different"
  [ "$HARNESS_GERRIT_HTTP_HOST_PORT" != "$HARNESS_JENKINS_CONTROLLER_TARGET_SSH_HOST_PORT" ] ||
    die "HARNESS_GERRIT_HTTP_HOST_PORT and HARNESS_JENKINS_CONTROLLER_TARGET_SSH_HOST_PORT must be different"
  [ "$HARNESS_GERRIT_HTTP_HOST_PORT" != "$HARNESS_JENKINS_AGENT_TARGET_SSH_HOST_PORT" ] ||
    die "HARNESS_GERRIT_HTTP_HOST_PORT and HARNESS_JENKINS_AGENT_TARGET_SSH_HOST_PORT must be different"
  [ "$HARNESS_JENKINS_HTTP_HOST_PORT" != "$HARNESS_GERRIT_TARGET_SSH_HOST_PORT" ] ||
    die "HARNESS_JENKINS_HTTP_HOST_PORT and HARNESS_GERRIT_TARGET_SSH_HOST_PORT must be different"
  [ "$HARNESS_JENKINS_HTTP_HOST_PORT" != "$HARNESS_JENKINS_CONTROLLER_TARGET_SSH_HOST_PORT" ] ||
    die "HARNESS_JENKINS_HTTP_HOST_PORT and HARNESS_JENKINS_CONTROLLER_TARGET_SSH_HOST_PORT must be different"
  [ "$HARNESS_JENKINS_HTTP_HOST_PORT" != "$HARNESS_JENKINS_AGENT_TARGET_SSH_HOST_PORT" ] ||
    die "HARNESS_JENKINS_HTTP_HOST_PORT and HARNESS_JENKINS_AGENT_TARGET_SSH_HOST_PORT must be different"

  export HARNESS_GERRIT_HTTP_HOST_PORT HARNESS_JENKINS_HTTP_HOST_PORT
  export HARNESS_GERRIT_TARGET_SSH_HOST_PORT
  export HARNESS_JENKINS_CONTROLLER_TARGET_SSH_HOST_PORT
  export HARNESS_JENKINS_AGENT_TARGET_SSH_HOST_PORT
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
    configure-role) output="$(cmd_configure_role "$role")" || rc=$? ;;
    validate-role) output="$(cmd_validate_role "$role")" || rc=$? ;;
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
  local checkpoint role
  checkpoint="${1:?checkpoint required}"
  role="${2:?role required}"
  case "$role" in
    gerrit|jenkins-controller|jenkins-agent)
      case "$checkpoint" in
        prepare-artifacts)
          printf '%s/manifest.txt\n' "$(container_bundle_factory_work_dir_for_role "$role")"
          ;;
        stage-artifacts|configure-role|validate-role)
          printf '%s/manifest.txt\n' "$(target_payload_dir_for_role "$role")"
          ;;
        *)
          printf '%s/manifest.txt\n' "$(target_payload_dir_for_role "$role")"
          ;;
      esac
      ;;
    *)
      printf '%s\n' "not-applicable"
      ;;
  esac
}

checksum_reference_for_evidence() {
  local checkpoint role
  checkpoint="${1:?checkpoint required}"
  role="${2:?role required}"
  case "$role" in
    gerrit|jenkins-controller|jenkins-agent)
      case "$checkpoint" in
        prepare-artifacts)
          printf '%s;%s\n' \
            "$(container_prepared_artifact_checksum_for_role "$role")" \
            "$(container_bundle_factory_work_dir_for_role "$role")/checksums.sha256"
          ;;
        stage-artifacts)
          printf '%s;%s/checksums/SHA256SUMS;%s/checksums.sha256\n' \
            "$(exported_artifact_checksum_for_role "$role")" \
            "$(target_bundle_dir_for_role "$role")" \
            "$(target_payload_dir_for_role "$role")"
          ;;
        configure-role|validate-role)
          printf '%s/checksums/SHA256SUMS;%s/checksums.sha256\n' \
            "$(target_bundle_dir_for_role "$role")" \
            "$(target_payload_dir_for_role "$role")"
          ;;
        *)
          printf '%s/checksums.sha256\n' "$(target_payload_dir_for_role "$role")"
          ;;
      esac
      ;;
    *)
      printf '%s\n' "not-applicable"
      ;;
  esac
}

bundle_name_for_role() {
  local role
  role="${1:?role required}"
  case "$role" in
    gerrit) printf '%s\n' "gerrit-artifacts-bundle" ;;
    jenkins-controller) printf '%s\n' "jenkins-artifacts-bundle" ;;
    jenkins-agent) printf '%s\n' "jenkins-agent-artifacts-bundle" ;;
    *) die "Unknown role for artifact bundle: $role" ;;
  esac
}

bundle_payload_dir_for_role() {
  local role
  role="${1:?role required}"
  case "$role" in
    gerrit) printf '%s\n' "gerrit" ;;
    jenkins-controller) printf '%s\n' "jenkins" ;;
    jenkins-agent) printf '%s\n' "jenkins-agent" ;;
    *) die "Unknown role for artifact payload: $role" ;;
  esac
}

container_bundle_factory_work_dir_for_role() {
  local role bundle payload
  role="${1:?role required}"
  bundle="$(bundle_name_for_role "$role")"
  payload="$(bundle_payload_dir_for_role "$role")"
  printf '/var/lib/loopforge/preparing/%s/%s\n' "$bundle" "$payload"
}

container_bundle_factory_root_for_role() {
  local role bundle
  role="${1:?role required}"
  bundle="$(bundle_name_for_role "$role")"
  printf '/var/lib/loopforge/preparing/%s\n' "$bundle"
}

container_prepared_artifact_archive_for_role() {
  local role bundle
  role="${1:?role required}"
  bundle="$(bundle_name_for_role "$role")"
  printf '/var/lib/loopforge/preparing/%s.tar.gz\n' "$bundle"
}

container_prepared_artifact_checksum_for_role() {
  local role
  role="${1:?role required}"
  printf '%s.sha256\n' "$(container_prepared_artifact_archive_for_role "$role")"
}

exported_artifact_archive_for_role() {
  local role bundle
  role="${1:?role required}"
  bundle="$(bundle_name_for_role "$role")"
  printf '%s/%s.tar.gz\n' "$HARNESS_EXPORTED_ARTIFACT_DIR" "$bundle"
}

exported_artifact_checksum_for_role() {
  local role
  role="${1:?role required}"
  printf '%s.sha256\n' "$(exported_artifact_archive_for_role "$role")"
}

stage_bundle_dir_for_role() {
  local role bundle
  role="${1:?role required}"
  bundle="$(bundle_name_for_role "$role")"
  printf '%s/%s/%s\n' "$HARNESS_STAGING_DIR" "$role" "$bundle"
}

stage_payload_dir_for_role() {
  local role payload
  role="${1:?role required}"
  payload="$(bundle_payload_dir_for_role "$role")"
  printf '%s/%s\n' "$(stage_bundle_dir_for_role "$role")" "$payload"
}

target_bundle_dir_for_role() {
  local role bundle
  role="${1:?role required}"
  bundle="$(bundle_name_for_role "$role")"
  printf '/var/lib/loopforge/staging/%s\n' "$bundle"
}

target_payload_dir_for_role() {
  local role payload
  role="${1:?role required}"
  payload="$(bundle_payload_dir_for_role "$role")"
  printf '%s/%s\n' "$(target_bundle_dir_for_role "$role")" "$payload"
}

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

ensure_gerrit_ldap_bind_secret() {
  local log secret_file secret_dir
  log="${1:?log required}"
  secret_dir="$HARNESS_GERRIT_VALIDATION_SECRET_DIR"
  secret_file="$HARNESS_GERRIT_VALIDATION_SECRET_DIR/ldap-bind-password"
  if [ -d "$secret_dir" ] && [ ! -w "$secret_dir" ]; then
    rm -rf "$secret_dir"
  fi
  mkdir -p "$secret_dir"
  chmod 0700 "$secret_dir"
  printf '%s' "$HARNESS_LDAP_BIND_PASSWORD" >"$secret_file"
  chmod 0600 "$secret_file"
  printf 'validation_secret_ready role=gerrit secret_kind=ldap-bind-password custody=harness-owned-simulation-not-gerrit-artifact public_value_redacted=true\n' >>"$log"
}

stage_gerrit_ldap_bind_secret() {
  local log service secret_file container_secret_file
  log="${1:?log required}"
  service="${2:?service required}"
  ensure_gerrit_ldap_bind_secret "$log"
  secret_file="$HARNESS_GERRIT_VALIDATION_SECRET_DIR/ldap-bind-password"
  container_secret_file="/var/lib/loopforge/secret-inputs/ldap-bind-password"
  docker_cp_file_to_service "$secret_file" "$service" "$container_secret_file" ci-operator ci-operator 0600 "$log"
  printf 'validation_secret_staged role=gerrit secret_kind=ldap-bind-password destination=%s owner=ci-operator mode=0600 public_value_redacted=true\n' \
    "$container_secret_file" >>"$log"
}

gerrit_target_secret_env() {
  printf '%s\n' "LDAP_BIND_PASSWORD_FILE=/var/lib/loopforge/secret-inputs/ldap-bind-password"
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
  printf '%s\n' "/var/lib/loopforge/rendered/gerrit-bundle-factory.env"
}

jenkins_controller_bundle_factory_env_file() {
  printf '%s\n' "/var/lib/loopforge/rendered/jenkins-controller-bundle-factory.env"
}

container_env_file_for_role() {
  local role service state_dir
  role="${1:?role required}"
  service="${2:?service required}"
  if [ "$service" = "bundle-factory" ]; then
    printf '/var/lib/loopforge/rendered/%s.env\n' "$role"
    return 0
  fi
  state_dir="$(container_state_dir_for_service "$service")"
  printf '%s/rendered/%s.env\n' "$state_dir" "$role"
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
  case "$role" in
    gerrit)
      sed -e 's|^GERRIT_SITE_PATH=.*|GERRIT_SITE_PATH="/srv/gerrit"|' \
        -e 's|^GERRIT_EVIDENCE_DIR=.*|GERRIT_EVIDENCE_DIR="/var/lib/loopforge/evidence"|' \
        -e 's|^GERRIT_LOG_DIR=.*|GERRIT_LOG_DIR="/var/log/loopforge"|' \
        "$src" >"$host_env_file"
      canonical_web_url="http://127.0.0.1:$HARNESS_GERRIT_HTTP_HOST_PORT/"
      set_env_file_value "$host_env_file" GERRIT_CANONICAL_WEB_URL "$canonical_web_url"
      ;;
    jenkins-controller)
      sed -e 's|^JENKINS_HOME=.*|JENKINS_HOME="/var/lib/jenkins"|' \
        -e 's|^JENKINS_EVIDENCE_DIR=.*|JENKINS_EVIDENCE_DIR="/var/lib/loopforge/evidence"|' \
        -e 's|^JENKINS_LOG_DIR=.*|JENKINS_LOG_DIR="/var/log/loopforge"|' \
        "$src" >"$host_env_file"
      ;;
    jenkins-agent)
      if [ "$service" = "bundle-factory" ]; then
        sed \
          -e 's|^JENKINS_AGENT_ARTIFACT_OUTPUT_DIR=.*|JENKINS_AGENT_ARTIFACT_OUTPUT_DIR="/var/lib/loopforge/preparing/jenkins-agent-artifacts-bundle/jenkins-agent"|' \
          "$src" >"$host_env_file"
      else
        sed -e 's|^JENKINS_AGENT_REMOTE_FS=.*|JENKINS_AGENT_REMOTE_FS="/var/lib/jenkins-agent"|' \
          -e 's|^JENKINS_AGENT_EVIDENCE_DIR=.*|JENKINS_AGENT_EVIDENCE_DIR="/var/lib/loopforge/evidence"|' \
          -e 's|^JENKINS_AGENT_LOG_DIR=.*|JENKINS_AGENT_LOG_DIR="/var/log/loopforge"|' \
          "$src" >"$host_env_file"
      fi
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
    -e 's|^GERRIT_LOCAL_ARTIFACT_OUTPUT_DIR=.*|GERRIT_LOCAL_ARTIFACT_OUTPUT_DIR="/var/lib/loopforge/preparing/gerrit-artifacts-bundle/gerrit"|' \
    -e 's|^GERRIT_ARTIFACT_OUTPUT_DIR=.*|GERRIT_ARTIFACT_OUTPUT_DIR="/var/lib/loopforge/preparing/gerrit-artifacts-bundle/gerrit"|' \
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
    -e 's|^JENKINS_ARTIFACT_OUTPUT_DIR=.*|JENKINS_ARTIFACT_OUTPUT_DIR="/var/lib/loopforge/preparing/jenkins-artifacts-bundle/jenkins"|' \
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
  stage_rendered_env_file "$service" "$host_env_file" "$container_env_file" ci-operator ci-operator "$log"
}

prepare_product_home_ownership() {
  local role service host_env_file path account group log command
  role="${1:?role required}"
  service="${2:?service required}"
  log="${3:?log required}"
  host_env_file="$(host_container_env_file_for_role "$role" "$service")"
  require_readable_file "Rendered $role env file; run init-run first" "$host_env_file"
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
  command="$(owned_directory_command "$account" "$group" 0755 "$path" 1)"
  compose exec -T "$service" sh -c "$command" >>"$log" 2>&1
  printf 'product_home_ownership_prepared role=%s service=%s path=%s owner=%s group=%s\n' \
    "$role" "$service" "$path" "$account" "$group" >>"$log"
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

prepare_bundle_factory_workspace_ownership() {
  local role log work_root script
  role="${1:?role required}"
  log="${2:?log required}"
  work_root="/var/lib/loopforge/preparing"
  script="$(owned_directory_command ci-operator ci-operator 0700 "$work_root" 1)"
  if ! compose exec -T -u root bundle-factory sh -c "$script" >>"$log" 2>&1; then
    return 1
  fi
  printf 'bundle_factory_bind_mount_prepared role=%s service=bundle-factory preparing=%s owner=ci-operator group=ci-operator scope=docker-simulation-bind-mount\n' \
    "$role" "$work_root" >>"$log"
}

prepare_target_helper_owned_paths() {
  local role service log state_root rendered_root secret_input_root staging_root evidence_root log_root script
  role="${1:?role required}"
  service="${2:?service required}"
  log="${3:?log required}"
  state_root="/var/lib/loopforge"
  rendered_root="/var/lib/loopforge/rendered"
  secret_input_root="/var/lib/loopforge/secret-inputs"
  staging_root="/var/lib/loopforge/staging"
  evidence_root="/var/lib/loopforge/evidence"
  log_root="/var/log/loopforge"

  script="$(owned_directory_command ci-operator ci-operator 0700 "$state_root" 0)"
  script="$script && $(owned_directory_command ci-operator ci-operator 0750 "$rendered_root" 1)"
  script="$script && $(owned_directory_command ci-operator ci-operator 0700 "$secret_input_root" 1)"
  script="$script && $(owned_directory_command ci-operator ci-operator 0750 "$staging_root" 1)"
  script="$script && $(owned_directory_command ci-operator ci-operator 0750 "$evidence_root" 1)"
  script="$script && $(owned_directory_command ci-operator ci-operator 0750 "$log_root" 1)"
  if ! compose exec -T -u root "$service" sh -c "$script" >>"$log" 2>&1; then
    return 1
  fi
  printf 'helper_owned_paths_prepared role=%s service=%s state=%s rendered=%s secret_inputs=%s staging=%s evidence=%s logs=%s owner=ci-operator group=ci-operator recursive_contract=target-helper-owned\n' \
    "$role" "$service" "$state_root" "$rendered_root" "$secret_input_root" "$staging_root" "$evidence_root" "$log_root" >>"$log"
}

prepare_all_target_helper_owned_paths() {
  local log
  log="${1:?log required}"
  prepare_target_helper_owned_paths gerrit gerrit-target "$log"
  prepare_target_helper_owned_paths jenkins-controller jenkins-controller-target "$log"
  prepare_target_helper_owned_paths jenkins-agent jenkins-agent-target "$log"
}

copy_bundle_factory_artifacts_to_host() {
  local role service log container_dir container_root container_archive container_checksum container_id
  local archive checksum bundle payload
  role="${1:?role required}"
  service="${2:?service required}"
  log="${3:?log required}"
  container_dir="$(container_bundle_factory_work_dir_for_role "$role")"
  container_root="$(container_bundle_factory_root_for_role "$role")"
  container_archive="$(container_prepared_artifact_archive_for_role "$role")"
  container_checksum="$(container_prepared_artifact_checksum_for_role "$role")"
  archive="$(exported_artifact_archive_for_role "$role")"
  checksum="$(exported_artifact_checksum_for_role "$role")"
  bundle="$(bundle_name_for_role "$role")"
  payload="$(bundle_payload_dir_for_role "$role")"
  if ! compose exec -T "$service" sh -c \
    "test -f $(shell_quote "$container_dir/manifest.txt") && test -f $(shell_quote "$container_dir/checksums.sha256") && cd $(shell_quote "$container_dir") && sha256sum -c checksums.sha256 && test -f $(shell_quote "$container_root/checksums/SHA256SUMS") && cd $(shell_quote "$container_root") && sha256sum -c checksums/SHA256SUMS && cd /var/lib/loopforge/preparing && sha256sum -c $(shell_quote "$(basename "$container_checksum")")" \
    >>"$log" 2>&1; then
    return 1
  fi
  container_id="$(container_id_for_service "$service")"
  [ -n "$container_id" ] || die "Harness service '$service' is not created; run up first"
  rm -f "$archive" "$checksum"
  mkdir -p "$HARNESS_EXPORTED_ARTIFACT_DIR"
  if ! docker cp "$container_id:$container_archive" "$archive" >>"$log" 2>&1; then
    return 1
  fi
  if ! docker cp "$container_id:$container_checksum" "$checksum" >>"$log" 2>&1; then
    return 1
  fi
  if ! (cd "$HARNESS_EXPORTED_ARTIFACT_DIR" && sha256sum -c "$(basename "$checksum")") >>"$log" 2>&1; then
    return 1
  fi
  tar -xOf "$archive" "$bundle/$payload/manifest.txt" >"$HARNESS_EXPORTED_ARTIFACT_DIR/.manifest-$role.tmp"
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
  [ -n "$container_id" ] || die "Harness service '$service' is not created; run up first"
  tmp_path="/tmp/loopforge-docker-cp-$$-$(basename "$container_path")"
  dest_dir="$(dirname "$container_path")"
  if ! docker cp "$host_file" "$container_id:$tmp_path" >>"$log" 2>&1; then
    return 1
  fi
  command="$(owned_directory_command "$owner" "$group" 0750 "$dest_dir" 0)"
  command="$command && mv $(shell_quote "$tmp_path") $(shell_quote "$container_path") && chown $(shell_quote "$owner:$group") $(shell_quote "$container_path") && chmod $(shell_quote "$mode") $(shell_quote "$container_path")"
  compose exec -T -u root "$service" sh -c "$command" >>"$log" 2>&1
  printf 'transfer_mode=docker-cp-waiver source=%s service=%s destination=%s owner=%s group=%s mode=%s scope=docker-simulation-only\n' \
    "$host_file" "$service" "$container_path" "$owner" "$group" "$mode" >>"$log"
}

docker_cp_file_from_service() {
  local service container_path host_file log container_id
  service="${1:?service required}"
  container_path="${2:?container path required}"
  host_file="${3:?host file required}"
  log="${4:?log required}"
  container_id="$(container_id_for_service "$service")"
  [ -n "$container_id" ] || die "Harness service '$service' is not created; run up first"
  mkdir -p "$(dirname "$host_file")"
  if ! docker cp "$container_id:$container_path" "$host_file" >>"$log" 2>&1; then
    return 1
  fi
  chmod u+rw,go-rwx "$host_file" 2>/dev/null || true
  printf 'transfer_mode=docker-cp-collector service=%s source=%s destination=%s scope=docker-simulation-only\n' \
    "$service" "$container_path" "$host_file" >>"$log"
}

stage_rendered_env_file() {
  local service host_env_file container_env_file owner group log
  service="${1:?service required}"
  host_env_file="${2:?host env file required}"
  container_env_file="${3:?container env file required}"
  owner="${4:?owner required}"
  group="${5:?group required}"
  log="${6:?log required}"
  docker_cp_file_to_service "$host_env_file" "$service" "$container_env_file" "$owner" "$group" 0640 "$log"
  printf '%s\n' "$container_env_file"
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

validate_role_baseline_manifest_in_target() {
  local role service manifest log gerrit_version jenkins_version plugin_manager_version script
  role="${1:?role required}"
  service="${2:?service required}"
  log="${3:?log required}"
  manifest="$(target_payload_dir_for_role "$role")/manifest.txt"
  case "$role" in
    gerrit)
      gerrit_version="$HARNESS_GERRIT_BASELINE"
      jenkins_version="not-applicable"
      plugin_manager_version="not-applicable"
      ;;
    jenkins-controller)
      gerrit_version="not-applicable"
      jenkins_version="$HARNESS_JENKINS_BASELINE"
      plugin_manager_version="$HARNESS_JENKINS_PLUGIN_MANAGER_BASELINE"
      ;;
    jenkins-agent)
      gerrit_version="not-applicable"
      jenkins_version="not-applicable"
      plugin_manager_version="not-applicable"
      ;;
    *)
      die "Unknown role for target manifest validation: $role"
      ;;
  esac
  script='
manifest="$1"
role="$2"
ubuntu_release="$3"
ubuntu_codename="$4"
java_version="$5"
gerrit_version="$6"
jenkins_version="$7"
plugin_manager_version="$8"
test -f "$manifest" || {
  printf "baseline_drift role=%s field=manifest expected=present actual=missing manifest=%s\n" "$role" "$manifest"
  exit 1
}
expect_manifest_value() {
  key="$1"
  expected="$2"
  actual="$(awk -F= -v key="$key" '\''
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
  '\'' "$manifest")" || {
    printf "baseline_drift role=%s field=%s expected=%s actual=<missing> manifest=%s\n" "$role" "$key" "$expected" "$manifest"
    exit 1
  }
  [ "$actual" = "$expected" ] || {
    printf "baseline_drift role=%s field=%s expected=%s actual=%s manifest=%s\n" "$role" "$key" "$expected" "$actual" "$manifest"
    exit 1
  }
}
expect_manifest_value harness_manifest_version 1
expect_manifest_value role "$role"
expect_manifest_value ubuntu_release "$ubuntu_release"
expect_manifest_value ubuntu_codename "$ubuntu_codename"
expect_manifest_value java_version "$java_version"
expect_manifest_value artifact_source curated-bundle-factory
expect_manifest_value os_dependency_source approved-internal-os-repos
expect_manifest_value public_internet_fallback simulation-only
expect_manifest_value bundle_contains_keys no
expect_manifest_value gerrit_version "$gerrit_version"
expect_manifest_value jenkins_version "$jenkins_version"
expect_manifest_value jenkins_plugin_manager_version "$plugin_manager_version"
'
  if ! compose exec -T "$service" sh -c "$script" sh \
    "$manifest" \
    "$role" \
    "$HARNESS_UBUNTU_BASELINE_RELEASE" \
    "$HARNESS_UBUNTU_BASELINE_CODENAME" \
    "$HARNESS_JAVA_BASELINE" \
    "$gerrit_version" \
    "$jenkins_version" \
    "$plugin_manager_version" >>"$log" 2>&1; then
    return 1
  fi
  printf 'baseline_ok role=%s manifest=%s location=target-container\n' "$role" "$manifest" >>"$log"
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
  if [ "$checkpoint" = "preflight" ] || [ "$checkpoint" = "clean" ]; then
    ensure_preflight_dirs
  else
    ensure_dirs
  fi
  file="$(evidence_dir_for_record "$checkpoint" "$role")/${checkpoint}-${role}-$(timestamp_utc).json"
  mkdir -p "$(dirname "$file")"
  manifest_ref="$(manifest_reference_for_evidence "$checkpoint" "$role")"
  checksum_ref="$(checksum_reference_for_evidence "$checkpoint" "$role")"
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
  q_source_boundary="$(json_quote "Application artifacts are prepared in bundle factory and transferred to targets with a Docker cp simulation-only waiver; target-host public internet fallback is simulation-only for Ubuntu/OS dependencies.")"

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
  require_command python3
  prepare_init_run
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
HARNESS_GENERATED_RUN_DIR=$(shell_quote "$HARNESS_GENERATED_RUN_DIR")
HARNESS_HOST_DIR=$(shell_quote "$HARNESS_HOST_DIR")
HARNESS_TARGET_DIR=$(shell_quote "$HARNESS_TARGET_DIR")
HARNESS_STATE_DIR=$(shell_quote "$HARNESS_STATE_DIR")
HARNESS_PRODUCT_HOME_DIR=$(shell_quote "$HARNESS_PRODUCT_HOME_DIR")
HARNESS_STAGING_DIR=$(shell_quote "$HARNESS_STAGING_DIR")
HARNESS_EXPORTED_ARTIFACT_DIR=$(shell_quote "$HARNESS_EXPORTED_ARTIFACT_DIR")
HARNESS_EVIDENCE_DIR=$(shell_quote "$HARNESS_EVIDENCE_DIR")
HARNESS_LOG_DIR=$(shell_quote "$HARNESS_LOG_DIR")
HARNESS_RETAINED_OUTPUT_BACKUP_DIR=$(shell_quote "$HARNESS_RETAINED_OUTPUT_BACKUP_DIR")
HARNESS_INTEGRATION_ENV_FILE=$(shell_quote "$HARNESS_INTEGRATION_ENV_FILE")
HARNESS_GERRIT_ENV_FILE=$(shell_quote "$HARNESS_GERRIT_ENV_FILE")
HARNESS_JENKINS_CONTROLLER_ENV_FILE=$(shell_quote "$HARNESS_JENKINS_CONTROLLER_ENV_FILE")
HARNESS_JENKINS_AGENT_ENV_FILE=$(shell_quote "$HARNESS_JENKINS_AGENT_ENV_FILE")
HARNESS_JENKINS_SHARED_STORAGE_PATH=$(shell_quote "$HARNESS_JENKINS_SHARED_STORAGE_PATH")
HARNESS_GERRIT_HTTP_HOST_PORT=$(shell_quote "$HARNESS_GERRIT_HTTP_HOST_PORT")
HARNESS_JENKINS_HTTP_HOST_PORT=$(shell_quote "$HARNESS_JENKINS_HTTP_HOST_PORT")
HARNESS_GERRIT_TARGET_SSH_HOST_PORT=$(shell_quote "$HARNESS_GERRIT_TARGET_SSH_HOST_PORT")
HARNESS_JENKINS_CONTROLLER_TARGET_SSH_HOST_PORT=$(shell_quote "$HARNESS_JENKINS_CONTROLLER_TARGET_SSH_HOST_PORT")
HARNESS_JENKINS_AGENT_TARGET_SSH_HOST_PORT=$(shell_quote "$HARNESS_JENKINS_AGENT_TARGET_SSH_HOST_PORT")
HARNESS_TARGET_SSH_DIR=$(shell_quote "$HARNESS_TARGET_SSH_DIR")
HARNESS_TARGET_SSH_IDENTITY_FILE=$(shell_quote "$HARNESS_TARGET_SSH_IDENTITY_FILE")
HARNESS_TARGET_SSH_KNOWN_HOSTS_FILE=$(shell_quote "$HARNESS_TARGET_SSH_KNOWN_HOSTS_FILE")
HARNESS_GERRIT_VALIDATION_SECRET_DIR=$(shell_quote "$HARNESS_GERRIT_VALIDATION_SECRET_DIR")
HARNESS_BUNDLE_FACTORY_RENDERED_DIR=$(shell_quote "$HARNESS_BUNDLE_FACTORY_RENDERED_DIR")
HARNESS_BUNDLE_FACTORY_VALIDATION_PUBLIC_DIR=$(shell_quote "$HARNESS_BUNDLE_FACTORY_VALIDATION_PUBLIC_DIR")
HARNESS_LDAP_DATA_DIR=$(shell_quote "$HARNESS_LDAP_DATA_DIR")
HARNESS_LDAP_CONFIG_DIR=$(shell_quote "$HARNESS_LDAP_CONFIG_DIR")
HARNESS_SHARED_JENKINS_STORAGE_DIR=$(shell_quote "$HARNESS_SHARED_JENKINS_STORAGE_DIR")
HARNESS_GERRIT_EVIDENCE_DIR=$(shell_quote "$HARNESS_GERRIT_EVIDENCE_DIR")
HARNESS_GERRIT_LOG_DIR=$(shell_quote "$HARNESS_GERRIT_LOG_DIR")
HARNESS_JENKINS_CONTROLLER_EVIDENCE_DIR=$(shell_quote "$HARNESS_JENKINS_CONTROLLER_EVIDENCE_DIR")
HARNESS_JENKINS_CONTROLLER_LOG_DIR=$(shell_quote "$HARNESS_JENKINS_CONTROLLER_LOG_DIR")
HARNESS_JENKINS_AGENT_EVIDENCE_DIR=$(shell_quote "$HARNESS_JENKINS_AGENT_EVIDENCE_DIR")
HARNESS_JENKINS_AGENT_LOG_DIR=$(shell_quote "$HARNESS_JENKINS_AGENT_LOG_DIR")
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
  write_run_marker
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
HARNESS_GENERATED_RUN_DIR=$(shell_quote "$HARNESS_GENERATED_RUN_DIR")
HARNESS_HOST_DIR=$(shell_quote "$HARNESS_HOST_DIR")
HARNESS_TARGET_DIR=$(shell_quote "$HARNESS_TARGET_DIR")
HARNESS_STATE_DIR=$(shell_quote "$HARNESS_STATE_DIR")
HARNESS_PRODUCT_HOME_DIR=$(shell_quote "$HARNESS_PRODUCT_HOME_DIR")
HARNESS_STAGING_DIR=$(shell_quote "$HARNESS_STAGING_DIR")
HARNESS_EXPORTED_ARTIFACT_DIR=$(shell_quote "$HARNESS_EXPORTED_ARTIFACT_DIR")
HARNESS_EVIDENCE_DIR=$(shell_quote "$HARNESS_EVIDENCE_DIR")
HARNESS_LOG_DIR=$(shell_quote "$HARNESS_LOG_DIR")
HARNESS_RETAINED_OUTPUT_BACKUP_DIR=$(shell_quote "$HARNESS_RETAINED_OUTPUT_BACKUP_DIR")
HARNESS_INTEGRATION_ENV_FILE=$(shell_quote "$HARNESS_INTEGRATION_ENV_FILE")
HARNESS_GERRIT_ENV_FILE=$(shell_quote "$HARNESS_GERRIT_ENV_FILE")
HARNESS_JENKINS_CONTROLLER_ENV_FILE=$(shell_quote "$HARNESS_JENKINS_CONTROLLER_ENV_FILE")
HARNESS_JENKINS_AGENT_ENV_FILE=$(shell_quote "$HARNESS_JENKINS_AGENT_ENV_FILE")
HARNESS_JENKINS_SHARED_STORAGE_PATH=$(shell_quote "$HARNESS_JENKINS_SHARED_STORAGE_PATH")
HARNESS_GERRIT_HTTP_HOST_PORT=$(shell_quote "$HARNESS_GERRIT_HTTP_HOST_PORT")
HARNESS_JENKINS_HTTP_HOST_PORT=$(shell_quote "$HARNESS_JENKINS_HTTP_HOST_PORT")
HARNESS_GERRIT_TARGET_SSH_HOST_PORT=$(shell_quote "$HARNESS_GERRIT_TARGET_SSH_HOST_PORT")
HARNESS_JENKINS_CONTROLLER_TARGET_SSH_HOST_PORT=$(shell_quote "$HARNESS_JENKINS_CONTROLLER_TARGET_SSH_HOST_PORT")
HARNESS_JENKINS_AGENT_TARGET_SSH_HOST_PORT=$(shell_quote "$HARNESS_JENKINS_AGENT_TARGET_SSH_HOST_PORT")
HARNESS_TARGET_SSH_DIR=$(shell_quote "$HARNESS_TARGET_SSH_DIR")
HARNESS_TARGET_SSH_IDENTITY_FILE=$(shell_quote "$HARNESS_TARGET_SSH_IDENTITY_FILE")
HARNESS_TARGET_SSH_KNOWN_HOSTS_FILE=$(shell_quote "$HARNESS_TARGET_SSH_KNOWN_HOSTS_FILE")
HARNESS_GERRIT_VALIDATION_SECRET_DIR=$(shell_quote "$HARNESS_GERRIT_VALIDATION_SECRET_DIR")
HARNESS_BUNDLE_FACTORY_RENDERED_DIR=$(shell_quote "$HARNESS_BUNDLE_FACTORY_RENDERED_DIR")
HARNESS_BUNDLE_FACTORY_VALIDATION_PUBLIC_DIR=$(shell_quote "$HARNESS_BUNDLE_FACTORY_VALIDATION_PUBLIC_DIR")
HARNESS_LDAP_DATA_DIR=$(shell_quote "$HARNESS_LDAP_DATA_DIR")
HARNESS_LDAP_CONFIG_DIR=$(shell_quote "$HARNESS_LDAP_CONFIG_DIR")
HARNESS_SHARED_JENKINS_STORAGE_DIR=$(shell_quote "$HARNESS_SHARED_JENKINS_STORAGE_DIR")
HARNESS_GERRIT_EVIDENCE_DIR=$(shell_quote "$HARNESS_GERRIT_EVIDENCE_DIR")
HARNESS_GERRIT_LOG_DIR=$(shell_quote "$HARNESS_GERRIT_LOG_DIR")
HARNESS_JENKINS_CONTROLLER_EVIDENCE_DIR=$(shell_quote "$HARNESS_JENKINS_CONTROLLER_EVIDENCE_DIR")
HARNESS_JENKINS_CONTROLLER_LOG_DIR=$(shell_quote "$HARNESS_JENKINS_CONTROLLER_LOG_DIR")
HARNESS_JENKINS_AGENT_EVIDENCE_DIR=$(shell_quote "$HARNESS_JENKINS_AGENT_EVIDENCE_DIR")
HARNESS_JENKINS_AGENT_LOG_DIR=$(shell_quote "$HARNESS_JENKINS_AGENT_LOG_DIR")
HARNESS_GERRIT_BROWSER_URL=$(shell_quote "http://127.0.0.1:$HARNESS_GERRIT_HTTP_HOST_PORT/")
HARNESS_JENKINS_BROWSER_URL=$(shell_quote "http://127.0.0.1:$HARNESS_JENKINS_HTTP_HOST_PORT/login")
HARNESS_RENDERED_ENV=$(shell_quote "$HARNESS_RENDERED_ENV")
HARNESS_RUNTIME_ENV=$(shell_quote "$HARNESS_RUNTIME_ENV")
HARNESS_RUNTIME_INPUT_DIR=$(shell_quote "$HARNESS_RUNTIME_INPUT_DIR")
HARNESS_BASELINE_CONTRACT=$(shell_quote "$HARNESS_BASELINE_CONTRACT")
HARNESS_RUN_MARKER=$(shell_quote "$HARNESS_RUN_MARKER")
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

running_loopback_port_for_service_port() {
  local service container_port container_id port
  service="${1:?service required}"
  container_port="${2:?container port required}"
  container_id="$(container_id_for_service "$service")"
  [ -n "$container_id" ] || die "Harness service '$service' is not created; run up first"
  port="$(docker inspect -f "{{with index .NetworkSettings.Ports \"$container_port\"}}{{range .}}{{if eq .HostIp \"127.0.0.1\"}}{{.HostPort}}{{\"\\n\"}}{{end}}{{end}}{{end}}" "$container_id" 2>/dev/null | sed -n '1p')"
  [ -n "$port" ] || die "Harness service '$service' has no published loopback port for $container_port"
  printf '%s\n' "$port"
}

check_target_os_release() {
  local role service log os_release os_codename evidence
  role="${1:?role required}"
  service="$(service_for_role "$role")"
  log="$(bounded_log_path "os-release-$role")"

  if ! compose exec -T "$service" sh -c '. /etc/os-release && printf "%s %s\n" "$VERSION_ID" "$VERSION_CODENAME"' >"$log" 2>&1; then
    evidence="$(write_evidence os-release "$role" fail "simulate.sh validate-role" "$log" "Could not read target OS release")"
    die "Failed to read OS release for $role; evidence=$evidence log=$log"
  fi

  os_release="$(awk '{print $1}' "$log")"
  os_codename="$(awk '{print $2}' "$log")"
  if [ "$os_release" != "$HARNESS_UBUNTU_BASELINE_RELEASE" ] || [ "$os_codename" != "$HARNESS_UBUNTU_BASELINE_CODENAME" ]; then
    evidence="$(write_evidence os-release "$role" blocked "simulate.sh validate-role" "$log" "Target OS $os_release $os_codename does not match Version Baseline")"
    die "Target OS drift for $role; expected $HARNESS_UBUNTU_BASELINE_RELEASE $HARNESS_UBUNTU_BASELINE_CODENAME, evidence=$evidence log=$log"
  fi

  write_evidence os-release "$role" pass "simulate.sh validate-role" "$log" "Target OS release matches Version Baseline" >/dev/null
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

workflow_step() {
  local step
  step="${1:?step required}"
  shift
  printf '==> %s\n' "$step"
  if [ -n "${HARNESS_TEST_WORKFLOW_CALLS:-}" ]; then
    mkdir -p "$(dirname "$HARNESS_TEST_WORKFLOW_CALLS")"
    printf '%s\n' "$step" >>"$HARNESS_TEST_WORKFLOW_CALLS"
    return 0
  fi
  "$@"
}

workflow_downstream_steps() {
  workflow_step up cmd_up
  workflow_step status cmd_status
  workflow_step prepare-artifacts cmd_prepare_artifacts ""
  workflow_step stage-artifacts cmd_stage_artifacts ""
  workflow_step configure-role cmd_configure_role ""
  workflow_step validate-role cmd_validate_role ""
  workflow_step configure-integration cmd_configure_integration
  workflow_step validate-integration cmd_validate_integration
  workflow_step prove-integration cmd_prove_integration
}

cmd_run() {
  bootstrap_harness_env
  if runtime_config_valid; then
    printf 'run: mode=resume run-id=%s\n' "$HARNESS_RUN_ID"
    workflow_downstream_steps
    return
  fi
  if selected_containers_exist; then
    die "Docker generated state is missing or invalid while selected containers exist; run down or clean before running workflow"
  fi
  printf 'run: mode=fresh run-id=%s\n' "$HARNESS_RUN_ID"
  workflow_step preflight cmd_preflight
  workflow_step init-run cmd_init_run
  workflow_downstream_steps
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
  require_command ssh-keygen
  require_command ssh-keyscan
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

cmd_init_run() {
  bootstrap_harness_env
  require_baseline_label
  if selected_containers_exist; then
    die "Selected Docker simulation containers already exist; run down or clean before starting a fresh init-run workflow"
  fi
  write_rendered_env
  write_evidence init-run harness pass "simulate.sh init-run" "not-applicable" "Rendered redacted harness configuration with Version Baseline values" >/dev/null
  printf 'init-run: ok run-id=%s\n' "$HARNESS_RUN_ID"
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
  require_command ssh-keyscan
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
  if ! prepare_all_target_helper_owned_paths "$log" ||
    ! prepare_product_home_ownership gerrit gerrit-target "$log" ||
    ! prepare_product_home_ownership jenkins-controller jenkins-controller-target "$log" ||
    ! prepare_product_home_ownership jenkins-agent jenkins-agent-target "$log" ||
    ! refresh_target_ssh_known_hosts "$log"; then
    evidence="$(write_evidence up harness fail "simulate.sh up" "$log" "Post-start ownership preparation failed")"
    print_command_failure up "" failed "$log" "$evidence"
    return 1
  fi
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
  printf '  %-18s  %-14s  %-20s  %-40s\n' 'Gerrit integration' 'jenkins-gerrit' 'integration-password' 'Jenkins-to-Gerrit integration account'
  printf '  %-18s  %-14s  %-20s  %-40s\n' '------------------' '--------------' '--------------------' '----------------------------------------'
}

target_ssh_env_prefix() {
  case "${1:-}" in
    gerrit) printf '%s\n' INTEGRATION_GERRIT_TARGET ;;
    jenkins-controller) printf '%s\n' INTEGRATION_JENKINS_CONTROLLER_TARGET ;;
    jenkins-agent) printf '%s\n' INTEGRATION_JENKINS_AGENT_TARGET ;;
    *) die "Unknown role '${1:-}'; expected gerrit, jenkins-controller, or jenkins-agent" ;;
  esac
}

target_ssh_inventory_value() {
  local role suffix prefix value
  role="${1:?role required}"
  suffix="${2:?suffix required}"
  prefix="$(target_ssh_env_prefix "$role")"
  eval "value=\${${prefix}_SSH_${suffix}:-}"
  printf '%s\n' "$value"
}

cmd_ssh() {
  local role host port user identity_file known_hosts_file
  role="${1:?role required}"
  bootstrap_harness_env
  ensure_runtime_config
  require_command ssh
  require_running_service "$(service_for_role "$role")"
  require_readable_file "Runtime integration env file" "$HARNESS_INTEGRATION_ENV_FILE"
  set -a
  # shellcheck disable=SC1090
  . "$HARNESS_INTEGRATION_ENV_FILE"
  set +a

  host="$(target_ssh_inventory_value "$role" HOST)"
  port="$(target_ssh_inventory_value "$role" PORT)"
  user="$(target_ssh_inventory_value "$role" USER)"
  identity_file="$(target_ssh_inventory_value "$role" IDENTITY_FILE)"
  known_hosts_file="$(target_ssh_inventory_value "$role" KNOWN_HOSTS_FILE)"

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

role_helper_present_in_container() {
  local service helper
  service="${1:?service required}"
  helper="${2:?helper required}"
  compose exec -T "$service" test -x "/workspace/$helper" >/dev/null 2>&1
}

cmd_prepare_artifacts() {
  local role helper service log rc evidence artifact_dir host_env_file role_env_file export_archive
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
  if ! prepare_bundle_factory_workspace_ownership "$role" "$log"; then
    evidence="$(write_evidence prepare-artifacts "$role" fail "simulate.sh prepare-artifacts" "$log" "Bundle factory workspace ownership preparation failed")"
    print_command_failure prepare-artifacts "$role" failed "$log" "$evidence"
    return 1
  fi
  if [ "$role" = "gerrit" ]; then
    ensure_gerrit_ldap_bind_secret "$log"
  elif [ "$role" = "jenkins-controller" ]; then
    :
  elif [ "$role" = "jenkins-agent" ]; then
    :
  fi
  role_env_file="$(stage_rendered_env_file "$service" "$host_env_file" "$role_env_file" ci-operator ci-operator "$log")"

  if [ "$role" = "gerrit" ]; then
    if compose exec -T -u ci-operator "$service" "/workspace/$helper" --env "$role_env_file" --yes prepare-artifacts >>"$log" 2>&1; then
      rc=0
    else
      rc=$?
    fi
  elif [ "$role" = "jenkins-controller" ]; then
    if compose exec -T -u ci-operator "$service" "/workspace/$helper" --env "$role_env_file" --yes prepare-artifacts >>"$log" 2>&1; then
      rc=0
    else
      rc=$?
    fi
  elif [ "$role" = "jenkins-agent" ]; then
    if compose exec -T -u ci-operator "$service" "/workspace/$helper" --env "$role_env_file" prepare-artifacts >>"$log" 2>&1; then
      rc=0
    else
      rc=$?
    fi
  elif compose exec -T -u ci-operator "$service" "/workspace/$helper" prepare-artifacts >>"$log" 2>&1; then
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

cmd_stage_artifacts() {
  local role service archive checksum target_bundle_dir target_payload_dir log evidence
  local staging_root archive_name checksum_name container_archive container_checksum extract_script
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
  if ! (cd "$(dirname "$archive")" && sha256sum -c "$(basename "$checksum")") >>"$log" 2>&1; then
    evidence="$(write_evidence stage-artifacts "$role" fail "simulate.sh stage-artifacts" "$log" "Exported artifact archive checksum verification failed")"
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
tar -xzf "$archive_name" -C "$staging_root"
test -d "$target_bundle_dir"
test -f "$target_payload_dir/manifest.txt"
test -f "$target_payload_dir/checksums.sha256"
cd "$target_bundle_dir"
sha256sum -c checksums/SHA256SUMS
cd "$target_payload_dir"
sha256sum -c checksums.sha256
chown -R ci-operator:ci-operator "$target_bundle_dir"
find "$target_bundle_dir" -type d -exec chmod 0755 {} +
find "$target_bundle_dir" -type f -exec chmod 0644 {} +
'
  if ! compose exec -T -u root "$service" sh -c "$extract_script" sh \
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
  local log role pattern state_dir service latest latest_base evidence_copy normalized
  log="${1:?log required}"
  role="${2:?role required}"
  pattern="${3:?pattern required}"
  state_dir="${4:?state dir required}"
  service="$(service_for_role "$role")"
  latest="$(compose exec -T -u ci-operator "$service" sh -c \
    "find /var/lib/loopforge/evidence -maxdepth 1 -type f -name $(shell_quote "$pattern") -print | sort | tail -1" 2>>"$log" || true)"
  [ -n "$latest" ] || {
    printf 'missing_role_evidence role=%s expected=%s\n' "$role" "$pattern" >>"$log"
    return 1
  }

  require_command python3
  latest_base="$(basename "$latest")"
  evidence_copy="$HARNESS_EVIDENCE_DIR/role-source/$role/$latest_base"
  normalized="$HARNESS_EVIDENCE_DIR/$(basename "${latest_base%.json}").host.json"
  docker_cp_file_from_service "$service" "$latest" "$evidence_copy" "$log" || return 1
  while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    case "$ref" in
      /*)
        docker_cp_file_from_service "$service" "$ref" "$HARNESS_LOG_DIR/role-snapshots/$role/${ref#/}" "$log" || return 1
        if [ ! -s "$HARNESS_LOG_DIR/role-snapshots/$role/${ref#/}" ]; then
          printf 'bounded_log_reference_empty role=%s reference=%s\n' "$role" "$ref" >>"$log"
          return 1
        fi
        ;;
      *)
        printf 'unsupported_relative_bounded_log_reference role=%s reference=%s\n' "$role" "$ref" >>"$log"
        return 1
        ;;
    esac
  done <<EOF
$(python3 - "$evidence_copy" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    data = json.load(handle)

for ref in data.get("bounded_log_references", "").split(";"):
    if ref:
        print(ref)
PY
)
EOF

  python3 - "$evidence_copy" "$normalized" "$HARNESS_LOG_DIR/role-snapshots/$role" <<'PY' >>"$log" 2>&1
import json
import pathlib
import sys

evidence = pathlib.Path(sys.argv[1])
normalized = pathlib.Path(sys.argv[2])
snapshot_root = pathlib.Path(sys.argv[3])
data = json.loads(evidence.read_text())
refs = data.get("bounded_log_references", "")
mapped = []
for ref in refs.split(";"):
    if not ref:
        continue
    if ref.startswith("/"):
        mapped_ref = snapshot_root / ref.removeprefix("/")
        mapped.append(str(mapped_ref))
    else:
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

cmd_configure_role() {
  local role helper service log rc evidence role_env_file
  bootstrap_harness_env
  ensure_runtime_config
  role="${1:-}"
  if [ -z "$role" ]; then
    run_all_roles configure-role
    return "$?"
  fi
  helper="$(helper_for_role "$role")"
  service="$(service_for_role "$role")"
  require_running_service "$service"

  log="$(bounded_log_path "configure-role-$role")"
  : >"$log"
  if ! role_helper_present_in_container "$service" "$helper"; then
    evidence="$(write_evidence configure-role "$role" blocked "simulate.sh configure-role" "$log" "Missing executable role helper /workspace/$helper in target container")"
    printf 'ERROR: Missing role helper for %s in target container: /workspace/%s\n' "$role" "$helper" >>"$log"
    printf 'exit=1 log=%s evidence=%s\n' "$log" "$evidence" >&2
    return 1
  fi
  role_env_file="$(stage_container_role_env "$role" "$service" "$log")"

  case "$role" in
    gerrit)
      stage_gerrit_ldap_bind_secret "$log" "$service"
      if require_staged_artifacts_in_target gerrit "$service" "$log" &&
        reset_gerrit_site_state "$service" "$log" &&
        prepare_product_home_ownership gerrit "$service" "$log" &&
        compose exec -T -u ci-operator "$service" env "$(gerrit_target_secret_env)" "/workspace/$helper" --env "$role_env_file" --yes install >>"$log" 2>&1 &&
        compose exec -T -u ci-operator "$service" env "$(gerrit_target_secret_env)" "/workspace/$helper" --env "$role_env_file" --yes configure >>"$log" 2>&1; then
        rc=0
      else
        rc=$?
      fi
      ;;
    jenkins-controller)
      if require_staged_artifacts_in_target jenkins-controller "$service" "$log" &&
        prepare_product_home_ownership jenkins-controller "$service" "$log" &&
        compose exec -T -u ci-operator "$service" env LDAP_BIND_PASSWORD="$HARNESS_LDAP_BIND_PASSWORD" "/workspace/$helper" --env "$role_env_file" --yes install >>"$log" 2>&1 &&
        compose exec -T -u ci-operator "$service" env LDAP_BIND_PASSWORD="$HARNESS_LDAP_BIND_PASSWORD" "/workspace/$helper" --env "$role_env_file" --yes configure-service >>"$log" 2>&1 &&
        compose exec -T -u ci-operator "$service" env LDAP_BIND_PASSWORD="$HARNESS_LDAP_BIND_PASSWORD" "/workspace/$helper" --env "$role_env_file" --yes install-plugins >>"$log" 2>&1 &&
        compose exec -T -u ci-operator "$service" env LDAP_BIND_PASSWORD="$HARNESS_LDAP_BIND_PASSWORD" "/workspace/$helper" --env "$role_env_file" --yes configure-jcasc >>"$log" 2>&1; then
        rc=0
      else
        rc=$?
      fi
      ;;
    jenkins-agent)
      if require_staged_artifacts_in_target jenkins-agent "$service" "$log" &&
        prepare_product_home_ownership jenkins-agent "$service" "$log" &&
        compose exec -T -u ci-operator "$service" "/workspace/$helper" --env "$role_env_file" --yes install >>"$log" 2>&1 &&
        compose exec -T -u ci-operator "$service" "/workspace/$helper" --env "$role_env_file" --yes configure-runtime >>"$log" 2>&1; then
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

cmd_validate_role() {
  local role helper service log rc evidence role_env_file
  bootstrap_harness_env
  ensure_runtime_config
  role="${1:-}"
  if [ -z "$role" ]; then
    run_all_roles validate-role
    return "$?"
  fi
  helper="$(helper_for_role "$role")"
  service="$(service_for_role "$role")"
  require_running_service "$service"
  check_target_os_release "$role"

  log="$(bounded_log_path "validate-role-$role")"
  : >"$log"
  if ! role_helper_present_in_container "$service" "$helper"; then
    evidence="$(write_evidence validate-role "$role" blocked "simulate.sh validate-role" "$log" "Missing executable role helper /workspace/$helper in target container")"
    printf 'ERROR: Missing role helper for %s in target container: /workspace/%s\n' "$role" "$helper" >>"$log"
    printf 'exit=1 log=%s evidence=%s\n' "$log" "$evidence" >&2
    return 1
  fi
  role_env_file="$(stage_container_role_env "$role" "$service" "$log")"

  case "$role" in
    gerrit)
      stage_gerrit_ldap_bind_secret "$log" "$service"
      if compose exec -T -u ci-operator "$service" env "$(gerrit_target_secret_env)" "/workspace/$helper" --env "$role_env_file" --yes validate >>"$log" 2>&1 &&
        compose exec -T -u ci-operator "$service" env "$(gerrit_target_secret_env)" "/workspace/$helper" --env "$role_env_file" --yes collect-evidence >>"$log" 2>&1 &&
        normalize_gerrit_role_evidence_logs "$log"; then
        rc=0
      else
        rc=$?
      fi
      ;;
    jenkins-controller)
      if compose exec -T -u ci-operator "$service" env LDAP_BIND_PASSWORD="$HARNESS_LDAP_BIND_PASSWORD" "/workspace/$helper" --env "$role_env_file" validate >>"$log" 2>&1 &&
        compose exec -T -u ci-operator "$service" env LDAP_BIND_PASSWORD="$HARNESS_LDAP_BIND_PASSWORD" "/workspace/$helper" --env "$role_env_file" collect-evidence >>"$log" 2>&1 &&
        normalize_jenkins_controller_role_evidence_logs "$log"; then
        rc=0
      else
        rc=$?
      fi
      ;;
    jenkins-agent)
      if compose exec -T -u ci-operator "$service" "/workspace/$helper" --env "$role_env_file" validate >>"$log" 2>&1 &&
        compose exec -T -u ci-operator "$service" "/workspace/$helper" --env "$role_env_file" collect-evidence >>"$log" 2>&1 &&
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

integration_validate_marker_path() {
  printf '%s/rendered/integration-validate-pass.env\n' "$HARNESS_HOST_DIR"
}

write_integration_validate_marker() {
  local marker fingerprint
  marker="$(integration_validate_marker_path)"
  fingerprint="$(runtime_env_fingerprint)"
  mkdir -p "$(dirname "$marker")"
  cat >"$marker" <<EOF
mode=$HARNESS_MODE
run_id=$HARNESS_RUN_ID
project_name=$HARNESS_PROJECT_NAME
runtime_env_fingerprint=$fingerprint
EOF
  chmod 0600 "$marker"
}

prove_integration_validate_marker() {
  local marker fingerprint
  marker="$(integration_validate_marker_path)"
  [ -f "$marker" ] || die "Missing successful validate-integration marker; run validate-integration first"
  [ "$(marker_value "$marker" mode)" = "$HARNESS_MODE" ] ||
    die "Validate-integration marker mode does not match selected runtime config"
  [ "$(marker_value "$marker" run_id)" = "$HARNESS_RUN_ID" ] ||
    die "Validate-integration marker run ID does not match selected runtime config"
  [ "$(marker_value "$marker" project_name)" = "$HARNESS_PROJECT_NAME" ] ||
    die "Validate-integration marker project name does not match selected runtime config"
  fingerprint="$(runtime_env_fingerprint)"
  [ "$(marker_value "$marker" runtime_env_fingerprint)" = "$fingerprint" ] ||
    die "Validate-integration marker runtime env fingerprint does not match selected runtime config"
}

cmd_configure_integration() {
  local log rc evidence
  bootstrap_harness_env
  ensure_runtime_config
  refresh_integration_args

  [ -x "$integration_helper" ] || die "Missing executable integration helper: $integration_helper"
  log="$(bounded_log_path configure-integration)"
  "$integration_helper" "${integration_args[@]}" --yes configure-integration >"$log" 2>&1 || rc=$?
  rc="${rc:-0}"
  if [ "$rc" -eq 0 ]; then
    if ! assert_no_forbidden_success_markers "$log"; then
      evidence="$(write_evidence configure-integration integration fail "simulate.sh configure-integration" "$log" "Forbidden success marker found in integration configuration log")"
      print_command_failure configure-integration "" failed "$log" "$evidence"
      return 1
    fi
    evidence="$(write_evidence configure-integration integration pass "simulate.sh configure-integration" "$log" "Shared integration helper completed cross-role setup/configuration")"
    print_command_summary configure-integration "" ok
    return 0
  fi

  evidence="$(write_evidence configure-integration integration fail "simulate.sh configure-integration" "$log" "Shared integration helper failed cross-role setup/configuration")"
  print_command_failure configure-integration "" failed "$log" "$evidence"
  return "$rc"
}

cmd_validate_integration() {
  local log rc evidence
  bootstrap_harness_env
  ensure_runtime_config
  refresh_integration_args

  [ -x "$integration_helper" ] || die "Missing executable integration helper: $integration_helper"
  log="$(bounded_log_path validate-integration)"
  "$integration_helper" "${integration_args[@]}" --yes validate-integration >"$log" 2>&1 || rc=$?
  rc="${rc:-0}"
  if [ "$rc" -eq 0 ]; then
    if ! assert_no_forbidden_success_markers "$log"; then
      evidence="$(write_evidence validate-integration integration fail "simulate.sh validate-integration" "$log" "Forbidden success marker found in integration validation log")"
      print_command_failure validate-integration "" failed "$log" "$evidence"
      return 1
    fi
    evidence="$(write_evidence validate-integration integration pass "simulate.sh validate-integration" "$log" "Shared integration helper validated cross-role readiness without end-to-end proof")"
    write_integration_validate_marker
    print_command_summary validate-integration "" ok
    return 0
  fi

  write_blocked_integration_evidence jenkins-to-gerrit-ssh "$log" "Blocked: shared integration helper has not implemented real Jenkins-to-Gerrit SSH validation"
  write_blocked_integration_evidence agent-connection "$log" "Blocked: shared integration helper has not implemented real Jenkins-to-agent readiness validation"
  evidence="$(write_evidence validate-integration integration blocked "simulate.sh validate-integration" "$log" "Shared integration helper reported blocked cross-role validation; Docker simulation cannot claim readiness")"
  print_command_summary validate-integration "" blocked
  return "$rc"
}

cmd_prove_integration() {
  local log rc evidence
  bootstrap_harness_env
  ensure_runtime_config
  refresh_integration_args
  prove_integration_validate_marker

  [ -x "$integration_helper" ] || die "Missing executable integration helper: $integration_helper"
  log="$(bounded_log_path prove-integration)"
  "$integration_helper" "${integration_args[@]}" --yes prove-integration >"$log" 2>&1 || rc=$?
  rc="${rc:-0}"
  if [ "$rc" -eq 0 ]; then
    if ! assert_no_forbidden_success_markers "$log"; then
      evidence="$(write_evidence prove-integration integration fail "simulate.sh prove-integration" "$log" "Forbidden success marker found in integration proof log")"
      print_command_failure prove-integration "" failed "$log" "$evidence"
      return 1
    fi
    evidence="$(write_evidence prove-integration integration pass "simulate.sh prove-integration" "$log" "Shared integration helper proved disposable change, Gerrit event receipt, Jenkins job scheduling, agent execution, and Verified +1")"
    print_command_summary prove-integration "" ok
    return 0
  fi

  write_blocked_integration_evidence job-execution "$log" "Blocked: shared integration helper has not implemented real disposable Jenkins job execution proof"
  write_blocked_integration_evidence verified-vote "$log" "Blocked: shared integration helper has not implemented real Gerrit Verified +1 vote proof"
  evidence="$(write_evidence prove-integration integration blocked "simulate.sh prove-integration" "$log" "Shared integration helper reported blocked proof; Docker simulation cannot claim end-to-end success")"
  print_command_summary prove-integration "" blocked
  return "$rc"
}

cmd_audit_state() {
  bootstrap_harness_env
  ensure_runtime_config
  require_command docker
  detect_compose
  verify_selected_container_mounts
  print_command_summary audit-state "" "ok"
}

cmd_down() {
  local log rc evidence container
  bootstrap_harness_env
  require_command docker
  if runtime_config_valid; then
    detect_compose
    log="$(bounded_log_path down)"
    if compose down >"$log" 2>&1; then
      rc=0
    else
      rc=$?
    fi
  else
    ensure_preflight_dirs
    log="$(bounded_log_path down)"
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
    evidence="$(write_evidence down harness fail "simulate.sh down" "$log" "Compose down failed")"
    print_command_failure down "" failed "$log" "$evidence"
    return "$rc"
  fi
  evidence="$(write_evidence down harness pass "simulate.sh down" "$log" "Stopped harness containers without deleting retained evidence")"
  print_command_summary down "" "stopped harness containers"
}

cleanup_mutable_paths_host() {
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

cleanup_mutable_paths_container() {
  local log
  log="${1:?log required}"
  docker run --rm \
    --mount "type=bind,source=$HARNESS_GENERATED_RUN_DIR,target=/cleanup-root" \
    "$HARNESS_UBUNTU_IMAGE" \
    sh -c 'rm -rf -- /cleanup-root/target/helper-state /cleanup-root/target/product-homes /cleanup-root/target/artifacts/staging /cleanup-root/target/ldap /cleanup-root/target/shared-jenkins-storage /cleanup-root/host/rendered /cleanup-root/host/runtime-inputs /cleanup-root/host/target-ssh /cleanup-root/host/validation-secrets /cleanup-root/host/bundle-factory' \
    >>"$log" 2>&1
}

backup_and_clear_retained_outputs_container() {
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

canonical_run_root_exists_for_recovery() {
  local expected actual_real expected_real
  expected="$(canonical_generated_run_dir)"
  [ "$HARNESS_GENERATED_RUN_DIR" = "$expected" ] || return 1
  [ -d "$HARNESS_GENERATED_RUN_DIR" ] || return 1
  [ ! -L "$HARNESS_GENERATED_RUN_DIR" ] || return 1
  actual_real="$(realpath "$HARNESS_GENERATED_RUN_DIR")"
  expected_real="$(realpath "$expected")"
  [ "$actual_real" = "$expected_real" ]
}

verify_clean_output_dirs() {
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

cmd_clean() {
  local log rc evidence cleanup_fallback container backup_name backup_path recovery_run_root_exists
  bootstrap_harness_env
  require_command docker
  recovery_run_root_exists=0
  if runtime_config_valid; then
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
    if canonical_run_root_exists_for_recovery; then
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
      if ! cleanup_mutable_paths_container "$log"; then
        evidence="$(write_evidence clean harness fail "simulate.sh clean" "$log" "Generated runtime cleanup failed during recovery")"
        print_command_failure clean "" failed "$log" "$evidence"
        return 1
      fi
      backup_path="$(backup_and_clear_retained_outputs_container "$log" "$backup_name")" || rc=$?
      rc="${rc:-0}"
      if [ "$rc" -ne 0 ]; then
        evidence="$(write_evidence clean harness fail "simulate.sh clean" "$log" "Retained output backup failed during recovery")"
        print_command_failure clean "" failed "$log" "$evidence"
        return "$rc"
      fi
      verify_clean_output_dirs
      evidence="$(write_evidence clean harness pass "simulate.sh clean" "$log" "Removed selected containers, cleaned mutable generated runtime data, and backed up retained outputs during recovery to $backup_path")"
      print_command_summary clean "" "removed containers runtime data backup=$backup_name cleanup=$cleanup_fallback"
      return 0
    else
      evidence="$(write_evidence clean harness pass "simulate.sh clean" "$log" "Removed selected containers with bootstrap recovery; host generated cleanup skipped because runtime config is invalid or missing")"
      print_command_summary clean "" "removed containers cleanup=skipped reason=invalid-or-missing-runtime-config"
      return 0
    fi
  fi

  if ! cleanup_mutable_paths_host >>"$log" 2>&1; then
    cleanup_fallback=container
    cleanup_mutable_paths_container "$log" || rc=$?
    rc="${rc:-0}"
    if [ "$rc" -ne 0 ]; then
      evidence="$(write_evidence clean harness fail "simulate.sh clean" "$log" "Generated runtime cleanup failed")"
      print_command_failure clean "" failed "$log" "$evidence"
      return "$rc"
    fi
  fi
  backup_name="clean-$(timestamp_utc)"
  backup_path="$(backup_and_clear_retained_outputs_container "$log" "$backup_name")" || rc=$?
  rc="${rc:-0}"
  if [ "$rc" -ne 0 ]; then
    evidence="$(write_evidence clean harness fail "simulate.sh clean" "$log" "Retained output backup failed")"
    print_command_failure clean "" failed "$log" "$evidence"
    return "$rc"
  fi
  ensure_preflight_dirs
  verify_clean_output_dirs
  evidence="$(write_evidence clean harness pass "simulate.sh clean" "$log" "Removed mutable generated runtime data and backed up retained outputs to $backup_path")"
  print_command_summary clean "" "removed runtime data backup=$backup_name cleanup=$cleanup_fallback"
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
    run)
      shift
      parse_env_only_args "$@"
      cmd_run
      ;;
    preflight)
      shift
      parse_env_only_args "$@"
      cmd_preflight
      ;;
    init-run)
      shift
      parse_env_only_args "$@"
      cmd_init_run
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
    ssh)
      shift
      parse_env_and_role_args 1 "$@"
      cmd_ssh "$PARSED_ROLE"
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
    configure-role)
      shift
      parse_env_and_role_args 0 "$@"
      cmd_configure_role "$PARSED_ROLE"
      ;;
    validate-role)
      shift
      parse_env_and_role_args 0 "$@"
      cmd_validate_role "$PARSED_ROLE"
      ;;
    configure-integration)
      shift
      parse_env_only_args "$@"
      cmd_configure_integration
      ;;
    validate-integration)
      shift
      parse_env_only_args "$@"
      cmd_validate_integration
      ;;
    prove-integration)
      shift
      parse_env_only_args "$@"
      cmd_prove_integration
      ;;
    audit-state)
      shift
      parse_env_only_args "$@"
      cmd_audit_state
      ;;
    down)
      shift
      parse_env_only_args "$@"
      cmd_down
      ;;
    clean)
      shift
      parse_env_only_args "$@"
      cmd_clean
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
