#!/usr/bin/env bash

write_run_marker() {
  write_runtime_marker \
    "$HARNESS_RUN_MARKER" \
    "$HARNESS_MODE" \
    docker \
    "$HARNESS_SET_ID" \
    "$HARNESS_RUN_ID" \
    "$HARNESS_PROJECT_NAME" \
    "$repo_root" \
    "$HARNESS_GENERATED_RUN_DIR" \
    "$HARNESS_RUNTIME_ENV" \
    "$HARNESS_SOURCE_INPUT_DIR"
}

verify_run_marker() {
  local marker
  marker="${HARNESS_RUN_MARKER:-$HARNESS_GENERATED_RUN_DIR/.loopforge-docker-run.env}"
  validate_canonical_run_root
  verify_runtime_marker \
    "$marker" \
    "$HARNESS_MODE" \
    docker \
    "$HARNESS_SET_ID" \
    "$HARNESS_RUN_ID" \
    "$HARNESS_PROJECT_NAME" \
    "$repo_root" \
    "$HARNESS_GENERATED_RUN_DIR" \
    "$HARNESS_RUNTIME_ENV" \
    "$HARNESS_SOURCE_INPUT_DIR" \
    "Docker harness run marker"
}

write_initial_lifecycle_records() {
  local source_fingerprint
  source_fingerprint="$(simulation_input_bundle_fingerprint "$HARNESS_SOURCE_INPUT_DIR")" || return $?
  write_initial_workflow_state \
    "$HARNESS_WORKFLOW_STATE_FILE" docker "$HARNESS_SET_ID" "$HARNESS_RUN_ID" \
    "$HARNESS_RUN_MARKER" none "$source_fingerprint" || return $?
  write_active_run_record \
    "$HARNESS_ACTIVE_RUN_FILE" docker "$HARNESS_SET_ID" "$HARNESS_RUN_ID" \
    "$HARNESS_PROJECT_NAME" "$HARNESS_RUN_MARKER" none active none
}

verify_active_run_binding() {
  lifecycle_records_are_bound \
    "$HARNESS_ACTIVE_RUN_FILE" "$HARNESS_RUN_MARKER" \
    "$HARNESS_WORKFLOW_STATE_FILE" docker "$HARNESS_SET_ID" "$HARNESS_RUN_ID" \
    "$HARNESS_PROJECT_NAME" "$(simulation_input_bundle_fingerprint "$HARNESS_SOURCE_INPUT_DIR")" ||
    die "Docker active-run, run marker, and workflow state do not agree"
  simulation_input_state_is_bound "$HARNESS_WORKFLOW_STATE_FILE" "$HARNESS_RUN_MARKER" \
    docker "$HARNESS_SET_ID" "$HARNESS_RUN_ID" "$HARNESS_SOURCE_INPUT_DIR" \
    "$HARNESS_EFFECTIVE_INPUT_RECORD" "$HARNESS_RUNTIME_INPUT_DIR" ||
    die "Docker source/effective input state does not agree"
}

require_docker_effective_inputs() {
  require_effective_inputs_ready "$HARNESS_WORKFLOW_STATE_FILE" "$HARNESS_RUN_MARKER" \
    docker "$HARNESS_SET_ID" "$HARNESS_RUN_ID" "$HARNESS_SOURCE_INPUT_DIR" \
    "$HARNESS_EFFECTIVE_INPUT_RECORD" "$HARNESS_RUNTIME_INPUT_DIR"
}

validate_core_generated_state() {
  local role service state_name
  state_name="Docker generated state"
  validate_canonical_run_root
  require_generated_state_file "$state_name" "rendered harness env" "$HARNESS_RENDERED_ENV"
  require_generated_state_file "$state_name" "runtime harness env" "$HARNESS_RUNTIME_ENV"
  require_generated_state_file "$state_name" "artifact manifest contract" "$HARNESS_BASELINE_CONTRACT"
  require_generated_state_file "$state_name" "active-run pointer" "$HARNESS_ACTIVE_RUN_FILE"
  require_generated_state_file "$state_name" "workflow state" "$HARNESS_WORKFLOW_STATE_FILE"
  require_generated_state_dir "$state_name" "source input directory" "$HARNESS_SOURCE_INPUT_DIR"
  require_generated_state_file "$state_name" "source harness env" "$HARNESS_SOURCE_INPUT_DIR/harness.env"
  require_generated_state_file "$state_name" "source Gerrit env" "$HARNESS_SOURCE_INPUT_DIR/gerrit.env"
  require_generated_state_file "$state_name" "source Jenkins controller env" "$HARNESS_SOURCE_INPUT_DIR/jenkins-controller.env"
  require_generated_state_file "$state_name" "source Jenkins agent env" "$HARNESS_SOURCE_INPUT_DIR/jenkins-agent.env"
  require_generated_state_file "$state_name" "source integration env" "$HARNESS_SOURCE_INPUT_DIR/integration.env"
  require_generated_state_dir "$state_name" "host contribution directory" "$HARNESS_HOST_DIR"
  require_generated_state_dir "$state_name" "target contribution directory" "$HARNESS_TARGET_DIR"
  require_generated_state_dir "$state_name" "exported artifact directory" "$HARNESS_EXPORTED_ARTIFACT_DIR"
  require_generated_state_dir "$state_name" "evidence directory" "$HARNESS_EVIDENCE_DIR"
  require_generated_state_dir "$state_name" "log directory" "$HARNESS_LOG_DIR"
  require_generated_state_dir "$state_name" "bundle factory operator input source" "$HARNESS_BUNDLE_FACTORY_RENDERED_DIR"
  require_generated_state_dir "$state_name" "target SSH state" "$HARNESS_TARGET_SSH_DIR"
  require_generated_state_file "$state_name" "target SSH identity file" "$HARNESS_TARGET_SSH_IDENTITY_FILE"
  verify_active_run_binding
  if [ "$(strict_record_value "$HARNESS_WORKFLOW_STATE_FILE" input_state)" = ready ]; then
    require_generated_state_file "$state_name" "effective-input binding" "$HARNESS_EFFECTIVE_INPUT_RECORD"
    require_generated_state_dir "$state_name" "effective input directory" "$HARNESS_RUNTIME_INPUT_DIR"
    for role in harness gerrit jenkins-controller jenkins-agent integration; do
      require_generated_state_file "$state_name" "effective $role env" "$HARNESS_RUNTIME_INPUT_DIR/$role.env"
    done
  fi
}
