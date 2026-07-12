#!/usr/bin/env bash

docker_dir="$script_dir"
compose_file="$docker_dir/compose.yaml"
docker_env_example="$docker_dir/examples/docker.env.example"
integration_helper="${HARNESS_TEST_INTEGRATION_HELPER:-$repo_root/scripts/integration-setup.sh}"
services=(bundle-factory ldap gerrit-target jenkins-controller-target jenkins-agent-target)
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

write_run_marker() {
  write_runtime_marker \
    "$HARNESS_RUN_MARKER" \
    "$HARNESS_MODE" \
    "$HARNESS_RUN_ID" \
    "$HARNESS_PROJECT_NAME" \
    "$repo_root" \
    "$HARNESS_GENERATED_RUN_DIR" \
    "$HARNESS_RUNTIME_ENV"
}

verify_run_marker() {
  local marker
  marker="${HARNESS_RUN_MARKER:-$HARNESS_GENERATED_RUN_DIR/.loopforge-docker-run.env}"
  validate_canonical_run_root
  verify_runtime_marker \
    "$marker" \
    "$HARNESS_MODE" \
    "$HARNESS_RUN_ID" \
    "$HARNESS_PROJECT_NAME" \
    "$repo_root" \
    "$HARNESS_GENERATED_RUN_DIR" \
    "$HARNESS_RUNTIME_ENV" \
    "Docker harness run marker"
}

validate_core_generated_state() {
  local role service state_name
  state_name="Docker generated state"
  validate_canonical_run_root
  require_generated_state_file "$state_name" "rendered harness env" "$HARNESS_RENDERED_ENV"
  require_generated_state_file "$state_name" "runtime harness env" "$HARNESS_RUNTIME_ENV"
  require_generated_state_file "$state_name" "artifact manifest contract" "$HARNESS_BASELINE_CONTRACT"
  require_generated_state_dir "$state_name" "runtime input directory" "$HARNESS_RUNTIME_INPUT_DIR"
  require_generated_state_file "$state_name" "runtime input harness env" "$HARNESS_RUNTIME_INPUT_DIR/harness.env"
  require_generated_state_file "$state_name" "runtime input Gerrit env" "$HARNESS_RUNTIME_INPUT_DIR/gerrit.env"
  require_generated_state_file "$state_name" "runtime input Jenkins controller env" "$HARNESS_RUNTIME_INPUT_DIR/jenkins-controller.env"
  require_generated_state_file "$state_name" "runtime input Jenkins agent env" "$HARNESS_RUNTIME_INPUT_DIR/jenkins-agent.env"
  require_generated_state_file "$state_name" "runtime input integration env" "$HARNESS_RUNTIME_INPUT_DIR/integration.env"
  require_generated_state_file "$state_name" "bundle factory Gerrit helper env" "$(host_gerrit_bundle_factory_env_file)"
  require_generated_state_file "$state_name" "bundle factory Jenkins controller helper env" "$(host_jenkins_controller_bundle_factory_env_file)"
  require_generated_state_file "$state_name" "bundle factory Jenkins agent helper env" "$(host_container_env_file_for_role jenkins-agent bundle-factory)"
  for role in "${roles[@]}"; do
    service="$(service_for_role "$role")"
    require_generated_state_file "$state_name" "$role target helper env" "$(host_container_env_file_for_role "$role" "$service")"
  done
  require_generated_state_dir "$state_name" "host contribution directory" "$HARNESS_HOST_DIR"
  require_generated_state_dir "$state_name" "target contribution directory" "$HARNESS_TARGET_DIR"
  require_generated_state_dir "$state_name" "product home directory" "$HARNESS_PRODUCT_HOME_DIR"
  require_generated_state_dir "$state_name" "staging directory" "$HARNESS_STAGING_DIR"
  require_generated_state_dir "$state_name" "exported artifact directory" "$HARNESS_EXPORTED_ARTIFACT_DIR"
  require_generated_state_dir "$state_name" "evidence directory" "$HARNESS_EVIDENCE_DIR"
  require_generated_state_dir "$state_name" "log directory" "$HARNESS_LOG_DIR"
  require_generated_state_dir "$state_name" "bundle factory operator input source" "$HARNESS_BUNDLE_FACTORY_RENDERED_DIR"
  require_generated_state_dir "$state_name" "LDAP data bind source" "$HARNESS_LDAP_DATA_DIR"
  require_generated_state_dir "$state_name" "LDAP config bind source" "$HARNESS_LDAP_CONFIG_DIR"
  require_generated_state_dir "$state_name" "Gerrit product home bind source" "$HARNESS_PRODUCT_HOME_DIR/gerrit"
  require_generated_state_dir "$state_name" "Jenkins controller product home bind source" "$HARNESS_PRODUCT_HOME_DIR/jenkins-controller"
  require_generated_state_dir "$state_name" "Jenkins agent product home bind source" "$HARNESS_PRODUCT_HOME_DIR/jenkins-agent"
  require_generated_state_dir "$state_name" "shared Jenkins storage bind source" "$HARNESS_SHARED_JENKINS_STORAGE_DIR"
  require_generated_state_dir "$state_name" "target SSH state" "$HARNESS_TARGET_SSH_DIR"
  require_generated_state_file "$state_name" "target SSH identity file" "$HARNESS_TARGET_SSH_IDENTITY_FILE"
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

resolve_repo_relative_path() {
  resolve_base_relative_path "$repo_root" "${1:?path required}"
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
  source_env_file "Harness env file" "$file"
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
  source_env_file "Docker harness runtime config" "$runtime"
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
  any_path_exists \
    "$HARNESS_RUN_MARKER" \
    "$HARNESS_RENDERED_ENV" \
    "$HARNESS_RUNTIME_ENV" \
    "$HARNESS_RUNTIME_INPUT_DIR" \
    "$HARNESS_HOST_DIR/rendered"
}

verify_selected_container_mounts() {
  validate_selected_container_mounts
}

bootstrap_harness_env() {
  load_env_file "$HARNESS_ENV_FILE"
}

load_harness_integration_env() {
  source_env_file "Integration env file for Docker harness shared storage" "$HARNESS_INTEGRATION_ENV_FILE"
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

copy_runtime_env_inputs() {
  HARNESS_RUNTIME_INPUT_DIR="$HARNESS_HOST_DIR/runtime-inputs"
  rm -rf "$HARNESS_RUNTIME_INPUT_DIR"
  copy_simulation_runtime_env_inputs \
    "$HARNESS_RUNTIME_INPUT_DIR" \
    "$HARNESS_ENV_FILE" \
    "$HARNESS_GERRIT_ENV_FILE" \
    "$HARNESS_JENKINS_CONTROLLER_ENV_FILE" \
    "$HARNESS_JENKINS_AGENT_ENV_FILE" \
    "$HARNESS_INTEGRATION_ENV_FILE"
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
    "$HARNESS_BUNDLE_FACTORY_VALIDATION_PUBLIC_DIR" \
    "$HARNESS_LDAP_DATA_DIR" \
    "$HARNESS_LDAP_CONFIG_DIR" \
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
  local name
  name="${1:?log name required}"
  bounded_log_path_in_dir "$(bounded_log_dir_for_name "$name")" "$name"
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
