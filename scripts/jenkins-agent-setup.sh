#!/usr/bin/env bash

set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
repo_root="$(CDPATH= cd -- "$script_dir/.." && pwd)"
# shellcheck source=common.sh
. "$script_dir/common.sh"

role="jenkins-agent"
default_env_file="$repo_root/examples/jenkins-agent.env.example"
env_file=""
dry_run=0
assume_yes=0
readonly JENKINS_AGENT_NATIVE_REMOTE_FS="/var/lib/jenkins-agent"
readonly JENKINS_AGENT_BUNDLE_FACTORY_WORK_DIR="/var/lib/loopforge/preparing/jenkins-agent-artifacts-bundle/jenkins-agent"
readonly JENKINS_AGENT_STAGED_BUNDLE_PAYLOAD_DIR="/var/lib/loopforge/staging/jenkins-agent-artifacts-bundle/jenkins-agent"
readonly JENKINS_AGENT_ARTIFACT_BUNDLE_NAME="jenkins-agent-artifacts-bundle"

usage() {
  cat <<'USAGE'
Usage:
  scripts/jenkins-agent-setup.sh [--env FILE] [--dry-run] [--yes] <command>

Commands:
  print-env-template
  preflight
  prepare-artifacts
  prepare-target-workspace
  install
  configure-runtime
  validate
  collect-evidence

Options:
  --env FILE     Source reviewed Jenkins agent env values from FILE.
  --dry-run      Check inputs and describe non-mutating results only.
  --yes          Confirm mutating commands after env review.
  -h, --help     Show this help.

The manual remains the authority. This helper configures only the Jenkins
agent host runtime account, remote filesystem, and real SSH daemon readiness.
Jenkins controller node registration, keypair generation, authorized-key
handoff, and executor scheduling stay with later integration work.
USAGE
}

die_usage() {
  printf 'ERROR: %s\n' "$*" >&2
  usage >&2
  exit 1
}

timestamp_utc() {
  date -u +%Y%m%dT%H%M%SZ
}

iso_timestamp_utc() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

json_quote() {
  local value i ch out
  value="${1-}"
  out='"'
  i=0
  while [ "$i" -lt "${#value}" ]; do
    ch="${value:$i:1}"
    case "$ch" in
      '"') out="$out\\\"" ;;
      "\\") out="$out\\\\" ;;
      $'\n') out="$out\\n" ;;
      $'\r') out="$out\\r" ;;
      $'\t') out="$out\\t" ;;
      *) out="$out$ch" ;;
    esac
    i=$((i + 1))
  done
  out="$out\""
  printf '%s\n' "$out"
}

shell_quote() {
  printf '%q' "${1:?value required}"
}

sha256_file() {
  local file
  file="${1:?file required}"
  sha256sum "$file" | awk '{print $1}'
}

load_env_file() {
  local file
  file="${env_file:-$default_env_file}"
  [ -f "$file" ] || die "Missing env file: $file"
  set -a
  # shellcheck disable=SC1090
  . "$file"
  set +a
}

value_or_default() {
  local var_name default_value
  var_name="${1:?var name required}"
  default_value="${2:-}"
  eval "printf '%s' \"\${$var_name:-$default_value}\""
}

is_placeholder() {
  case "${1:-}" in
    ""|"<"*">"|"{{"*"}}"|"CHANGE-ME"*|"change-me"*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

require_reviewed_value() {
  local name value
  name="${1:?name required}"
  value="$(value_or_default "$name" "")"
  if is_placeholder "$value"; then
    die "Env value $name must be reviewed and must not be a placeholder"
  fi
}

require_env_values() {
  local required name
  required="
JENKINS_AGENT_UBUNTU_RELEASE
JENKINS_AGENT_UBUNTU_CODENAME
JENKINS_AGENT_JAVA_VERSION
JENKINS_AGENT_HOST
JENKINS_AGENT_SSH_PORT
JENKINS_AGENT_ACCOUNT
JENKINS_AGENT_GROUP
LOOPFORGE_OPERATOR_ACCOUNT
LOOPFORGE_OPERATOR_GROUP
JENKINS_AGENT_REMOTE_FS
JENKINS_AGENT_NODE_NAME
JENKINS_AGENT_LABELS
JENKINS_AGENT_EXECUTORS
JENKINS_AGENT_CREDENTIAL_ID
JENKINS_AGENT_STATE_DIR
JENKINS_AGENT_STAGED_ARTIFACT_DIR
JENKINS_AGENT_ARTIFACT_OUTPUT_DIR
JENKINS_AGENT_EVIDENCE_DIR
JENKINS_AGENT_LOG_DIR
JENKINS_AGENT_VERIFICATION_MODE
JENKINS_AGENT_OS_DEPENDENCIES
JENKINS_AGENT_CONTROLLER_PLUGIN
JENKINS_AGENT_CONTROLLER_PLUGIN_SOURCE
JENKINS_AGENT_EXECUTOR_CONTEXT
"
  for name in $required; do
    if [ "$dry_run" -eq 1 ]; then
      [ -n "$(value_or_default "$name" "")" ] || die "Missing env value $name"
    else
      require_reviewed_value "$name"
    fi
  done
}

apply_env_defaults() {
  JENKINS_AGENT_UBUNTU_RELEASE="${JENKINS_AGENT_UBUNTU_RELEASE:-24.04}"
  JENKINS_AGENT_UBUNTU_CODENAME="${JENKINS_AGENT_UBUNTU_CODENAME:-noble}"
  JENKINS_AGENT_JAVA_VERSION="${JENKINS_AGENT_JAVA_VERSION:-21}"
  JENKINS_AGENT_HOST="${JENKINS_AGENT_HOST:-jenkins-agent-target}"
  JENKINS_AGENT_SSH_PORT="${JENKINS_AGENT_SSH_PORT:-22}"
  JENKINS_AGENT_ACCOUNT="${JENKINS_AGENT_ACCOUNT:-jenkins-agent}"
  JENKINS_AGENT_GROUP="${JENKINS_AGENT_GROUP:-jenkins-agent}"
  LOOPFORGE_OPERATOR_ACCOUNT="${LOOPFORGE_OPERATOR_ACCOUNT:-ci-operator}"
  LOOPFORGE_OPERATOR_GROUP="${LOOPFORGE_OPERATOR_GROUP:-$LOOPFORGE_OPERATOR_ACCOUNT}"
  JENKINS_AGENT_REMOTE_FS="${JENKINS_AGENT_REMOTE_FS:-$JENKINS_AGENT_NATIVE_REMOTE_FS}"
  JENKINS_AGENT_NODE_NAME="${JENKINS_AGENT_NODE_NAME:-build-linux-x86-01}"
  JENKINS_AGENT_LABELS="${JENKINS_AGENT_LABELS:-linux x86_64 general-build gerrit-ci}"
  JENKINS_AGENT_EXECUTORS="${JENKINS_AGENT_EXECUTORS:-5}"
  JENKINS_AGENT_CREDENTIAL_ID="${JENKINS_AGENT_CREDENTIAL_ID:-jenkins-agent-ssh}"
  JENKINS_AGENT_STATE_DIR="${JENKINS_AGENT_STATE_DIR:-$JENKINS_AGENT_NATIVE_REMOTE_FS}"
  JENKINS_AGENT_STAGED_ARTIFACT_DIR="${JENKINS_AGENT_STAGED_ARTIFACT_DIR:-$JENKINS_AGENT_STAGED_BUNDLE_PAYLOAD_DIR}"
  JENKINS_AGENT_ARTIFACT_OUTPUT_DIR="${JENKINS_AGENT_ARTIFACT_OUTPUT_DIR:-$JENKINS_AGENT_BUNDLE_FACTORY_WORK_DIR}"
  JENKINS_AGENT_EVIDENCE_DIR="${JENKINS_AGENT_EVIDENCE_DIR:-/var/lib/loopforge/evidence}"
  JENKINS_AGENT_LOG_DIR="${JENKINS_AGENT_LOG_DIR:-/var/log/loopforge}"
  JENKINS_AGENT_VERIFICATION_MODE="${JENKINS_AGENT_VERIFICATION_MODE:-docker-simulation}"
  JENKINS_AGENT_OS_DEPENDENCIES="${JENKINS_AGENT_OS_DEPENDENCIES:-ca-certificates,curl,git,openssh-server,openjdk-21-jre,rsync,tar,unzip,wget}"
  JENKINS_AGENT_CONTROLLER_PLUGIN="${JENKINS_AGENT_CONTROLLER_PLUGIN:-ssh-slaves}"
  JENKINS_AGENT_CONTROLLER_PLUGIN_SOURCE="${JENKINS_AGENT_CONTROLLER_PLUGIN_SOURCE:-jenkins-controller-plugin-bundle}"
  JENKINS_AGENT_EXECUTOR_CONTEXT="${JENKINS_AGENT_EXECUTOR_CONTEXT:-controller-owned}"
}

load_env() {
  if [ "$1" = "template-only" ]; then
    return 0
  fi
  load_env_file
  apply_env_defaults
}

print_env_template() {
  cat "$default_env_file"
}

ensure_dirs() {
  prepare_loopforge_helper_dirs "$JENKINS_AGENT_EVIDENCE_DIR" "$JENKINS_AGENT_LOG_DIR"
  prepare_agent_state_dirs
}

prepare_loopforge_helper_dirs() {
  local command path
  command="install -d -m 0750 -o $(shell_quote "$LOOPFORGE_OPERATOR_ACCOUNT") -g $(shell_quote "$LOOPFORGE_OPERATOR_GROUP")"
  for path in "$@"; do
    command="$command $(shell_quote "$path")"
  done
  run_with_privilege "$command"
}

cmd_prepare_target_workspace() {
  load_env normal
  confirm_mutation prepare-target-workspace || return 0
  prepare_loopforge_helper_dirs /var/lib/loopforge /var/log/loopforge /var/lib/loopforge/staging "$JENKINS_AGENT_EVIDENCE_DIR" "$JENKINS_AGENT_LOG_DIR"
  printf 'status=pass command=prepare-target-workspace state_root=/var/lib/loopforge log_root=/var/log/loopforge\n'
}

for_each_csv_value() {
  local csv callback label old_ifs item
  local -a values
  csv="${1:?csv required}"
  callback="${2:?callback required}"
  label="${3:?label required}"
  case "$csv" in
    ""|,*|*,|*,,*)
      die "$label contains an empty entry"
      ;;
  esac
  old_ifs="$IFS"
  IFS=,
  read -r -a values <<<"$csv"
  IFS="$old_ifs"
  [ "${#values[@]}" -gt 0 ] || die "$label must include at least one entry"
  for item in "${values[@]}"; do
    [ -n "$item" ] || die "$label contains an empty entry"
    "$callback" "$item"
  done
}

require_docker_simulation() {
  [ "${HARNESS_MODE:-}" = "docker-simulation" ] ||
    die "Target-local SSH readiness is supported only in Docker simulation mode"
  [ "${HARNESS_ENVIRONMENT:-}" = "jenkins-agent-target" ] ||
    die "Target-local SSH readiness is supported only in the Jenkins agent Docker harness target"
  [ "$JENKINS_AGENT_VERIFICATION_MODE" = "docker-simulation" ] ||
    die "JENKINS_AGENT_VERIFICATION_MODE must be docker-simulation for agent readiness validation"
}

is_docker_simulation() {
  [ "${HARNESS_MODE:-}" = "docker-simulation" ] &&
    [ "${HARNESS_ENVIRONMENT:-}" = "jenkins-agent-target" ] &&
    [ "$JENKINS_AGENT_VERIFICATION_MODE" = "docker-simulation" ]
}

reject_control_chars() {
  local name value
  name="${1:?name required}"
  value="${2-}"
  case "$value" in
    *[$'\001'-$'\037'$'\177']*)
      die "$name must not contain newline or control characters"
      ;;
  esac
}

validate_agent_account_name() {
  local value
  value="${JENKINS_AGENT_ACCOUNT:-}"
  reject_control_chars JENKINS_AGENT_ACCOUNT "$value"
  case "$value" in
    ""|*[!a-z_0-9-]*)
      die "JENKINS_AGENT_ACCOUNT must be a local account name using lowercase letters, digits, underscore, or dash"
      ;;
  esac
  case "$value" in
    -*|[0-9]*|root|daemon|bin|sys|sync|games|man|lp|mail|news|uucp|proxy|www-data|backup|list|irc|_apt|nobody|systemd-*)
      die "JENKINS_AGENT_ACCOUNT is not allowed for the agent runtime account: $value"
      ;;
  esac
  [ "${#value}" -le 32 ] || die "JENKINS_AGENT_ACCOUNT must be 32 characters or fewer"
}

validate_agent_group_name() {
  local value
  value="${JENKINS_AGENT_GROUP:-}"
  reject_control_chars JENKINS_AGENT_GROUP "$value"
  case "$value" in
    ""|*[!a-z_0-9-]*)
      die "JENKINS_AGENT_GROUP must be a local group name using lowercase letters, digits, underscore, or dash"
      ;;
  esac
  case "$value" in
    -*|[0-9]*|root|daemon|bin|sys|sync|games|man|lp|mail|news|uucp|proxy|www-data|backup|list|irc|_apt|nobody|systemd-*)
      die "JENKINS_AGENT_GROUP is not allowed for the agent runtime group: $value"
      ;;
  esac
  [ "${#value}" -le 32 ] || die "JENKINS_AGENT_GROUP must be 32 characters or fewer"
}

validate_agent_ssh_port() {
  local value
  value="${JENKINS_AGENT_SSH_PORT:-}"
  reject_control_chars JENKINS_AGENT_SSH_PORT "$value"
  case "$value" in
    ""|*[!0-9]*)
      die "JENKINS_AGENT_SSH_PORT must be numeric"
      ;;
  esac
  [ "$value" -ge 1 ] && [ "$value" -le 65535 ] ||
    die "JENKINS_AGENT_SSH_PORT must be between 1 and 65535"
}

validate_safe_absolute_path_string() {
  local name value
  name="${1:?name required}"
  value="${2:-}"
  reject_control_chars "$name" "$value"
  [ -n "$value" ] || die "$name must not be empty"
  case "$value" in
    /*) ;;
    *) die "$name must be an absolute path: $value" ;;
  esac
  case "$value" in
    *[!A-Za-z0-9_./-]*)
      die "$name contains whitespace or sshd-config-significant unsafe characters: $value"
      ;;
  esac
  case "$value" in
    *"/../"*|*"/.."|"../"*|".."|*"//"*|*"/./"*|*"/.")
      die "$name contains unsafe path traversal or repeated slash: $value"
      ;;
  esac
}

validate_agent_state_dir() {
  local value
  value="${JENKINS_AGENT_STATE_DIR:-}"
  validate_safe_absolute_path_string JENKINS_AGENT_STATE_DIR "$value"
  case "$value" in
    "$JENKINS_AGENT_NATIVE_REMOTE_FS"|"$JENKINS_AGENT_NATIVE_REMOTE_FS"/*)
      ;;
    *)
      die "JENKINS_AGENT_STATE_DIR must be under $JENKINS_AGENT_NATIVE_REMOTE_FS"
      ;;
  esac
}

validate_agent_remote_fs() {
  local value
  value="${JENKINS_AGENT_REMOTE_FS:-}"
  validate_safe_absolute_path_string JENKINS_AGENT_REMOTE_FS "$value"
  case "$value" in
    "$JENKINS_AGENT_NATIVE_REMOTE_FS")
      ;;
    *)
      die "JENKINS_AGENT_REMOTE_FS must be $JENKINS_AGENT_NATIVE_REMOTE_FS, got $value"
      ;;
  esac
  case "$value" in
    /|/etc|/etc/*|/usr|/usr/*|/var|/var/*|/tmp|/tmp/*|/root|/root/*|/home|/home/*)
      case "$value" in
        "$JENKINS_AGENT_NATIVE_REMOTE_FS")
          ;;
        *)
          die "JENKINS_AGENT_REMOTE_FS is too broad or unsafe: $value"
          ;;
      esac
      ;;
  esac
}

validate_agent_render_inputs() {
  local label
  reject_control_chars JENKINS_AGENT_HOST "${JENKINS_AGENT_HOST:-}"
  reject_control_chars JENKINS_AGENT_NODE_NAME "${JENKINS_AGENT_NODE_NAME:-}"
  reject_control_chars JENKINS_AGENT_LABELS "${JENKINS_AGENT_LABELS:-}"
  reject_control_chars JENKINS_AGENT_CREDENTIAL_ID "${JENKINS_AGENT_CREDENTIAL_ID:-}"
  reject_control_chars JENKINS_AGENT_CONTROLLER_PLUGIN "${JENKINS_AGENT_CONTROLLER_PLUGIN:-}"
  reject_control_chars JENKINS_AGENT_CONTROLLER_PLUGIN_SOURCE "${JENKINS_AGENT_CONTROLLER_PLUGIN_SOURCE:-}"
  reject_control_chars JENKINS_AGENT_EXECUTOR_CONTEXT "${JENKINS_AGENT_EXECUTOR_CONTEXT:-}"
  validate_agent_account_name
  validate_agent_group_name
  validate_agent_ssh_port
  validate_agent_state_dir
  validate_agent_remote_fs
  case "$JENKINS_AGENT_NODE_NAME" in
    ""|*[!A-Za-z0-9_.-]*|.*|*-|*.)
      die "JENKINS_AGENT_NODE_NAME must use letters, digits, underscore, dot, or dash"
      ;;
  esac
  case " $JENKINS_AGENT_LABELS " in
    *"  "*)
      die "JENKINS_AGENT_LABELS must be a space-separated list without empty labels"
      ;;
  esac
  [ -n "$JENKINS_AGENT_LABELS" ] || die "JENKINS_AGENT_LABELS must not be empty"
  for label in $JENKINS_AGENT_LABELS; do
    case "$label" in
      ""|*[!A-Za-z0-9_.-]*)
        die "JENKINS_AGENT_LABELS must contain space-separated Jenkins labels using letters, digits, underscore, dot, or dash"
        ;;
    esac
  done
  case "$JENKINS_AGENT_EXECUTORS" in
    ""|*[!0-9]*)
      die "JENKINS_AGENT_EXECUTORS must be numeric"
      ;;
  esac
  [ "$JENKINS_AGENT_EXECUTORS" -ge 1 ] && [ "$JENKINS_AGENT_EXECUTORS" -le 100 ] ||
    die "JENKINS_AGENT_EXECUTORS must be between 1 and 100"
  case "$JENKINS_AGENT_CREDENTIAL_ID" in
    ""|*[!A-Za-z0-9_.-]*)
      die "JENKINS_AGENT_CREDENTIAL_ID must use letters, digits, underscore, dot, or dash"
      ;;
  esac
}

confirm_mutation() {
  local command_name
  command_name="${1:?command required}"
  if [ "$dry_run" -eq 1 ]; then
    printf 'dry_run=1 command=%s mutation=skipped\n' "$command_name"
    return 1
  fi
  if [ "$assume_yes" -eq 1 ]; then
    return 0
  fi
  die "$command_name mutates Jenkins agent target state; rerun with --yes after reviewing the env file"
}

write_text_file() {
  local target content
  target="${1:?target required}"
  content="${2:?content required}"
  mkdir -p "$(dirname "$target")"
  printf '%s\n' "$content" >"$target"
}

run_with_privilege() {
  local command
  command="${1:?command required}"
  if [ "$(id -u)" -eq 0 ]; then
    sh -c "$command"
  elif command -v sudo >/dev/null 2>&1; then
    sudo -n sh -c "$command"
  else
    die "Missing root or passwordless sudo for Jenkins agent privileged operation"
  fi
}

prepare_agent_state_dirs() {
  run_with_privilege "install -d -m 0755 -o $(shell_quote "$JENKINS_AGENT_ACCOUNT") -g $(shell_quote "$JENKINS_AGENT_GROUP") $(shell_quote "$JENKINS_AGENT_STATE_DIR") $(shell_quote "$JENKINS_AGENT_STATE_DIR/bootstrap") $(shell_quote "$JENKINS_AGENT_STATE_DIR/templates") $(shell_quote "$JENKINS_AGENT_STATE_DIR/state")"
}

reset_agent_state_for_install() {
  run_with_privilege "rm -rf -- $(shell_quote "$JENKINS_AGENT_STATE_DIR/bootstrap") $(shell_quote "$JENKINS_AGENT_STATE_DIR/templates") $(shell_quote "$JENKINS_AGENT_STATE_DIR/state") $(shell_quote "$JENKINS_AGENT_STATE_DIR/etc") $(shell_quote "$JENKINS_AGENT_STATE_DIR/run") $(shell_quote "$JENKINS_AGENT_STATE_DIR/logs") $(shell_quote "$JENKINS_AGENT_STATE_DIR/artifact-manifest.txt") $(shell_quote "$JENKINS_AGENT_STATE_DIR/artifact-checksums.sha256")"
  prepare_agent_state_dirs
}

prepare_agent_remote_fs() {
  run_with_privilege "install -d -m 0755 -o $(shell_quote "$JENKINS_AGENT_ACCOUNT") -g $(shell_quote "$JENKINS_AGENT_GROUP") $(shell_quote "$JENKINS_AGENT_REMOTE_FS") && chown -R $(shell_quote "$JENKINS_AGENT_ACCOUNT:$JENKINS_AGENT_GROUP") $(shell_quote "$JENKINS_AGENT_REMOTE_FS")"
}

install_file_as_agent() {
  local source target mode target_dir
  source="${1:?source required}"
  target="${2:?target required}"
  mode="${3:?mode required}"
  target_dir="$(dirname "$target")"
  run_with_privilege "install -d -m 0755 -o $(shell_quote "$JENKINS_AGENT_ACCOUNT") -g $(shell_quote "$JENKINS_AGENT_GROUP") $(shell_quote "$target_dir") && install -m $(shell_quote "$mode") -o $(shell_quote "$JENKINS_AGENT_ACCOUNT") -g $(shell_quote "$JENKINS_AGENT_GROUP") $(shell_quote "$source") $(shell_quote "$target")"
}

copy_tree_as_agent() {
  local source target
  source="${1:?source required}"
  target="${2:?target required}"
  run_with_privilege "rm -rf $(shell_quote "$target") && install -d -m 0755 -o $(shell_quote "$JENKINS_AGENT_ACCOUNT") -g $(shell_quote "$JENKINS_AGENT_GROUP") $(shell_quote "$target") && cp -R $(shell_quote "$source/.") $(shell_quote "$target/") && chown -R $(shell_quote "$JENKINS_AGENT_ACCOUNT:$JENKINS_AGENT_GROUP") $(shell_quote "$target")"
}

write_text_file_as_agent() {
  local target content tmp
  target="${1:?target required}"
  content="${2:?content required}"
  tmp="$(mktemp)"
  printf '%s\n' "$content" >"$tmp"
  install_file_as_agent "$tmp" "$target" 0644
  rm -f "$tmp"
}

render_template() {
  local source target text
  source="${1:?source required}"
  target="${2:?target required}"
  text="$(cat "$source")"
  text="${text//\{\{JENKINS_AGENT_ACCOUNT\}\}/$JENKINS_AGENT_ACCOUNT}"
  text="${text//\{\{JENKINS_AGENT_REMOTE_FS\}\}/$JENKINS_AGENT_REMOTE_FS}"
  text="${text//\{\{JENKINS_AGENT_NODE_NAME\}\}/$JENKINS_AGENT_NODE_NAME}"
  text="${text//\{\{JENKINS_AGENT_LABELS\}\}/$JENKINS_AGENT_LABELS}"
  text="${text//\{\{JENKINS_AGENT_EXECUTORS\}\}/$JENKINS_AGENT_EXECUTORS}"
  text="${text//\{\{JENKINS_AGENT_CREDENTIAL_ID\}\}/$JENKINS_AGENT_CREDENTIAL_ID}"
  text="${text//\{\{JENKINS_AGENT_SSH_PORT\}\}/$JENKINS_AGENT_SSH_PORT}"
  text="${text//\{\{JENKINS_AGENT_JAVA_VERSION\}\}/$JENKINS_AGENT_JAVA_VERSION}"
  text="${text//\{\{JENKINS_AGENT_CONTROLLER_PLUGIN\}\}/$JENKINS_AGENT_CONTROLLER_PLUGIN}"
  text="${text//\{\{JENKINS_AGENT_CONTROLLER_PLUGIN_SOURCE\}\}/$JENKINS_AGENT_CONTROLLER_PLUGIN_SOURCE}"
  text="${text//\{\{JENKINS_AGENT_EXECUTOR_CONTEXT\}\}/$JENKINS_AGENT_EXECUTOR_CONTEXT}"
  mkdir -p "$(dirname "$target")"
  printf '%s\n' "$text" >"$target"
}

render_template_as_agent() {
  local source target tmp
  source="${1:?source required}"
  target="${2:?target required}"
  tmp="$(mktemp)"
  render_template "$source" "$tmp"
  install_file_as_agent "$tmp" "$target" 0644
  rm -f "$tmp"
}

assert_no_unresolved_placeholders() {
  local file
  file="${1:?file required}"
  if grep -Eq '\{\{[^}]+\}\}' "$file"; then
    die "Rendered file contains unresolved template placeholders: $file"
  fi
}

validate_os_dependency_identifier() {
  local package
  package="${1:?package required}"
  case "$package" in
    *[!a-z0-9+.-]*|.*|*-|*.)
      die "Invalid Jenkins agent OS dependency identifier: $package"
      ;;
  esac
}

validate_os_dependencies() {
  for_each_csv_value "$JENKINS_AGENT_OS_DEPENDENCIES" validate_os_dependency_identifier "JENKINS_AGENT_OS_DEPENDENCIES"
}

check_os_dependency_command() {
  local package command_name
  package="${1:?package required}"
  case "$package" in
    ca-certificates) command_name="update-ca-certificates" ;;
    curl) command_name="curl" ;;
    git) command_name="git" ;;
    openssh-server) command_name="sshd" ;;
    openjdk-21-jre|openjdk-21-jre-headless) command_name="java" ;;
    rsync) command_name="rsync" ;;
    tar) command_name="tar" ;;
    unzip) command_name="unzip" ;;
    wget) command_name="wget" ;;
    *) return 0 ;;
  esac
  if ! command -v "$command_name" >/dev/null 2>&1; then
    die "Missing Jenkins agent OS dependency command '$command_name' for package '$package'"
  fi
}

check_os_dependency_expectations() {
  validate_os_dependencies
  for_each_csv_value "$JENKINS_AGENT_OS_DEPENDENCIES" check_os_dependency_command "JENKINS_AGENT_OS_DEPENDENCIES"
}

validate_artifact_output_dir() {
  local dir allowed_work base suffix
  dir="${JENKINS_AGENT_ARTIFACT_OUTPUT_DIR:-}"
  allowed_work="$JENKINS_AGENT_BUNDLE_FACTORY_WORK_DIR"
  [ -n "$dir" ] || die "JENKINS_AGENT_ARTIFACT_OUTPUT_DIR must not be empty"
  case "$dir" in
    /*) ;;
    *) die "JENKINS_AGENT_ARTIFACT_OUTPUT_DIR must be an absolute path: $dir" ;;
  esac
  case "$dir" in
    *"/../"*|*"/.."|"../"*|".."|*"//"*)
      die "Unsafe JENKINS_AGENT_ARTIFACT_OUTPUT_DIR path traversal or repeated slash: $dir"
      ;;
  esac
  case "$dir" in
    "$allowed_work"|"$allowed_work"/*)
      ;;
    /|/tmp|/tmp/*|/var|/var/*|/etc|/etc/*|/usr|/usr/*|"$repo_root"|"$repo_root"/*)
      die "Unsafe JENKINS_AGENT_ARTIFACT_OUTPUT_DIR for prepare-artifacts: $dir"
      ;;
    /home|/home/*|"$HOME"|"$HOME"/*)
      die "Unsafe JENKINS_AGENT_ARTIFACT_OUTPUT_DIR for prepare-artifacts: $dir"
      ;;
  esac
  for base in "$allowed_work"; do
    if [ "$dir" = "$base" ]; then
      return 0
    fi
    case "$dir" in
      "$base"/*)
        suffix="${dir#"$base"/}"
        [ -n "$suffix" ] || die "Unsafe empty artifact output suffix: $dir"
        case "$suffix" in
          *"/../"*|*"/.."|"../"*|".."|*"//"*|/*)
            die "Unsafe JENKINS_AGENT_ARTIFACT_OUTPUT_DIR suffix: $dir"
            ;;
        esac
        return 0
        ;;
    esac
  done
  die "JENKINS_AGENT_ARTIFACT_OUTPUT_DIR must be under $allowed_work"
}

assert_no_ssh_key_material() {
  local dir
  dir="${1:?dir required}"
  if find "$dir" -type f \( -name '*.pub' -o -name 'authorized_keys' -o -name '*_key' -o -name '*_key.*' \) -print -quit | grep -q .; then
    die "Agent artifact bundle must not contain SSH key material: $dir"
  fi
}

verify_staged_artifacts() {
  local manifest checksums
  manifest="$JENKINS_AGENT_STAGED_ARTIFACT_DIR/manifest.txt"
  checksums="$JENKINS_AGENT_STAGED_ARTIFACT_DIR/checksums.sha256"
  [ -f "$manifest" ] || die "Missing staged Jenkins agent manifest: $manifest"
  [ -f "$checksums" ] || die "Missing staged Jenkins agent checksums: $checksums"
  (cd "$JENKINS_AGENT_STAGED_ARTIFACT_DIR" && sha256sum -c checksums.sha256) >/dev/null
  [ -f "$JENKINS_AGENT_STAGED_ARTIFACT_DIR/package-intent.manifest" ] || die "Missing staged Jenkins agent package intent manifest: $JENKINS_AGENT_STAGED_ARTIFACT_DIR/package-intent.manifest"
  awk -F= '
    $1 == "harness_manifest_version" && $2 == "1" { h=1 }
    $1 == "role" && $2 == "jenkins-agent" { r=1 }
    $1 == "gerrit_version" && $2 == "not-applicable" { g=1 }
    $1 == "jenkins_version" && $2 == "not-applicable" { jn=1 }
    $1 == "jenkins_plugin_manager_version" && $2 == "not-applicable" { pm=1 }
    $1 == "java_version" && $2 == "21" { j=1 }
    $1 == "ubuntu_release" && $2 == "24.04" { u=1 }
    $1 == "ubuntu_codename" && $2 == "noble" { n=1 }
    $1 == "artifact_source" && $2 == "curated-bundle-factory" { a=1 }
    $1 == "public_internet_fallback" && $2 == "simulation-only" { p=1 }
    $1 == "os_dependency_source" && $2 == "approved-internal-os-repos" { o=1 }
    $1 == "bundle_contains_keys" && $2 == "no" { k=1 }
    END { exit !(h && r && g && jn && pm && j && u && n && a && p && o && k) }
  ' "$manifest" || die "Staged manifest does not match the Jenkins agent Version Baseline"
  awk -F= '
    $1 == "packages" && $2 != "" { p=1 }
    $1 == "source_boundary" && $2 == "approved-internal-os-repos" { s=1 }
    $1 == "public_internet_fallback" && $2 == "simulation-only" { i=1 }
    $1 == "bundle_contains_keys" && $2 == "no" { k=1 }
    END { exit !(p && s && i && k) }
  ' "$JENKINS_AGENT_STAGED_ARTIFACT_DIR/package-intent.manifest" || die "Staged package intent manifest does not enforce the required internet fallback contract"
  assert_no_ssh_key_material "$JENKINS_AGENT_STAGED_ARTIFACT_DIR"
}

cmd_preflight() {
  load_env normal
  require_env_values
  require_command sha256sum
  require_command ssh-keygen
  require_command awk
  require_command sed
  validate_agent_render_inputs
  validate_os_dependencies
  check_agent_runtime_account_readiness
  if [ "$dry_run" -eq 0 ]; then
    check_os_dependency_expectations
  fi
  [ "$JENKINS_AGENT_JAVA_VERSION" = "21" ] || die "Jenkins agent Java baseline must be OpenJDK 21"
  [ "$JENKINS_AGENT_UBUNTU_RELEASE" = "24.04" ] || die "Ubuntu release baseline must be 24.04"
  [ "$JENKINS_AGENT_UBUNTU_CODENAME" = "noble" ] || die "Ubuntu codename baseline must be noble"
  [ "$JENKINS_AGENT_CONTROLLER_PLUGIN_SOURCE" = "jenkins-controller-plugin-bundle" ] ||
    die "Jenkins agent must consume SSH Build Agents plugin from the controller plugin bundle"
  [ "$JENKINS_AGENT_EXECUTOR_CONTEXT" = "controller-owned" ] ||
    die "Jenkins agent executor and scheduling context must remain controller-owned"
  printf 'status=pass command=preflight dry_run=%s env=%s host=%s ssh_port=%s account=%s group=%s node_name=%s labels=%s mode=%s\n' \
    "$dry_run" "${env_file:-$default_env_file}" "$JENKINS_AGENT_HOST" "$JENKINS_AGENT_SSH_PORT" "$JENKINS_AGENT_ACCOUNT" "$JENKINS_AGENT_GROUP" "$JENKINS_AGENT_NODE_NAME" "$JENKINS_AGENT_LABELS" "$JENKINS_AGENT_VERIFICATION_MODE"
}

write_manifest() {
  local manifest
  manifest="$JENKINS_AGENT_ARTIFACT_OUTPUT_DIR/manifest.txt"
  cat >"$manifest" <<EOF
harness_manifest_version=1
role=jenkins-agent
ubuntu_release=24.04
ubuntu_codename=noble
java_version=21
gerrit_version=not-applicable
jenkins_version=not-applicable
jenkins_plugin_manager_version=not-applicable
artifact_source=curated-bundle-factory
public_internet_fallback=simulation-only
os_dependency_source=approved-internal-os-repos
bundle_contains_keys=no
os_dependencies=$JENKINS_AGENT_OS_DEPENDENCIES
controller_plugin=$JENKINS_AGENT_CONTROLLER_PLUGIN
controller_plugin_source=$JENKINS_AGENT_CONTROLLER_PLUGIN_SOURCE
bootstrap=jenkins-agent-bootstrap.txt
EOF
}

package_artifact_bundle() {
  local payload_dir bundle_dir preparing_dir archive checksum
  payload_dir="$JENKINS_AGENT_ARTIFACT_OUTPUT_DIR"
  bundle_dir="$(dirname "$payload_dir")"
  preparing_dir="$(dirname "$bundle_dir")"
  [ "$(basename "$bundle_dir")" = "$JENKINS_AGENT_ARTIFACT_BUNDLE_NAME" ] ||
    die "JENKINS_AGENT_ARTIFACT_OUTPUT_DIR must end with $JENKINS_AGENT_ARTIFACT_BUNDLE_NAME/jenkins-agent"
  archive="$preparing_dir/$JENKINS_AGENT_ARTIFACT_BUNDLE_NAME.tar.gz"
  checksum="$archive.sha256"
  rm -f "$archive" "$checksum"
  rm -rf "$bundle_dir/checksums"
  mkdir -p "$bundle_dir/checksums"
  (
    cd "$bundle_dir"
    find . -type f ! -path './checksums/SHA256SUMS' -print0 |
      sort -z |
      xargs -0 sha256sum >checksums/SHA256SUMS
  )
  tar -C "$preparing_dir" -czf "$archive" "$JENKINS_AGENT_ARTIFACT_BUNDLE_NAME"
  (cd "$preparing_dir" && sha256sum "$(basename "$archive")" >"$(basename "$checksum")")
  chmod u+rw,go+r "$archive" "$checksum"
}

prepare_artifact_bundle_workspace() {
  local payload_dir bundle_dir preparing_dir
  payload_dir="$JENKINS_AGENT_ARTIFACT_OUTPUT_DIR"
  bundle_dir="$(dirname "$payload_dir")"
  preparing_dir="$(dirname "$bundle_dir")"
  [ "$payload_dir" = "$JENKINS_AGENT_BUNDLE_FACTORY_WORK_DIR" ] ||
    die "JENKINS_AGENT_ARTIFACT_OUTPUT_DIR must be $JENKINS_AGENT_BUNDLE_FACTORY_WORK_DIR"
  prepare_loopforge_helper_dirs "$preparing_dir"
  rm -rf "$bundle_dir"
  mkdir -p "$payload_dir/templates"
}

cmd_prepare_artifacts() {
  load_env normal
  apply_env_defaults
  require_command sha256sum
  validate_os_dependencies
  validate_artifact_output_dir
  prepare_artifact_bundle_workspace
  write_text_file "$JENKINS_AGENT_ARTIFACT_OUTPUT_DIR/jenkins-agent-bootstrap.txt" \
    "Jenkins SSH agent bootstrap marker for Ubuntu 24.04 noble with OpenJDK 21."
  write_text_file "$JENKINS_AGENT_ARTIFACT_OUTPUT_DIR/package-intent.manifest" \
    "packages=$JENKINS_AGENT_OS_DEPENDENCIES
source_boundary=approved-internal-os-repos
public_internet_fallback=simulation-only
bundle_contains_keys=no"
  cp "$repo_root/templates/jenkins-agent/agent-runtime-profile.env.template" "$JENKINS_AGENT_ARTIFACT_OUTPUT_DIR/templates/agent-runtime-profile.env.template"
  cp "$repo_root/templates/jenkins-agent/sshd-policy.conf.template" "$JENKINS_AGENT_ARTIFACT_OUTPUT_DIR/templates/sshd-policy.conf.template"
  write_manifest
  (
    cd "$JENKINS_AGENT_ARTIFACT_OUTPUT_DIR"
    rm -f checksums.sha256
    find . -type f ! -name checksums.sha256 -print0 |
      sort -z |
      xargs -0 sha256sum >checksums.sha256
  )
  assert_no_ssh_key_material "$JENKINS_AGENT_ARTIFACT_OUTPUT_DIR"
  package_artifact_bundle
  printf 'status=pass command=prepare-artifacts artifact_dir=%s manifest=%s checksums=%s archive=%s archive_checksum=%s bundle_contains_keys=no\n' \
    "$JENKINS_AGENT_ARTIFACT_OUTPUT_DIR" "$JENKINS_AGENT_ARTIFACT_OUTPUT_DIR/manifest.txt" "$JENKINS_AGENT_ARTIFACT_OUTPUT_DIR/checksums.sha256" \
    "$(dirname "$(dirname "$JENKINS_AGENT_ARTIFACT_OUTPUT_DIR")")/$JENKINS_AGENT_ARTIFACT_BUNDLE_NAME.tar.gz" \
    "$(dirname "$(dirname "$JENKINS_AGENT_ARTIFACT_OUTPUT_DIR")")/$JENKINS_AGENT_ARTIFACT_BUNDLE_NAME.tar.gz.sha256"
}

cmd_install() {
  load_env normal
  require_env_values
  validate_agent_render_inputs
  confirm_mutation install || return 0
  verify_staged_artifacts
  ensure_dirs
  check_agent_runtime_account_readiness
  reset_agent_state_for_install
  install_file_as_agent "$JENKINS_AGENT_STAGED_ARTIFACT_DIR/jenkins-agent-bootstrap.txt" "$JENKINS_AGENT_STATE_DIR/bootstrap/jenkins-agent-bootstrap.txt" 0644
  install_file_as_agent "$JENKINS_AGENT_STAGED_ARTIFACT_DIR/package-intent.manifest" "$JENKINS_AGENT_STATE_DIR/bootstrap/package-intent.manifest" 0644
  copy_tree_as_agent "$JENKINS_AGENT_STAGED_ARTIFACT_DIR/templates" "$JENKINS_AGENT_STATE_DIR/templates"
  install_file_as_agent "$JENKINS_AGENT_STAGED_ARTIFACT_DIR/manifest.txt" "$JENKINS_AGENT_STATE_DIR/artifact-manifest.txt" 0644
  install_file_as_agent "$JENKINS_AGENT_STAGED_ARTIFACT_DIR/checksums.sha256" "$JENKINS_AGENT_STATE_DIR/artifact-checksums.sha256" 0644
  write_text_file_as_agent "$JENKINS_AGENT_STATE_DIR/state/install.status" "installed"
  printf 'status=pass command=install state_dir=%s staged=%s\n' "$JENKINS_AGENT_STATE_DIR" "$JENKINS_AGENT_STAGED_ARTIFACT_DIR"
}

check_agent_runtime_account_readiness() {
  validate_agent_remote_fs
  require_runtime_account_home "$JENKINS_AGENT_ACCOUNT" "$JENKINS_AGENT_GROUP" "$JENKINS_AGENT_NATIVE_REMOTE_FS" "Jenkins agent"
  if [ ! -d "$JENKINS_AGENT_NATIVE_REMOTE_FS" ]; then
    prepare_agent_remote_fs
  fi
  require_product_home_ownership "$JENKINS_AGENT_NATIVE_REMOTE_FS" "$JENKINS_AGENT_ACCOUNT" "$JENKINS_AGENT_GROUP" "Jenkins agent"
}

ensure_runtime_account_accepts_publickey() {
  local shadow_marker
  shadow_marker="$(awk -F: -v user="$JENKINS_AGENT_ACCOUNT" '$1 == user {print $2}' /etc/shadow 2>/dev/null || true)"
  case "$shadow_marker" in
    ""|"!"|"!!"|"\!"*)
      command -v usermod >/dev/null 2>&1 ||
        die "Runtime account $JENKINS_AGENT_ACCOUNT is locked and usermod is unavailable"
      run_with_privilege "usermod -p '*' $(shell_quote "$JENKINS_AGENT_ACCOUNT")"
      ;;
  esac
}

runtime_account_home() {
  getent passwd "$JENKINS_AGENT_ACCOUNT" | awk -F: '{print $6}'
}

validate_os_sshd_service() {
  local pidfile log_file sshd_config sshd_bin
  pidfile="$JENKINS_AGENT_STATE_DIR/run/os-sshd.pid"
  log_file="$JENKINS_AGENT_STATE_DIR/logs/sshd.log"
  sshd_config="$JENKINS_AGENT_STATE_DIR/etc/sshd_config"
  sshd_bin="$(command -v sshd)"
  run_with_privilege "install -d -m 0755 -o $(shell_quote "$JENKINS_AGENT_ACCOUNT") -g $(shell_quote "$JENKINS_AGENT_GROUP") $(shell_quote "$JENKINS_AGENT_STATE_DIR/run") $(shell_quote "$JENKINS_AGENT_STATE_DIR/logs") $(shell_quote "$JENKINS_AGENT_STATE_DIR/etc") && : >$(shell_quote "$log_file") && chown $(shell_quote "$JENKINS_AGENT_ACCOUNT:$JENKINS_AGENT_GROUP") $(shell_quote "$log_file")"
  run_with_privilege "ssh-keygen -A >>$(shell_quote "$log_file") 2>&1"
  local tmp_config tmp_log
  tmp_config="$(mktemp)"
  tmp_log="$(mktemp)"
  cat >"$tmp_config" <<EOF
Port $JENKINS_AGENT_SSH_PORT
ListenAddress 0.0.0.0
HostKey /etc/ssh/ssh_host_ed25519_key
HostKey /etc/ssh/ssh_host_rsa_key
PidFile $pidfile
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
PermitRootLogin no
AllowUsers $JENKINS_AGENT_ACCOUNT
UsePAM no
LogLevel VERBOSE
Subsystem sftp internal-sftp
EOF
  install_file_as_agent "$tmp_config" "$sshd_config" 0644
  rm -f "$tmp_config"
  {
    printf 'timestamp=%s\n' "$(iso_timestamp_utc)"
    printf 'service=os-sshd\n'
    printf 'mode=%s\n' "$JENKINS_AGENT_VERIFICATION_MODE"
    printf 'account=%s\n' "$JENKINS_AGENT_ACCOUNT"
    printf 'node_name=%s\n' "$JENKINS_AGENT_NODE_NAME"
    printf 'labels=%s\n' "$JENKINS_AGENT_LABELS"
    printf 'remote_fs=%s\n' "$JENKINS_AGENT_REMOTE_FS"
    printf 'sshd_config=%s\n' "$sshd_config"
    printf 'ownership=target-os-control-plane\n'
  } >"$tmp_log"
  run_with_privilege "cat $(shell_quote "$tmp_log") >>$(shell_quote "$log_file")"
  rm -f "$tmp_log"
  run_with_privilege "$(shell_quote "$sshd_bin") -t -f $(shell_quote "$sshd_config") >>$(shell_quote "$log_file") 2>&1" || die "sshd configuration validation failed; log=$log_file"
  pid="$(pgrep -x sshd | sed -n '1p')" || die "Target OS sshd is not running on $JENKINS_AGENT_HOST:$JENKINS_AGENT_SSH_PORT"
  write_text_file_as_agent "$pidfile" "$pid"
}

cmd_configure_runtime() {
  local account_home
  load_env normal
  require_env_values
  validate_agent_render_inputs
  require_docker_simulation
  check_agent_runtime_account_readiness
  confirm_mutation configure-runtime || return 0
  verify_staged_artifacts
  require_command ssh-keygen
  check_os_dependency_expectations
  ensure_runtime_account_accepts_publickey
  ensure_dirs
  prepare_agent_remote_fs
  prepare_agent_state_dirs
  run_with_privilege "install -d -m 0755 -o $(shell_quote "$JENKINS_AGENT_ACCOUNT") -g $(shell_quote "$JENKINS_AGENT_GROUP") $(shell_quote "$JENKINS_AGENT_STATE_DIR/etc")"
  account_home="$(runtime_account_home)"
  [ -n "$account_home" ] || die "Could not determine home directory for $JENKINS_AGENT_ACCOUNT"
  render_template_as_agent "$JENKINS_AGENT_STATE_DIR/templates/agent-runtime-profile.env.template" "$JENKINS_AGENT_STATE_DIR/etc/agent-runtime-profile.env"
  render_template_as_agent "$JENKINS_AGENT_STATE_DIR/templates/sshd-policy.conf.template" "$JENKINS_AGENT_STATE_DIR/etc/sshd-policy.conf"
  assert_no_unresolved_placeholders "$JENKINS_AGENT_STATE_DIR/etc/agent-runtime-profile.env"
  assert_no_unresolved_placeholders "$JENKINS_AGENT_STATE_DIR/etc/sshd-policy.conf"
  write_text_file_as_agent "$JENKINS_AGENT_STATE_DIR/state/runtime.status" \
    "account=$JENKINS_AGENT_ACCOUNT group=$JENKINS_AGENT_GROUP home=$account_home remote_fs=$JENKINS_AGENT_REMOTE_FS node_name=$JENKINS_AGENT_NODE_NAME labels=$JENKINS_AGENT_LABELS ssh_port=$JENKINS_AGENT_SSH_PORT executor_context=$JENKINS_AGENT_EXECUTOR_CONTEXT"
  validate_os_sshd_service
  check_ssh_reachability >/dev/null
  printf 'status=pass command=configure-runtime account=%s remote_fs=%s SSH_port=%s ssh_daemon=target-os-existing\n' \
    "$JENKINS_AGENT_ACCOUNT" "$JENKINS_AGENT_REMOTE_FS" "$JENKINS_AGENT_SSH_PORT"
}

check_ssh_reachability() {
  local banner
  banner="$(timeout 5 bash -c 'exec 3<>"/dev/tcp/$0/$1"; IFS= read -r line <&3; printf "%s\n" "$line"' "$JENKINS_AGENT_HOST" "$JENKINS_AGENT_SSH_PORT")"
  grep -Eq '^SSH-2\.0-OpenSSH_' <<<"$banner" || die "Jenkins agent SSH endpoint did not return an OpenSSH banner"
  printf '%s\n' "$banner"
}

check_runtime_account() {
  check_agent_runtime_account_readiness
}

check_remote_fs_ownership() {
  local owner group
  [ -d "$JENKINS_AGENT_REMOTE_FS" ] || die "Remote filesystem is missing: $JENKINS_AGENT_REMOTE_FS"
  owner="$(stat -c '%U' "$JENKINS_AGENT_REMOTE_FS")"
  group="$(stat -c '%G' "$JENKINS_AGENT_REMOTE_FS")"
  [ "$owner" = "$JENKINS_AGENT_ACCOUNT" ] || die "Remote filesystem owner mismatch: expected $JENKINS_AGENT_ACCOUNT got $owner"
  [ "$group" = "$JENKINS_AGENT_GROUP" ] || die "Remote filesystem group mismatch: expected $JENKINS_AGENT_GROUP got $group"
}

sshd_process_running() {
  local pid args
  pid="${1:-}"
  case "$pid" in
    ''|*[!0-9]*)
      return 1
      ;;
  esac
  args="$(ps -p "$pid" -o args= 2>/dev/null || true)"
  [ -n "$args" ] || return 1
  printf '%s\n' "$args" | grep -Eq '(^|/| )sshd([: ]|$)' || return 1
}

check_runtime_readiness() {
  verify_staged_artifacts
  validate_agent_render_inputs
  check_os_dependency_expectations
  [ -s "$JENKINS_AGENT_STATE_DIR/state/install.status" ] || die "Install marker missing"
  [ -s "$JENKINS_AGENT_STATE_DIR/state/runtime.status" ] || die "Runtime marker missing"
  [ -s "$JENKINS_AGENT_STATE_DIR/bootstrap/jenkins-agent-bootstrap.txt" ] || die "Agent bootstrap marker is missing"
  [ -s "$JENKINS_AGENT_STATE_DIR/bootstrap/package-intent.manifest" ] || die "Agent package intent manifest is missing"
  check_runtime_account
  check_remote_fs_ownership
  [ -f "$JENKINS_AGENT_STATE_DIR/run/os-sshd.pid" ] || die "Target OS sshd pid marker is missing"
  sshd_process_running "$(cat "$JENKINS_AGENT_STATE_DIR/run/os-sshd.pid")" ||
    die "Target OS sshd process is not running"
  check_ssh_reachability >/dev/null
}

cmd_validate() {
  load_env normal
  require_env_values
  validate_agent_render_inputs
  check_runtime_readiness
  cmd_collect_evidence >/dev/null
  printf 'status=pass command=validate proof=real-agent-host-side SSH=pass ssh_daemon_banner=pass remote_fs=pass runtime_account=pass node_name=%s labels=%s executor_context=%s evidence_dir=%s\n' \
    "$JENKINS_AGENT_NODE_NAME" "$JENKINS_AGENT_LABELS" "$JENKINS_AGENT_EXECUTOR_CONTEXT" "$JENKINS_AGENT_EVIDENCE_DIR"
}

cmd_collect_evidence() {
  load_env normal
  apply_env_defaults
  require_env_values
  validate_agent_render_inputs
  check_runtime_readiness
  ensure_dirs
  local evidence input_fingerprint manifest checksum bounded_log service_log q_mode q_time q_role q_checkpoint
  local q_command q_status q_input q_manifest q_checksum q_checks q_log q_service_log q_redaction
  evidence="$JENKINS_AGENT_EVIDENCE_DIR/jenkins-agent-readiness-$(timestamp_utc).json"
  bounded_log="$JENKINS_AGENT_LOG_DIR/jenkins-agent-collect-evidence-$(timestamp_utc).log"
  service_log="$JENKINS_AGENT_STATE_DIR/logs/sshd.log"
  input_fingerprint="$(printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n' "$JENKINS_AGENT_HOST" "$JENKINS_AGENT_SSH_PORT" "$JENKINS_AGENT_ACCOUNT" "$JENKINS_AGENT_GROUP" "$JENKINS_AGENT_REMOTE_FS" "$JENKINS_AGENT_NODE_NAME" "$JENKINS_AGENT_LABELS" | sha256sum | awk '{print $1}')"
  manifest="$JENKINS_AGENT_STAGED_ARTIFACT_DIR/manifest.txt"
  checksum="$JENKINS_AGENT_STAGED_ARTIFACT_DIR/checksums.sha256"
  {
    printf 'timestamp=%s\n' "$(iso_timestamp_utc)"
    printf 'command=collect-evidence\n'
    printf 'verification_mode=%s\n' "$JENKINS_AGENT_VERIFICATION_MODE"
    printf 'artifact_manifest=%s\n' "$manifest"
    printf 'checksum_reference=%s\n' "$checksum"
    printf 'observed=static-os-dependency-baseline,dependency-commands,ssh-reachability,real-sshd-banner,remote-filesystem,runtime-account-ownership\n'
    printf 'account=%s\n' "$JENKINS_AGENT_ACCOUNT"
    printf 'group=%s\n' "$JENKINS_AGENT_GROUP"
    printf 'node_name=%s\n' "$JENKINS_AGENT_NODE_NAME"
    printf 'labels=%s\n' "$JENKINS_AGENT_LABELS"
    printf 'executor_context=%s\n' "$JENKINS_AGENT_EXECUTOR_CONTEXT"
    printf 'remote_fs=%s\n' "$JENKINS_AGENT_REMOTE_FS"
    printf 'redaction=secrets-not-recorded\n'
  } >"$bounded_log"
  [ -s "$bounded_log" ] || die "Bounded evidence log was not written: $bounded_log"
  [ -s "$service_log" ] || die "sshd bounded log is missing: $service_log"
  q_mode="$(json_quote "$JENKINS_AGENT_VERIFICATION_MODE")"
  q_time="$(json_quote "$(iso_timestamp_utc)")"
  q_role="$(json_quote "jenkins-agent")"
  q_checkpoint="$(json_quote "jenkins-agent-readiness")"
  q_command="$(json_quote "jenkins-agent-setup.sh collect-evidence")"
  q_status="$(json_quote "pass")"
  q_input="$(json_quote "$input_fingerprint")"
  q_manifest="$(json_quote "$manifest")"
  q_checksum="$(json_quote "$checksum")"
  q_checks="$(json_quote "real agent-host-side readiness: static OS dependency baseline, dependency commands including java, ssh, and sshd, SSH reachability, real sshd banner, remote filesystem ownership, runtime account ownership; node_name=$JENKINS_AGENT_NODE_NAME labels=$JENKINS_AGENT_LABELS executor_context=$JENKINS_AGENT_EXECUTOR_CONTEXT")"
  q_log="$(json_quote "$bounded_log")"
  q_service_log="$(json_quote "$service_log")"
  q_redaction="$(json_quote "secrets-redacted; private keys, passwords, tokens, and LDAP bind secrets not recorded")"
  cat >"$evidence" <<EOF
{
  "verification_mode": $q_mode,
  "timestamp": $q_time,
  "role_or_environment": $q_role,
  "checkpoint_name": $q_checkpoint,
  "command_name": $q_command,
  "status": $q_status,
  "reviewed_input_fingerprint": $q_input,
  "artifact_manifest_references": $q_manifest,
  "checksum_references": $q_checksum,
  "checksum_verification_result": "pass",
  "observed_checks": $q_checks,
  "bounded_log_references": $q_log,
  "service_log_reference": $q_service_log,
  "redaction_status": $q_redaction
}
EOF
  printf 'status=pass command=collect-evidence evidence=%s\n' "$evidence"
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --env)
        [ "$#" -ge 2 ] || die_usage "--env requires a value"
        env_file="$2"
        shift 2
        ;;
      --env=*)
        env_file="${1#--env=}"
        shift
        ;;
      --dry-run)
        dry_run=1
        shift
        ;;
      --yes)
        assume_yes=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      print-env-template|preflight|prepare-artifacts|prepare-target-workspace|install|configure-runtime|validate|collect-evidence)
        command_name="$1"
        shift
        [ "$#" -eq 0 ] || die_usage "Unexpected arguments after command: $*"
        return 0
        ;;
      "")
        usage
        exit 1
        ;;
      *)
        die_usage "Unknown option or command: $1"
        ;;
    esac
  done
  usage
  exit 1
}

main() {
  local command_name=""
  parse_args "$@"
  case "$command_name" in
    print-env-template) print_env_template ;;
    preflight) cmd_preflight ;;
    prepare-artifacts) cmd_prepare_artifacts ;;
    prepare-target-workspace) cmd_prepare_target_workspace ;;
    install) cmd_install ;;
    configure-runtime) cmd_configure_runtime ;;
    validate) cmd_validate ;;
    collect-evidence) cmd_collect_evidence ;;
    *) die_usage "Unknown command: $command_name" ;;
  esac
}

main "$@"
