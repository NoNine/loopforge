#!/usr/bin/env bash

set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
repo_root="$(CDPATH= cd -- "$script_dir/../.." && pwd)"
harness_dir="$script_dir/harness"
compose_file="$harness_dir/compose.yaml"

usage() {
  cat <<'USAGE'
Usage:
  simulation/docker/docker-harness.sh <command> [options]

Commands:
  preflight
  render-config
  up
  prepare-artifacts --role <gerrit|jenkins-controller|jenkins-agent>
  stage-artifacts --role <gerrit|jenkins-controller|jenkins-agent>
  run-role-gate --role <gerrit|jenkins-controller|jenkins-agent>
  down

Options:
  --role ROLE       Role for role-scoped commands.
  -h, --help        Show this help.

The harness starts the five role-gate environments only. It is not the full
end-to-end Docker simulation.
USAGE
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
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

HARNESS_MODE="${HARNESS_MODE:-docker-harness-simulation}"
HARNESS_RUN_ID="${HARNESS_RUN_ID:-default}"
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

HARNESS_STATE_DIR="${HARNESS_STATE_DIR:-$repo_root/simulation/state/docker/harness/$HARNESS_RUN_ID}"
HARNESS_STAGING_DIR="${HARNESS_STAGING_DIR:-$repo_root/simulation/staging/docker/harness/$HARNESS_RUN_ID}"
HARNESS_EVIDENCE_DIR="${HARNESS_EVIDENCE_DIR:-$repo_root/simulation/evidence/docker/harness/$HARNESS_RUN_ID}"
HARNESS_LOG_DIR="${HARNESS_LOG_DIR:-$repo_root/logs/docker/harness/$HARNESS_RUN_ID}"
HARNESS_RENDERED_ENV="$HARNESS_STATE_DIR/rendered/harness.env"
HARNESS_BASELINE_CONTRACT="$HARNESS_STATE_DIR/rendered/artifact-manifest-contract.txt"

export HARNESS_MODE HARNESS_RUN_ID HARNESS_PROJECT_NAME
export HARNESS_UBUNTU_IMAGE HARNESS_LDAP_IMAGE
export HARNESS_LDAP_DOMAIN HARNESS_LDAP_BASE_DN
export HARNESS_LDAP_ADMIN_PASSWORD HARNESS_LDAP_CONFIG_PASSWORD
export HARNESS_LDAP_BIND_USER HARNESS_LDAP_BIND_PASSWORD
export HARNESS_STATE_DIR HARNESS_STAGING_DIR HARNESS_EVIDENCE_DIR HARNESS_LOG_DIR

compose_kind=""
compose_cmd=()

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

ensure_dirs() {
  validate_harness_inputs
  mkdir -p \
    "$HARNESS_STATE_DIR" \
    "$HARNESS_STAGING_DIR" \
    "$HARNESS_EVIDENCE_DIR" \
    "$HARNESS_LOG_DIR" \
    "$HARNESS_STATE_DIR/bundle-factory/artifacts" \
    "$HARNESS_STATE_DIR/rendered" \
    "$HARNESS_STAGING_DIR/gerrit" \
    "$HARNESS_STAGING_DIR/jenkins-controller" \
    "$HARNESS_STAGING_DIR/jenkins-agent"
}

bounded_log_path() {
  local name
  name="${1:?log name required}"
  printf '%s/%s-%s.log' "$HARNESS_LOG_DIR" "$name" "$(timestamp_utc)"
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

json_quote() {
  local value
  value="${1-}"
  require_command python3
  python3 -c 'import json, sys; print(json.dumps(sys.argv[1]))' "$value"
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
  ensure_dirs
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
  "mode_labels": ["docker-harness", "simulation-only"],
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
  validate_harness_inputs
  ensure_dirs
  cat >"$HARNESS_RENDERED_ENV" <<EOF
HARNESS_MODE=$HARNESS_MODE
HARNESS_RUN_ID=$HARNESS_RUN_ID
HARNESS_PROJECT_NAME=$HARNESS_PROJECT_NAME
HARNESS_UBUNTU_IMAGE=$HARNESS_UBUNTU_IMAGE
HARNESS_UBUNTU_BASELINE_VERSION=$HARNESS_UBUNTU_BASELINE_VERSION
HARNESS_UBUNTU_BASELINE_RELEASE=$HARNESS_UBUNTU_BASELINE_RELEASE
HARNESS_UBUNTU_BASELINE_CODENAME=$HARNESS_UBUNTU_BASELINE_CODENAME
HARNESS_JAVA_BASELINE=$HARNESS_JAVA_BASELINE
HARNESS_GERRIT_BASELINE=$HARNESS_GERRIT_BASELINE
HARNESS_JENKINS_BASELINE=$HARNESS_JENKINS_BASELINE
HARNESS_JENKINS_PLUGIN_MANAGER_BASELINE=$HARNESS_JENKINS_PLUGIN_MANAGER_BASELINE
HARNESS_LDAP_IMAGE=$HARNESS_LDAP_IMAGE
HARNESS_LDAP_DOMAIN=$HARNESS_LDAP_DOMAIN
HARNESS_LDAP_BASE_DN=$HARNESS_LDAP_BASE_DN
HARNESS_LDAP_ADMIN_PASSWORD=<redacted>
HARNESS_LDAP_CONFIG_PASSWORD=<redacted>
HARNESS_LDAP_BIND_USER=$HARNESS_LDAP_BIND_USER
HARNESS_LDAP_BIND_PASSWORD=<redacted>
HARNESS_PUBLIC_INTERNET_FALLBACK_LABEL=$HARNESS_PUBLIC_INTERNET_FALLBACK_LABEL
HARNESS_STATE_DIR=$HARNESS_STATE_DIR
HARNESS_STAGING_DIR=$HARNESS_STAGING_DIR
HARNESS_EVIDENCE_DIR=$HARNESS_EVIDENCE_DIR
HARNESS_LOG_DIR=$HARNESS_LOG_DIR
EOF
  write_manifest_contract
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

check_target_os_release() {
  local role service log os_release os_codename evidence
  role="${1:?role required}"
  service="$(service_for_role "$role")"
  log="$(bounded_log_path "os-release-$role")"

  if ! compose exec -T "$service" sh -c '. /etc/os-release && printf "%s %s\n" "$VERSION_ID" "$VERSION_CODENAME"' >"$log" 2>&1; then
    evidence="$(write_evidence os-release "$role" fail "docker-harness.sh run-role-gate" "$log" "Could not read target OS release")"
    die "Failed to read OS release for $role; evidence=$evidence log=$log"
  fi

  os_release="$(awk '{print $1}' "$log")"
  os_codename="$(awk '{print $2}' "$log")"
  if [ "$os_release" != "$HARNESS_UBUNTU_BASELINE_RELEASE" ] || [ "$os_codename" != "$HARNESS_UBUNTU_BASELINE_CODENAME" ]; then
    evidence="$(write_evidence os-release "$role" blocked "docker-harness.sh run-role-gate" "$log" "Target OS $os_release $os_codename does not match Version Baseline")"
    die "Target OS drift for $role; expected $HARNESS_UBUNTU_BASELINE_RELEASE $HARNESS_UBUNTU_BASELINE_CODENAME, evidence=$evidence log=$log"
  fi

  write_evidence os-release "$role" pass "docker-harness.sh run-role-gate" "$log" "Target OS release matches Version Baseline" >/dev/null
}

check_ubuntu_service_baseline() {
  local service label log os_release os_codename image_id evidence
  service="${1:?service required}"
  label="${2:?label required}"
  log="$(bounded_log_path "baseline-$label")"

  require_running_service "$service"
  if ! compose exec -T "$service" sh -c '. /etc/os-release && printf "release=%s codename=%s pretty=%s\n" "$VERSION_ID" "$VERSION_CODENAME" "$PRETTY_NAME"' >"$log" 2>&1; then
    evidence="$(write_evidence baseline "$label" fail "docker-harness.sh up" "$log" "Could not read container OS release")"
    die "Failed to read OS release for $label; evidence=$evidence log=$log"
  fi

  os_release="$(sed -n 's/^release=\([^ ]*\).*/\1/p' "$log")"
  os_codename="$(sed -n 's/^.*codename=\([^ ]*\).*/\1/p' "$log")"
  image_id="$(docker inspect -f '{{.Image}}' "$(container_id_for_service "$service")" 2>/dev/null || printf 'unknown')"
  printf 'image_id=%s\n' "$image_id" >>"$log"

  if [ "$os_release" != "$HARNESS_UBUNTU_BASELINE_RELEASE" ] || [ "$os_codename" != "$HARNESS_UBUNTU_BASELINE_CODENAME" ]; then
    evidence="$(write_evidence baseline "$label" blocked "docker-harness.sh up" "$log" "Container OS does not match Version Baseline")"
    die "Container OS drift for $label; expected $HARNESS_UBUNTU_BASELINE_RELEASE $HARNESS_UBUNTU_BASELINE_CODENAME, evidence=$evidence log=$log"
  fi

  write_evidence baseline "$label" pass "docker-harness.sh up" "$log" "Container OS release matches Version Baseline; resolved image id recorded" >/dev/null
}

cmd_preflight() {
  validate_harness_inputs
  ensure_dirs
  require_command docker
  require_command python3
  require_command sha256sum
  require_command tar
  require_command awk
  detect_compose
  require_baseline_label
  [ -f "$compose_file" ] || die "Missing Compose file: $compose_file"
  [ -f "$harness_dir/ldap/50-harness-seed.ldif" ] || die "Missing LDAP seed LDIF"
  [ -f "$harness_dir/scripts/harness-sleep.sh" ] || die "Missing harness container entrypoint"
  write_rendered_env
  write_evidence preflight harness pass "docker-harness.sh preflight" "not-applicable" "Compose provider: $compose_kind; generated output paths are ignored local state" >/dev/null
  printf 'status=pass mode=%s compose=%s rendered_env=%s evidence_dir=%s log_dir=%s\n' \
    "$HARNESS_MODE" "$compose_kind" "$HARNESS_RENDERED_ENV" "$HARNESS_EVIDENCE_DIR" "$HARNESS_LOG_DIR"
}

cmd_render_config() {
  validate_harness_inputs
  ensure_dirs
  require_baseline_label
  write_rendered_env
  write_evidence render-config harness pass "docker-harness.sh render-config" "not-applicable" "Rendered redacted harness configuration with Version Baseline values" >/dev/null
  printf 'rendered_env=%s evidence_dir=%s\n' "$HARNESS_RENDERED_ENV" "$HARNESS_EVIDENCE_DIR"
}

cmd_up() {
  local log rc evidence
  cmd_preflight >/dev/null
  log="$(bounded_log_path up)"
  if compose up -d >"$log" 2>&1; then
    rc=0
  else
    rc=$?
  fi
  if [ "$rc" -ne 0 ]; then
    evidence="$(write_evidence up harness fail "docker-harness.sh up" "$log" "Compose up failed")"
    printf 'exit=%s log=%s evidence=%s\n' "$rc" "$log" "$evidence"
    return "$rc"
  fi
  check_ubuntu_service_baseline bundle-factory bundle-factory
  check_ubuntu_service_baseline gerrit-target gerrit
  check_ubuntu_service_baseline jenkins-controller-target jenkins-controller
  check_ubuntu_service_baseline jenkins-agent-target jenkins-agent
  require_running_service ldap
  evidence="$(write_evidence up harness pass "docker-harness.sh up" "$log" "Started bundle factory, LDAP, Gerrit target, Jenkins controller target, and Jenkins agent target")"
  printf 'exit=0 log=%s evidence=%s\n' "$log" "$evidence"
}

role_helper_present_in_container() {
  local service helper
  service="${1:?service required}"
  helper="${2:?helper required}"
  compose exec -T "$service" test -x "/workspace/$helper" >/dev/null 2>&1
}

cmd_prepare_artifacts() {
  local role helper service log rc evidence artifact_dir
  role="$(parse_role "$@")"
  helper="$(helper_for_role "$role")"
  service="bundle-factory"
  require_running_service "$service"

  # Guard the boundary-first model: artifact preparation runs only in the
  # bundle factory, never in target containers.
  require_running_service "$(service_for_role "$role")"
  if compose exec -T "$(service_for_role "$role")" env | grep -q '^HARNESS_ENVIRONMENT=bundle-factory$'; then
    die "Refusing prepare-artifacts: selected target container is incorrectly marked as bundle factory"
  fi

  log="$(bounded_log_path "prepare-artifacts-$role")"
  if ! role_helper_present_in_container "$service" "$helper"; then
    evidence="$(write_evidence prepare-artifacts "$role" blocked "docker-harness.sh prepare-artifacts" "$log" "Missing executable role helper /workspace/$helper in bundle factory")"
    printf 'ERROR: Missing role helper for %s in bundle factory: /workspace/%s\n' "$role" "$helper" >"$log"
    printf 'exit=1 log=%s evidence=%s\n' "$log" "$evidence" >&2
    return 1
  fi

  if compose exec -T "$service" "/workspace/$helper" prepare-artifacts >"$log" 2>&1; then
    rc=0
  else
    rc=$?
  fi
  if [ "$rc" -ne 0 ]; then
    if grep -Eq "is not implemented in this repository step|is a placeholder" "$log"; then
      evidence="$(write_evidence prepare-artifacts "$role" blocked "docker-harness.sh prepare-artifacts" "$log" "Role helper exists but prepare-artifacts is not implemented yet")"
      printf 'ERROR: Role helper for %s exists but prepare-artifacts is not implemented yet\n' "$role" >&2
    else
      evidence="$(write_evidence prepare-artifacts "$role" fail "docker-harness.sh prepare-artifacts" "$log" "Role helper prepare-artifacts failed in bundle factory")"
    fi
    printf 'exit=%s log=%s evidence=%s\n' "$rc" "$log" "$evidence"
    return "$rc"
  fi

  artifact_dir="$HARNESS_STATE_DIR/bundle-factory/artifacts/$role"
  if [ ! -f "$artifact_dir/manifest.txt" ] || [ ! -f "$artifact_dir/checksums.sha256" ]; then
    evidence="$(write_evidence prepare-artifacts "$role" fail "docker-harness.sh prepare-artifacts" "$log" "Role helper did not produce manifest.txt and checksums.sha256")"
    printf 'exit=1 log=%s evidence=%s\n' "$log" "$evidence"
    return 1
  fi

  if ! validate_role_baseline_manifest "$role" "$artifact_dir/manifest.txt" "$log"; then
    evidence="$(write_evidence prepare-artifacts "$role" blocked "docker-harness.sh prepare-artifacts" "$log" "Artifact manifest baseline metadata is missing or drifted; comparable readiness is blocked")"
    printf 'ERROR: Artifact baseline metadata for %s is missing or drifted; log=%s evidence=%s\n' "$role" "$log" "$evidence" >&2
    return 1
  fi

  evidence="$(write_evidence prepare-artifacts "$role" pass "docker-harness.sh prepare-artifacts" "$log" "Role artifacts produced in bundle factory with manifest and checksums")"
  printf 'exit=0 log=%s evidence=%s\n' "$log" "$evidence"
}

cmd_stage_artifacts() {
  local role service artifact_dir stage_dir log rc evidence
  role="$(parse_role "$@")"
  service="$(service_for_role "$role")"
  artifact_dir="$HARNESS_STATE_DIR/bundle-factory/artifacts/$role"
  stage_dir="$HARNESS_STAGING_DIR/$role"
  log="$(bounded_log_path "stage-artifacts-$role")"

  require_running_service "$service"
  [ -f "$artifact_dir/manifest.txt" ] || die "Missing bundle factory manifest for $role: $artifact_dir/manifest.txt"
  [ -f "$artifact_dir/checksums.sha256" ] || die "Missing bundle factory checksums for $role: $artifact_dir/checksums.sha256"

  : >"$log"
  if ! validate_role_baseline_manifest "$role" "$artifact_dir/manifest.txt" "$log"; then
    evidence="$(write_evidence stage-artifacts "$role" blocked "docker-harness.sh stage-artifacts" "$log" "Bundle factory manifest baseline metadata is missing or drifted; staging cannot report comparable readiness")"
    printf 'ERROR: Bundle factory baseline metadata for %s is missing or drifted; log=%s evidence=%s\n' "$role" "$log" "$evidence" >&2
    return 1
  fi

  mkdir -p "$stage_dir"
  rm -rf "$stage_dir"/* "$stage_dir"/.[!.]* "$stage_dir"/..?*
  if tar -C "$artifact_dir" -cf - . | tar -C "$stage_dir" -xf - >>"$log" 2>&1; then
    rc=0
  else
    rc=$?
  fi
  if [ "$rc" -ne 0 ]; then
    evidence="$(write_evidence stage-artifacts "$role" fail "docker-harness.sh stage-artifacts" "$log" "Failed to copy artifacts to target staging path")"
    printf 'exit=%s log=%s evidence=%s\n' "$rc" "$log" "$evidence"
    return "$rc"
  fi

  if (cd "$stage_dir" && sha256sum -c checksums.sha256) >>"$log" 2>&1; then
    rc=0
  else
    rc=$?
  fi
  if [ "$rc" -ne 0 ]; then
    evidence="$(write_evidence stage-artifacts "$role" fail "docker-harness.sh stage-artifacts" "$log" "Target-side checksum verification failed")"
    printf 'exit=%s log=%s evidence=%s\n' "$rc" "$log" "$evidence"
    return "$rc"
  fi

  if ! validate_role_baseline_manifest "$role" "$stage_dir/manifest.txt" "$log"; then
    evidence="$(write_evidence stage-artifacts "$role" blocked "docker-harness.sh stage-artifacts" "$log" "Target staged manifest baseline metadata is missing or drifted; comparable readiness is blocked")"
    printf 'ERROR: Target staged baseline metadata for %s is missing or drifted; log=%s evidence=%s\n' "$role" "$log" "$evidence" >&2
    return 1
  fi

  if ! compose exec -T "$service" sh -c 'test -f /harness/staged/manifest.txt && test -f /harness/staged/checksums.sha256 && cd /harness/staged && sha256sum -c checksums.sha256' >>"$log" 2>&1; then
    evidence="$(write_evidence stage-artifacts "$role" fail "docker-harness.sh stage-artifacts" "$log" "Container target-side manifest/checksum verification failed")"
    printf 'exit=1 log=%s evidence=%s\n' "$log" "$evidence"
    return 1
  fi

  evidence="$(write_evidence stage-artifacts "$role" pass "docker-harness.sh stage-artifacts" "$log" "Artifacts staged to target and verified by manifest/checksum before mutation")"
  printf 'exit=0 log=%s evidence=%s\n' "$log" "$evidence"
}

assert_no_placeholder_success() {
  local log
  log="${1:?log required}"
  if grep -Eiq "dummy success|operation-plan-only|planned-checks-only|modeled|placeholder success|would validate|would run" "$log"; then
    return 1
  fi
  return 0
}

cmd_run_role_gate() {
  local role helper service log rc evidence
  role="$(parse_role "$@")"
  helper="$(helper_for_role "$role")"
  service="$(service_for_role "$role")"
  require_running_service "$service"
  check_target_os_release "$role"

  log="$(bounded_log_path "run-role-gate-$role")"
  : >"$log"
  if ! role_helper_present_in_container "$service" "$helper"; then
    evidence="$(write_evidence run-role-gate "$role" blocked "docker-harness.sh run-role-gate" "$log" "Missing executable role helper /workspace/$helper in target container")"
    printf 'ERROR: Missing role helper for %s in target container: /workspace/%s\n' "$role" "$helper" >>"$log"
    printf 'exit=1 log=%s evidence=%s\n' "$log" "$evidence" >&2
    return 1
  fi

  if compose exec -T "$service" "/workspace/$helper" validate >>"$log" 2>&1; then
    rc=0
  else
    rc=$?
  fi

  if [ "$rc" -eq 0 ]; then
    if ! validate_role_baseline_manifest "$role" "$HARNESS_STAGING_DIR/$role/manifest.txt" "$log"; then
      evidence="$(write_evidence run-role-gate "$role" blocked "docker-harness.sh run-role-gate" "$log" "Staged artifact baseline metadata is missing or drifted; role readiness cannot be comparable")"
      printf 'ERROR: Staged artifact baseline metadata for %s is missing or drifted; log=%s evidence=%s\n' "$role" "$log" "$evidence" >&2
      return 1
    fi

    if ! assert_no_placeholder_success "$log"; then
      evidence="$(write_evidence run-role-gate "$role" fail "docker-harness.sh run-role-gate" "$log" "Role gate produced dummy, placeholder, operation-plan-only, planned-checks-only, or modeled success")"
      printf 'exit=1 log=%s evidence=%s\n' "$log" "$evidence"
      return 1
    fi
    evidence="$(write_evidence run-role-gate "$role" pass "docker-harness.sh run-role-gate" "$log" "Role helper validated required real behavior without placeholder success markers")"
    printf 'exit=0 log=%s evidence=%s\n' "$log" "$evidence"
    return 0
  fi

  if grep -Eq "is not implemented in this repository step|is a placeholder" "$log"; then
    evidence="$(write_evidence run-role-gate "$role" blocked "docker-harness.sh run-role-gate" "$log" "Role helper exists but validate is not implemented yet")"
    printf 'ERROR: Role helper for %s exists but validate is not implemented yet\n' "$role" >&2
  else
    evidence="$(write_evidence run-role-gate "$role" fail "docker-harness.sh run-role-gate" "$log" "Role helper validate failed; readiness is not proven")"
  fi
  printf 'exit=%s log=%s evidence=%s\n' "$rc" "$log" "$evidence"
  return "$rc"
}

cmd_down() {
  local log rc evidence
  validate_harness_inputs
  ensure_dirs
  detect_compose
  log="$(bounded_log_path down)"
  if compose down >"$log" 2>&1; then
    rc=0
  else
    rc=$?
  fi
  if [ "$rc" -ne 0 ]; then
    evidence="$(write_evidence down harness fail "docker-harness.sh down" "$log" "Compose down failed")"
    printf 'exit=%s log=%s evidence=%s\n' "$rc" "$log" "$evidence"
    return "$rc"
  fi
  evidence="$(write_evidence down harness pass "docker-harness.sh down" "$log" "Stopped harness containers without deleting retained evidence")"
  printf 'exit=0 log=%s evidence=%s\n' "$log" "$evidence"
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
    up)
      shift
      [ "$#" -eq 0 ] || die "up does not accept options"
      cmd_up
      ;;
    prepare-artifacts)
      shift
      cmd_prepare_artifacts "$@"
      ;;
    stage-artifacts)
      shift
      cmd_stage_artifacts "$@"
      ;;
    run-role-gate)
      shift
      cmd_run_role_gate "$@"
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
