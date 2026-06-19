#!/usr/bin/env bash

set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
repo_root="$(CDPATH= cd -- "$script_dir/../.." && pwd)"
harness="$script_dir/docker-harness.sh"
integration_helper="$repo_root/scripts/integration-setup.sh"

usage() {
  cat <<'USAGE'
Usage:
  simulation/docker/docker-verify.sh <command>

Commands:
  preflight
  render-config
  prepare-artifacts
  stage-artifacts
  up
  check
  full-verify
  down

Options:
  -h, --help        Show this help.

The verifier orchestrates the shared Docker harness for role-local lifecycle
work and calls scripts/integration-setup.sh for cross-role integration. It
fails closed when real Jenkins/Gerrit/agent integration proof is unavailable.
USAGE
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

timestamp_utc() {
  date -u +%Y%m%dT%H%M%SZ
}

iso_timestamp_utc() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

validate_name() {
  local name value
  name="${1:?name required}"
  value="${2:?value required}"
  case "$value" in
    [a-z0-9]*) ;;
    *) die "$name must start with a lowercase letter or digit" ;;
  esac
  case "$value" in
    *[!a-z0-9_-]*) die "$name may contain only lowercase letters, digits, underscores, and dashes" ;;
  esac
  [ "${#value}" -le 63 ] || die "$name must be 63 characters or fewer"
}

DOCKER_VERIFY_RUN_ID="${DOCKER_VERIFY_RUN_ID:-default}"
DOCKER_VERIFY_PROJECT_NAME="${DOCKER_VERIFY_PROJECT_NAME:-gerrit-jenkins-docker-${DOCKER_VERIFY_RUN_ID}}"
DOCKER_VERIFY_MODE="${DOCKER_VERIFY_MODE:-docker-simulation}"
DOCKER_VERIFY_STATE_DIR="${DOCKER_VERIFY_STATE_DIR:-$repo_root/simulation/state/docker/$DOCKER_VERIFY_RUN_ID}"
DOCKER_VERIFY_STAGING_DIR="${DOCKER_VERIFY_STAGING_DIR:-$repo_root/simulation/staging/docker/$DOCKER_VERIFY_RUN_ID}"
DOCKER_VERIFY_EVIDENCE_DIR="${DOCKER_VERIFY_EVIDENCE_DIR:-$repo_root/simulation/evidence/docker/$DOCKER_VERIFY_RUN_ID}"
DOCKER_VERIFY_LOG_DIR="${DOCKER_VERIFY_LOG_DIR:-$repo_root/logs/docker/$DOCKER_VERIFY_RUN_ID}"
DOCKER_VERIFY_RENDERED_ENV="$DOCKER_VERIFY_STATE_DIR/rendered/docker-verify.env"

# Role helpers currently recognize the reused role-gate harness mode for
# role-local runtime proof. Docker verifier evidence keeps the full
# docker-simulation label and aggregates harness evidence separately.
export HARNESS_MODE="${HARNESS_MODE:-docker-harness-simulation}"
export HARNESS_RUN_ID="$DOCKER_VERIFY_RUN_ID"
export HARNESS_PROJECT_NAME="$DOCKER_VERIFY_PROJECT_NAME"
export HARNESS_STATE_DIR="$DOCKER_VERIFY_STATE_DIR/harness"
export HARNESS_STAGING_DIR="$DOCKER_VERIFY_STAGING_DIR"
export HARNESS_EVIDENCE_DIR="$DOCKER_VERIFY_EVIDENCE_DIR/harness"
export HARNESS_LOG_DIR="$DOCKER_VERIFY_LOG_DIR/harness"
export HARNESS_PUBLIC_INTERNET_FALLBACK_LABEL="${HARNESS_PUBLIC_INTERNET_FALLBACK_LABEL:-simulation-only}"

roles=(gerrit jenkins-controller jenkins-agent)

ensure_dirs() {
  validate_name "DOCKER_VERIFY_RUN_ID" "$DOCKER_VERIFY_RUN_ID"
  validate_name "DOCKER_VERIFY_PROJECT_NAME" "$DOCKER_VERIFY_PROJECT_NAME"
  mkdir -p \
    "$DOCKER_VERIFY_STATE_DIR/rendered" \
    "$DOCKER_VERIFY_STAGING_DIR" \
    "$DOCKER_VERIFY_EVIDENCE_DIR/docker-verify" \
    "$DOCKER_VERIFY_LOG_DIR" \
    "$HARNESS_STATE_DIR" \
    "$HARNESS_STAGING_DIR" \
    "$HARNESS_EVIDENCE_DIR" \
    "$HARNESS_LOG_DIR"
}

json_quote() {
  local value
  value="${1-}"
  require_command python3
  python3 -c 'import json, sys; print(json.dumps(sys.argv[1]))' "$value"
}

bounded_log_path() {
  local name
  name="${1:?log name required}"
  ensure_dirs
  printf '%s/%s-%s.log' "$DOCKER_VERIFY_LOG_DIR" "$name" "$(timestamp_utc)"
}

write_rendered_env() {
  ensure_dirs
  cat >"$DOCKER_VERIFY_RENDERED_ENV" <<EOF
DOCKER_VERIFY_MODE=$DOCKER_VERIFY_MODE
DOCKER_VERIFY_RUN_ID=$DOCKER_VERIFY_RUN_ID
DOCKER_VERIFY_PROJECT_NAME=$DOCKER_VERIFY_PROJECT_NAME
DOCKER_VERIFY_STATE_DIR=$DOCKER_VERIFY_STATE_DIR
DOCKER_VERIFY_STAGING_DIR=$DOCKER_VERIFY_STAGING_DIR
DOCKER_VERIFY_EVIDENCE_DIR=$DOCKER_VERIFY_EVIDENCE_DIR
DOCKER_VERIFY_LOG_DIR=$DOCKER_VERIFY_LOG_DIR
HARNESS_MODE=$HARNESS_MODE
HARNESS_RUN_ID=$HARNESS_RUN_ID
HARNESS_PROJECT_NAME=$HARNESS_PROJECT_NAME
HARNESS_STATE_DIR=$HARNESS_STATE_DIR
HARNESS_STAGING_DIR=$HARNESS_STAGING_DIR
HARNESS_EVIDENCE_DIR=$HARNESS_EVIDENCE_DIR
HARNESS_LOG_DIR=$HARNESS_LOG_DIR
HARNESS_PUBLIC_INTERNET_FALLBACK_LABEL=$HARNESS_PUBLIC_INTERNET_FALLBACK_LABEL
public_internet_fallback=simulation-only
gerrit_env=$repo_root/examples/gerrit.env.example
jenkins_controller_env=$repo_root/examples/jenkins-controller.env.example
jenkins_agent_env=$repo_root/examples/jenkins-agent.env.example
EOF
}

manifest_ref_for_role() {
  printf '%s/bundle-factory/artifacts/%s/manifest.txt\n' "$HARNESS_STATE_DIR" "$1"
}

checksum_ref_for_role() {
  printf '%s/bundle-factory/artifacts/%s/checksums.sha256\n' "$HARNESS_STATE_DIR" "$1"
}

write_evidence() {
  local checkpoint role status command_name log_ref message file
  local q_mode q_timestamp q_role q_checkpoint q_command q_status q_manifest
  local q_checksum q_message q_log_ref q_redaction q_source q_versions
  checkpoint="${1:?checkpoint required}"
  role="${2:?role required}"
  status="${3:?status required}"
  command_name="${4:?command required}"
  log_ref="${5:-not-applicable}"
  message="${6:-}"

  ensure_dirs
  file="$DOCKER_VERIFY_EVIDENCE_DIR/docker-verify/${checkpoint}-${role}-$(timestamp_utc).json"
  q_mode="$(json_quote "$DOCKER_VERIFY_MODE")"
  q_timestamp="$(json_quote "$(iso_timestamp_utc)")"
  q_role="$(json_quote "$role")"
  q_checkpoint="$(json_quote "$checkpoint")"
  q_command="$(json_quote "$command_name")"
  q_status="$(json_quote "$status")"
  q_manifest="$(json_quote "$(manifest_ref_for_role "$role")")"
  q_checksum="$(json_quote "$(checksum_ref_for_role "$role")")"
  q_message="$(json_quote "$message")"
  q_log_ref="$(json_quote "$log_ref")"
  q_redaction="$(json_quote "secrets-not-recorded")"
  q_source="$(json_quote "Application artifacts are produced by the bundle factory and target-host public internet fallback is simulation-only for Ubuntu/OS dependencies.")"
  q_versions="$(json_quote "Ubuntu 24.04 noble, OpenJDK 21, Gerrit 3.13.6, Jenkins 2.555.3 LTS, Jenkins Plugin Installation Manager 2.15.0")"

  cat >"$file" <<EOF
{
  "verification_mode": $q_mode,
  "timestamp": $q_timestamp,
  "role_or_environment": $q_role,
  "checkpoint_name": $q_checkpoint,
  "command_name": $q_command,
  "status": $q_status,
  "reviewed_input_fingerprint": "examples-env-files",
  "artifact_manifest_references": $q_manifest,
  "checksum_references": $q_checksum,
  "observed_checks": $q_message,
  "bounded_log_references": $q_log_ref,
  "redaction_status": $q_redaction,
  "mode_labels": ["docker-simulation", "simulation-only"],
  "source_boundary": $q_source,
  "version_baseline": $q_versions
}
EOF
  printf '%s\n' "$file"
}

run_logged() {
  local label log rc
  label="${1:?label required}"
  shift
  log="$(bounded_log_path "$label")"
  if "$@" >"$log" 2>&1; then
    rc=0
  else
    rc=$?
  fi
  printf 'exit=%s log=%s\n' "$rc" "$log"
  return "$rc"
}

run_harness_logged() {
  local label
  label="${1:?label required}"
  shift
  run_logged "$label" "$harness" "$@"
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

require_baseline() {
  [ "$HARNESS_PUBLIC_INTERNET_FALLBACK_LABEL" = "simulation-only" ] ||
    die "Public internet fallback label must be simulation-only"
  [ "${HARNESS_UBUNTU_BASELINE_RELEASE:-24.04}" = "24.04" ] ||
    die "Ubuntu baseline release drifted from 24.04"
  [ "${HARNESS_UBUNTU_BASELINE_CODENAME:-noble}" = "noble" ] ||
    die "Ubuntu baseline codename drifted from noble"
  [ "${HARNESS_JAVA_BASELINE:-21}" = "21" ] ||
    die "Java baseline drifted from OpenJDK 21"
  [ "${HARNESS_GERRIT_BASELINE:-3.13.6}" = "3.13.6" ] ||
    die "Gerrit baseline drifted from 3.13.6"
  [ "${HARNESS_JENKINS_BASELINE:-2.555.3}" = "2.555.3" ] ||
    die "Jenkins baseline drifted from 2.555.3"
  [ "${HARNESS_JENKINS_PLUGIN_MANAGER_BASELINE:-2.15.0}" = "2.15.0" ] ||
    die "Jenkins Plugin Installation Manager baseline drifted from 2.15.0"
}

integration_args=(
  --gerrit-env "$repo_root/examples/gerrit.env.example"
  --jenkins-controller-env "$repo_root/examples/jenkins-controller.env.example"
  --jenkins-agent-env "$repo_root/examples/jenkins-agent.env.example"
)

write_blocked_integration_evidence() {
  local checkpoint log reason
  checkpoint="${1:?checkpoint required}"
  log="${2:?log required}"
  reason="${3:?reason required}"
  write_evidence "$checkpoint" integration blocked "scripts/integration-setup.sh" "$log" "$reason" >/dev/null
}

cmd_preflight() {
  local output log rc evidence
  ensure_dirs
  require_command bash
  require_command grep
  require_command python3
  [ -x "$harness" ] || die "Missing executable Docker harness: $harness"
  [ -x "$integration_helper" ] || die "Missing executable integration helper: $integration_helper"
  require_baseline
  output="$(run_harness_logged preflight-harness preflight)" || rc=$?
  rc="${rc:-0}"
  log="$(printf '%s\n' "$output" | sed -n 's/^exit=[0-9][0-9]* log=//p' | tail -1)"
  if [ "$rc" -ne 0 ]; then
    write_evidence preflight docker fail "docker-verify.sh preflight" "$log" "Shared Docker harness preflight failed" >/dev/null
    printf '%s\n' "$output"
    return "$rc"
  fi
  write_rendered_env
  evidence="$(write_evidence preflight docker pass "docker-verify.sh preflight" "$log" "Docker verifier inputs, harness, integration helper, generated paths, and Version Baseline are ready")"
  printf 'status=pass mode=%s rendered_env=%s evidence=%s log_dir=%s\n' \
    "$DOCKER_VERIFY_MODE" "$DOCKER_VERIFY_RENDERED_ENV" "$evidence" "$DOCKER_VERIFY_LOG_DIR"
}

cmd_render_config() {
  local evidence
  ensure_dirs
  require_baseline
  write_rendered_env
  run_harness_logged render-config-harness render-config
  evidence="$(write_evidence render-config docker pass "docker-verify.sh render-config" "not-applicable" "Rendered Docker simulation configuration and delegated harness configuration")"
  printf 'rendered_env=%s evidence=%s\n' "$DOCKER_VERIFY_RENDERED_ENV" "$evidence"
}

cmd_prepare_artifacts() {
  local role output log rc evidence
  ensure_dirs
  for role in "${roles[@]}"; do
    output="$(run_harness_logged "prepare-artifacts-$role" prepare-artifacts --role "$role")" || rc=$?
    rc="${rc:-0}"
    log="$(printf '%s\n' "$output" | sed -n 's/^exit=[0-9][0-9]* log=//p' | tail -1)"
    printf '%s\n' "$output"
    if [ "$rc" -ne 0 ]; then
      write_evidence prepare-artifacts "$role" fail "docker-verify.sh prepare-artifacts" "$log" "Harness artifact preparation failed for role" >/dev/null
      return "$rc"
    fi
    if ! assert_no_forbidden_success_markers "$log"; then
      evidence="$(write_evidence prepare-artifacts "$role" fail "docker-verify.sh prepare-artifacts" "$log" "Forbidden success marker found in role artifact preparation log")"
      printf 'exit=1 evidence=%s log=%s\n' "$evidence" "$log"
      return 1
    fi
    write_evidence prepare-artifacts "$role" pass "docker-verify.sh prepare-artifacts" "$log" "Bundle factory produced role artifacts, manifests, checksums, and simulation-only source labels" >/dev/null
    unset rc
  done
}

cmd_stage_artifacts() {
  local role output log rc evidence
  ensure_dirs
  for role in "${roles[@]}"; do
    output="$(run_harness_logged "stage-artifacts-$role" stage-artifacts --role "$role")" || rc=$?
    rc="${rc:-0}"
    log="$(printf '%s\n' "$output" | sed -n 's/^exit=[0-9][0-9]* log=//p' | tail -1)"
    printf '%s\n' "$output"
    if [ "$rc" -ne 0 ]; then
      write_evidence stage-artifacts "$role" fail "docker-verify.sh stage-artifacts" "$log" "Harness artifact staging failed for role" >/dev/null
      return "$rc"
    fi
    write_evidence stage-artifacts "$role" pass "docker-verify.sh stage-artifacts" "$log" "Role artifacts were staged and target-side manifests/checksums verified before mutation" >/dev/null
    unset rc
  done
}

cmd_up() {
  local output log rc evidence
  ensure_dirs
  output="$(run_harness_logged up-harness up)" || rc=$?
  rc="${rc:-0}"
  log="$(printf '%s\n' "$output" | sed -n 's/^exit=[0-9][0-9]* log=//p' | tail -1)"
  printf '%s\n' "$output"
  if [ "$rc" -ne 0 ]; then
    write_evidence up docker fail "docker-verify.sh up" "$log" "Shared Docker harness failed to start the five simulation environments" >/dev/null
    return "$rc"
  fi
  evidence="$(write_evidence up docker pass "docker-verify.sh up" "$log" "Started bundle factory, LDAP, Gerrit, Jenkins controller, and Jenkins agent containers through the shared harness")"
  printf 'evidence=%s\n' "$evidence"
}

cmd_check() {
  local role output log rc integration_log evidence
  ensure_dirs
  for role in "${roles[@]}"; do
    output="$(run_harness_logged "run-role-gate-$role" run-role-gate --role "$role")" || rc=$?
    rc="${rc:-0}"
    log="$(printf '%s\n' "$output" | sed -n 's/^exit=[0-9][0-9]* log=//p' | tail -1)"
    printf '%s\n' "$output"
    if [ "$rc" -ne 0 ]; then
      write_evidence check "$role" fail "docker-verify.sh check" "$log" "Role-local readiness gate failed before cross-role integration validation" >/dev/null
      return "$rc"
    fi
    if ! assert_no_forbidden_success_markers "$log"; then
      evidence="$(write_evidence check "$role" fail "docker-verify.sh check" "$log" "Forbidden success marker found in role readiness log")"
      printf 'exit=1 evidence=%s log=%s\n' "$evidence" "$log"
      return 1
    fi
    write_evidence check "$role" pass "docker-verify.sh check" "$log" "Role-local readiness passed with real service proof from shared harness" >/dev/null
    unset rc
  done

  integration_log="$(bounded_log_path configure-and-validate-integration)"
  {
    set -e
    "$integration_helper" "${integration_args[@]}" --yes configure-gerrit-ssh
    "$integration_helper" "${integration_args[@]}" --yes configure-agent-ssh
    "$integration_helper" "${integration_args[@]}" --yes configure-trigger
    "$integration_helper" "${integration_args[@]}" --yes validate-integration
  } >"$integration_log" 2>&1 || rc=$?
  rc="${rc:-0}"
  if [ "$rc" -eq 0 ]; then
    if ! assert_no_forbidden_success_markers "$integration_log"; then
      evidence="$(write_evidence check integration fail "docker-verify.sh check" "$integration_log" "Forbidden success marker found in integration validation log")"
      printf 'exit=1 evidence=%s log=%s\n' "$evidence" "$integration_log"
      return 1
    fi
    evidence="$(write_evidence check integration pass "docker-verify.sh check" "$integration_log" "Shared integration helper proved Jenkins-to-Gerrit SSH, stream-events, Jenkins-to-agent SSH, node readiness, and agent scheduling")"
    printf 'exit=0 log=%s evidence=%s\n' "$integration_log" "$evidence"
    return 0
  fi
  write_blocked_integration_evidence jenkins-to-gerrit-ssh "$integration_log" "Blocked: shared integration helper has not implemented real Jenkins-to-Gerrit SSH setup and validation"
  write_blocked_integration_evidence stream-events "$integration_log" "Blocked: shared integration helper has not implemented real Gerrit stream-events validation"
  write_blocked_integration_evidence agent-connection "$integration_log" "Blocked: shared integration helper has not implemented real Jenkins-to-agent SSH connection validation"
  write_blocked_integration_evidence scheduling "$integration_log" "Blocked: shared integration helper has not implemented real Jenkins agent scheduling validation"
  evidence="$(write_evidence check integration blocked "docker-verify.sh check" "$integration_log" "Shared integration helper reported blocked cross-role validation; Docker simulation cannot claim readiness")"
  printf 'exit=%s log=%s evidence=%s status=blocked\n' "$rc" "$integration_log" "$evidence"
  return "$rc"
}

cmd_full_verify() {
  local log rc evidence
  ensure_dirs
  cmd_check || rc=$?
  rc="${rc:-0}"
  if [ "$rc" -ne 0 ]; then
    log="$(bounded_log_path full-verify-blocked)"
    printf 'full_verify_blocked=check_failed_or_blocked\n' >"$log"
    write_blocked_integration_evidence job-execution "$log" "Blocked: readiness check did not prove real cross-role integration, so job execution was not attempted"
    write_blocked_integration_evidence verified-vote "$log" "Blocked: readiness check did not prove real cross-role integration, so Verified +1 was not attempted"
    evidence="$(write_evidence full-verify integration blocked "docker-verify.sh full-verify" "$log" "Full verification blocked before end-to-end trigger execution")"
    printf 'exit=%s log=%s evidence=%s status=blocked\n' "$rc" "$log" "$evidence"
    return "$rc"
  fi
  unset rc

  log="$(bounded_log_path verify-trigger)"
  "$integration_helper" "${integration_args[@]}" --yes verify-trigger >"$log" 2>&1 || rc=$?
  rc="${rc:-0}"
  if [ "$rc" -eq 0 ]; then
    if ! assert_no_forbidden_success_markers "$log"; then
      evidence="$(write_evidence full-verify integration fail "docker-verify.sh full-verify" "$log" "Forbidden success marker found in trigger verification log")"
      printf 'exit=1 evidence=%s log=%s\n' "$evidence" "$log"
      return 1
    fi
    evidence="$(write_evidence full-verify integration pass "docker-verify.sh full-verify" "$log" "Shared integration helper proved disposable change, Gerrit event receipt, Jenkins job scheduling, agent execution, and Verified +1")"
    printf 'exit=0 log=%s evidence=%s\n' "$log" "$evidence"
    return 0
  fi
  write_blocked_integration_evidence job-execution "$log" "Blocked: shared integration helper has not implemented real disposable Jenkins job execution proof"
  write_blocked_integration_evidence verified-vote "$log" "Blocked: shared integration helper has not implemented real Gerrit Verified +1 vote proof"
  evidence="$(write_evidence full-verify integration blocked "docker-verify.sh full-verify" "$log" "Shared integration helper reported blocked trigger verification; Docker simulation cannot claim end-to-end success")"
  printf 'exit=%s log=%s evidence=%s status=blocked\n' "$rc" "$log" "$evidence"
  return "$rc"
}

cmd_down() {
  local output log rc evidence
  ensure_dirs
  output="$(run_harness_logged down-harness down)" || rc=$?
  rc="${rc:-0}"
  log="$(printf '%s\n' "$output" | sed -n 's/^exit=[0-9][0-9]* log=//p' | tail -1)"
  printf '%s\n' "$output"
  if [ "$rc" -ne 0 ]; then
    write_evidence down docker fail "docker-verify.sh down" "$log" "Shared Docker harness down failed" >/dev/null
    return "$rc"
  fi
  evidence="$(write_evidence down docker pass "docker-verify.sh down" "$log" "Stopped Docker simulation containers without deleting retained evidence")"
  printf 'evidence=%s\n' "$evidence"
}

main() {
  local command_name
  command_name="${1:-}"
  case "$command_name" in
    -h|--help|help)
      usage
      ;;
    preflight)
      shift
      [ "$#" -eq 0 ] || die "preflight does not accept options"
      cmd_preflight
      ;;
    render-config)
      shift
      [ "$#" -eq 0 ] || die "render-config does not accept options"
      cmd_render_config
      ;;
    prepare-artifacts)
      shift
      [ "$#" -eq 0 ] || die "prepare-artifacts does not accept options"
      cmd_prepare_artifacts
      ;;
    stage-artifacts)
      shift
      [ "$#" -eq 0 ] || die "stage-artifacts does not accept options"
      cmd_stage_artifacts
      ;;
    up)
      shift
      [ "$#" -eq 0 ] || die "up does not accept options"
      cmd_up
      ;;
    check)
      shift
      [ "$#" -eq 0 ] || die "check does not accept options"
      cmd_check
      ;;
    full-verify)
      shift
      [ "$#" -eq 0 ] || die "full-verify does not accept options"
      cmd_full_verify
      ;;
    down)
      shift
      [ "$#" -eq 0 ] || die "down does not accept options"
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
