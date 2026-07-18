#!/usr/bin/env bash

docker_generated_root() {
  printf '%s/generated/simulation/docker\n' "$repo_root"
}

canonical_generated_run_dir() {
  printf '%s/%s\n' "$(docker_generated_root)" "$HARNESS_RUN_ID"
}

apply_canonical_output_paths() {
  HARNESS_GENERATED_RUN_DIR="$(canonical_generated_run_dir)"
  HARNESS_HOST_DIR="$HARNESS_GENERATED_RUN_DIR/host"
  HARNESS_TARGET_DIR="$HARNESS_GENERATED_RUN_DIR/target"
  HARNESS_SET_DIR="$(docker_generated_root)/sets/$HARNESS_SET_ID"
  HARNESS_SET_RUNTIME_DIR="$HARNESS_SET_DIR/runtime"
  HARNESS_DOCKER_SET_RECORD="$HARNESS_SET_DIR/docker-set.env"
  HARNESS_STATE_DIR="$HARNESS_SET_RUNTIME_DIR/helper-state"
  HARNESS_PRODUCT_HOME_DIR="$HARNESS_SET_RUNTIME_DIR/product-homes"
  HARNESS_STAGING_DIR="$HARNESS_SET_RUNTIME_DIR/artifacts/staging"
  HARNESS_EXPORTED_ARTIFACT_DIR="$HARNESS_TARGET_DIR/artifacts/exported"
  HARNESS_EVIDENCE_DIR="$HARNESS_HOST_DIR/evidence/harness"
  HARNESS_LOG_DIR="$HARNESS_HOST_DIR/logs/harness"
  HARNESS_RETAINED_OUTPUT_BACKUP_DIR="$HARNESS_HOST_DIR/retained-output-backups"
  HARNESS_RENDERED_ENV="$HARNESS_HOST_DIR/rendered/harness.env"
  HARNESS_RUNTIME_ENV="$HARNESS_HOST_DIR/rendered/harness.runtime.env"
  HARNESS_SOURCE_INPUT_DIR="$HARNESS_HOST_DIR/source-inputs"
  HARNESS_RUNTIME_INPUT_DIR="$HARNESS_HOST_DIR/runtime-inputs"
  HARNESS_EFFECTIVE_INPUT_RECORD="$HARNESS_HOST_DIR/state/effective-inputs.env"
  HARNESS_BASELINE_CONTRACT="$HARNESS_HOST_DIR/rendered/artifact-manifest-contract.txt"
  HARNESS_RUN_MARKER="$HARNESS_GENERATED_RUN_DIR/.loopforge-docker-run.env"
  HARNESS_SET_LOCK="$(simulation_set_lock_path "$(docker_generated_root)" "$HARNESS_SET_ID")"
  HARNESS_ACTIVE_RUN_FILE="$HARNESS_SET_DIR/active-run.env"
  HARNESS_WORKFLOW_STATE_FILE="$HARNESS_HOST_DIR/state/workflow-state.env"
  HARNESS_CHECKPOINT_RECORD_DIR="$HARNESS_HOST_DIR/state/checkpoints"
  HARNESS_TARGET_SSH_DIR="$HARNESS_HOST_DIR/target-ssh"
  HARNESS_TARGET_SSH_IDENTITY_FILE="$HARNESS_TARGET_SSH_DIR/ci-operator"
  HARNESS_TARGET_SSH_KNOWN_HOSTS_FILE="$HARNESS_TARGET_SSH_DIR/known_hosts"
  HARNESS_GERRIT_VALIDATION_SECRET_DIR="$HARNESS_HOST_DIR/validation-secrets/gerrit"
  HARNESS_BUNDLE_FACTORY_RENDERED_DIR="$HARNESS_HOST_DIR/bundle-factory/rendered"
  HARNESS_BUNDLE_FACTORY_VALIDATION_PUBLIC_DIR="$HARNESS_HOST_DIR/bundle-factory/validation-public"
  HARNESS_LDAP_DATA_DIR="$HARNESS_SET_RUNTIME_DIR/ldap/data"
  HARNESS_LDAP_CONFIG_DIR="$HARNESS_SET_RUNTIME_DIR/ldap/config"
  HARNESS_SHARED_JENKINS_STORAGE_DIR="$HARNESS_SET_RUNTIME_DIR/shared-jenkins-storage"
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
  export HARNESS_RENDERED_ENV HARNESS_RUNTIME_ENV HARNESS_SOURCE_INPUT_DIR
  export HARNESS_RUNTIME_INPUT_DIR HARNESS_EFFECTIVE_INPUT_RECORD
  export HARNESS_BASELINE_CONTRACT HARNESS_RUN_MARKER
  export HARNESS_SET_DIR HARNESS_SET_RUNTIME_DIR HARNESS_DOCKER_SET_RECORD
  export HARNESS_SET_LOCK HARNESS_ACTIVE_RUN_FILE
  export HARNESS_WORKFLOW_STATE_FILE HARNESS_CHECKPOINT_RECORD_DIR
  export HARNESS_TARGET_SSH_DIR HARNESS_TARGET_SSH_IDENTITY_FILE
  export HARNESS_TARGET_SSH_KNOWN_HOSTS_FILE
  export HARNESS_GERRIT_VALIDATION_SECRET_DIR HARNESS_BUNDLE_FACTORY_RENDERED_DIR
  export HARNESS_BUNDLE_FACTORY_VALIDATION_PUBLIC_DIR HARNESS_LDAP_DATA_DIR
  export HARNESS_LDAP_CONFIG_DIR HARNESS_SHARED_JENKINS_STORAGE_DIR
  export HARNESS_GERRIT_EVIDENCE_DIR HARNESS_GERRIT_LOG_DIR
  export HARNESS_JENKINS_CONTROLLER_EVIDENCE_DIR HARNESS_JENKINS_CONTROLLER_LOG_DIR
  export HARNESS_JENKINS_AGENT_EVIDENCE_DIR HARNESS_JENKINS_AGENT_LOG_DIR
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
    HARNESS_SET_RUNTIME_DIR \
    HARNESS_DOCKER_SET_RECORD \
    HARNESS_RENDERED_ENV \
    HARNESS_SOURCE_INPUT_DIR \
    HARNESS_RUNTIME_INPUT_DIR \
    HARNESS_EFFECTIVE_INPUT_RECORD \
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
      HARNESS_SET_RUNTIME_DIR) expected="$(docker_generated_root)/sets/$HARNESS_SET_ID/runtime" ;;
      HARNESS_DOCKER_SET_RECORD) expected="$(docker_generated_root)/sets/$HARNESS_SET_ID/docker-set.env" ;;
      HARNESS_STATE_DIR) expected="$(docker_generated_root)/sets/$HARNESS_SET_ID/runtime/helper-state" ;;
      HARNESS_PRODUCT_HOME_DIR) expected="$(docker_generated_root)/sets/$HARNESS_SET_ID/runtime/product-homes" ;;
      HARNESS_STAGING_DIR) expected="$(docker_generated_root)/sets/$HARNESS_SET_ID/runtime/artifacts/staging" ;;
      HARNESS_EXPORTED_ARTIFACT_DIR) expected="$(canonical_generated_run_dir)/target/artifacts/exported" ;;
      HARNESS_EVIDENCE_DIR) expected="$(canonical_generated_run_dir)/host/evidence/harness" ;;
      HARNESS_LOG_DIR) expected="$(canonical_generated_run_dir)/host/logs/harness" ;;
      HARNESS_RETAINED_OUTPUT_BACKUP_DIR) expected="$(canonical_generated_run_dir)/host/retained-output-backups" ;;
      HARNESS_RENDERED_ENV) expected="$(canonical_generated_run_dir)/host/rendered/harness.env" ;;
      HARNESS_SOURCE_INPUT_DIR) expected="$(canonical_generated_run_dir)/host/source-inputs" ;;
      HARNESS_RUNTIME_INPUT_DIR) expected="$(canonical_generated_run_dir)/host/runtime-inputs" ;;
      HARNESS_EFFECTIVE_INPUT_RECORD) expected="$(canonical_generated_run_dir)/host/state/effective-inputs.env" ;;
      HARNESS_BASELINE_CONTRACT) expected="$(canonical_generated_run_dir)/host/rendered/artifact-manifest-contract.txt" ;;
      HARNESS_TARGET_SSH_DIR) expected="$(canonical_generated_run_dir)/host/target-ssh" ;;
      HARNESS_GERRIT_VALIDATION_SECRET_DIR) expected="$(canonical_generated_run_dir)/host/validation-secrets/gerrit" ;;
      HARNESS_BUNDLE_FACTORY_RENDERED_DIR) expected="$(canonical_generated_run_dir)/host/bundle-factory/rendered" ;;
      HARNESS_BUNDLE_FACTORY_VALIDATION_PUBLIC_DIR) expected="$(canonical_generated_run_dir)/host/bundle-factory/validation-public" ;;
      HARNESS_LDAP_DATA_DIR) expected="$(docker_generated_root)/sets/$HARNESS_SET_ID/runtime/ldap/data" ;;
      HARNESS_LDAP_CONFIG_DIR) expected="$(docker_generated_root)/sets/$HARNESS_SET_ID/runtime/ldap/config" ;;
      HARNESS_SHARED_JENKINS_STORAGE_DIR) expected="$(docker_generated_root)/sets/$HARNESS_SET_ID/runtime/shared-jenkins-storage" ;;
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
