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

usage() {
  cat <<'USAGE'
Usage:
  scripts/jenkins-agent-setup.sh [--env FILE] [--dry-run] [--yes] <command>

Commands:
  print-env-template
  preflight
  prepare-artifacts
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
  JENKINS_AGENT_REMOTE_FS="${JENKINS_AGENT_REMOTE_FS:-/var/lib/jenkins-agent}"
  JENKINS_AGENT_NODE_NAME="${JENKINS_AGENT_NODE_NAME:-build-linux-x86-01}"
  JENKINS_AGENT_LABELS="${JENKINS_AGENT_LABELS:-linux x86_64 general-build gerrit-ci}"
  JENKINS_AGENT_EXECUTORS="${JENKINS_AGENT_EXECUTORS:-5}"
  JENKINS_AGENT_CREDENTIAL_ID="${JENKINS_AGENT_CREDENTIAL_ID:-jenkins-agent-ssh}"
  JENKINS_AGENT_STATE_DIR="${JENKINS_AGENT_STATE_DIR:-/harness/state/agent}"
  JENKINS_AGENT_STAGED_ARTIFACT_DIR="${JENKINS_AGENT_STAGED_ARTIFACT_DIR:-/harness/staged}"
  JENKINS_AGENT_ARTIFACT_OUTPUT_DIR="${JENKINS_AGENT_ARTIFACT_OUTPUT_DIR:-/harness/state/artifacts/jenkins-agent}"
  JENKINS_AGENT_EVIDENCE_DIR="${JENKINS_AGENT_EVIDENCE_DIR:-/harness/evidence}"
  JENKINS_AGENT_LOG_DIR="${JENKINS_AGENT_LOG_DIR:-/harness/logs}"
  JENKINS_AGENT_VERIFICATION_MODE="${JENKINS_AGENT_VERIFICATION_MODE:-docker-harness-simulation}"
  JENKINS_AGENT_OS_DEPENDENCIES="${JENKINS_AGENT_OS_DEPENDENCIES:-ca-certificates,curl,git,openssh-client,openssh-server,openjdk-21-jre,rsync,tar,unzip,wget}"
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
  mkdir -p "$JENKINS_AGENT_STATE_DIR" "$JENKINS_AGENT_EVIDENCE_DIR" "$JENKINS_AGENT_LOG_DIR"
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

require_docker_harness_simulation() {
  [ "${HARNESS_MODE:-}" = "docker-harness-simulation" ] ||
    die "Target-local SSH readiness is supported only in Docker harness simulation mode"
  [ "${HARNESS_ENVIRONMENT:-}" = "jenkins-agent-target" ] ||
    die "Target-local SSH readiness is supported only in the Jenkins agent Docker harness target"
  [ "$JENKINS_AGENT_VERIFICATION_MODE" = "docker-harness-simulation" ] ||
    die "JENKINS_AGENT_VERIFICATION_MODE must be docker-harness-simulation for agent readiness validation"
}

is_docker_harness_simulation() {
  [ "${HARNESS_MODE:-}" = "docker-harness-simulation" ] &&
    [ "${HARNESS_ENVIRONMENT:-}" = "jenkins-agent-target" ] &&
    [ "$JENKINS_AGENT_VERIFICATION_MODE" = "docker-harness-simulation" ]
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
    /harness/state/agent|/harness/state/agent/*)
      ;;
    *)
      die "JENKINS_AGENT_STATE_DIR must be under /harness/state/agent"
      ;;
  esac
}

validate_agent_remote_fs() {
  local value allowed_home
  value="${JENKINS_AGENT_REMOTE_FS:-}"
  validate_safe_absolute_path_string JENKINS_AGENT_REMOTE_FS "$value"
  allowed_home="/home/$JENKINS_AGENT_ACCOUNT/workspace"
  case "$value" in
    "$allowed_home"|"$allowed_home"/*|/var/lib/jenkins-agent|/var/lib/jenkins-agent/*|/harness/state/agent/workspace|/harness/state/agent/workspace/*)
      ;;
    *)
      die "JENKINS_AGENT_REMOTE_FS must be under $allowed_home, /var/lib/jenkins-agent, or /harness/state/agent/workspace"
      ;;
  esac
  case "$value" in
    /|/etc|/etc/*|/usr|/usr/*|/var|/var/*|/tmp|/tmp/*|/root|/root/*|/home|/home/*)
      case "$value" in
        "$allowed_home"|"$allowed_home"/*|/var/lib/jenkins-agent|/var/lib/jenkins-agent/*)
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
    openssh-client) command_name="ssh" ;;
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
  local dir repo_generated allowed_harness allowed_repo base suffix
  dir="${JENKINS_AGENT_ARTIFACT_OUTPUT_DIR:-}"
  repo_generated="$repo_root/simulation/state/generated-artifacts/jenkins-agent"
  allowed_harness="/harness/state/artifacts/jenkins-agent"
  allowed_repo="$repo_generated"
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
    /|/tmp|/tmp/*|/var|/var/*|/etc|/etc/*|/usr|/usr/*|/home|/home/*|"$HOME"|"$HOME"/*|"$repo_root"|"$repo_root"/*)
      case "$dir" in
        "$allowed_repo"|"$allowed_repo"/*)
          ;;
        *)
          die "Unsafe JENKINS_AGENT_ARTIFACT_OUTPUT_DIR for prepare-artifacts: $dir"
          ;;
      esac
      ;;
  esac
  for base in "$allowed_harness" "$allowed_repo"; do
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
  die "JENKINS_AGENT_ARTIFACT_OUTPUT_DIR must be under $allowed_harness or $allowed_repo"
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
  require_command ssh
  validate_agent_render_inputs
  validate_os_dependencies
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

cmd_prepare_artifacts() {
  load_env normal
  apply_env_defaults
  require_command sha256sum
  validate_os_dependencies
  validate_artifact_output_dir
  rm -rf "$JENKINS_AGENT_ARTIFACT_OUTPUT_DIR"
  mkdir -p "$JENKINS_AGENT_ARTIFACT_OUTPUT_DIR/templates"
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
  printf 'status=pass command=prepare-artifacts artifact_dir=%s manifest=%s checksums=%s bundle_contains_keys=no\n' \
    "$JENKINS_AGENT_ARTIFACT_OUTPUT_DIR" "$JENKINS_AGENT_ARTIFACT_OUTPUT_DIR/manifest.txt" "$JENKINS_AGENT_ARTIFACT_OUTPUT_DIR/checksums.sha256"
}

cmd_install() {
  load_env normal
  require_env_values
  validate_agent_render_inputs
  confirm_mutation install || return 0
  verify_staged_artifacts
  ensure_dirs
  mkdir -p "$JENKINS_AGENT_STATE_DIR/bootstrap" "$JENKINS_AGENT_STATE_DIR/templates" "$JENKINS_AGENT_STATE_DIR/state"
  cp "$JENKINS_AGENT_STAGED_ARTIFACT_DIR/jenkins-agent-bootstrap.txt" "$JENKINS_AGENT_STATE_DIR/bootstrap/jenkins-agent-bootstrap.txt"
  cp "$JENKINS_AGENT_STAGED_ARTIFACT_DIR/package-intent.manifest" "$JENKINS_AGENT_STATE_DIR/bootstrap/package-intent.manifest"
  cp -R "$JENKINS_AGENT_STAGED_ARTIFACT_DIR/templates/." "$JENKINS_AGENT_STATE_DIR/templates/"
  cp "$JENKINS_AGENT_STAGED_ARTIFACT_DIR/manifest.txt" "$JENKINS_AGENT_STATE_DIR/artifact-manifest.txt"
  cp "$JENKINS_AGENT_STAGED_ARTIFACT_DIR/checksums.sha256" "$JENKINS_AGENT_STATE_DIR/artifact-checksums.sha256"
  write_text_file "$JENKINS_AGENT_STATE_DIR/state/install.status" "installed"
  printf 'status=pass command=install state_dir=%s staged=%s\n' "$JENKINS_AGENT_STATE_DIR" "$JENKINS_AGENT_STAGED_ARTIFACT_DIR"
}

create_runtime_account_if_needed() {
  local existing_gid expected_gid
  if ! getent group "$JENKINS_AGENT_GROUP" >/dev/null 2>&1; then
    if command -v groupadd >/dev/null 2>&1; then
      groupadd "$JENKINS_AGENT_GROUP"
    else
      die "Runtime group $JENKINS_AGENT_GROUP does not exist and groupadd is unavailable"
    fi
  fi
  if id "$JENKINS_AGENT_ACCOUNT" >/dev/null 2>&1; then
    existing_gid="$(id -g "$JENKINS_AGENT_ACCOUNT")"
    expected_gid="$(getent group "$JENKINS_AGENT_GROUP" | awk -F: '{print $3}')"
    [ "$existing_gid" = "$expected_gid" ] ||
      die "Existing runtime account $JENKINS_AGENT_ACCOUNT primary group differs from JENKINS_AGENT_GROUP=$JENKINS_AGENT_GROUP; review and fix the account primary group outside this helper before rerunning"
    return 0
  fi
  if command -v useradd >/dev/null 2>&1; then
    useradd --create-home --shell /bin/sh --gid "$JENKINS_AGENT_GROUP" "$JENKINS_AGENT_ACCOUNT"
    return 0
  fi
  die "Runtime account $JENKINS_AGENT_ACCOUNT does not exist and useradd is unavailable"
}

ensure_runtime_account_accepts_publickey() {
  local shadow_marker
  shadow_marker="$(awk -F: -v user="$JENKINS_AGENT_ACCOUNT" '$1 == user {print $2}' /etc/shadow 2>/dev/null || true)"
  case "$shadow_marker" in
    ""|"!"|"!!"|"\!"*)
      if command -v usermod >/dev/null 2>&1; then
        usermod -p '*' "$JENKINS_AGENT_ACCOUNT"
      else
        die "Runtime account $JENKINS_AGENT_ACCOUNT is locked and usermod is unavailable"
      fi
      ;;
  esac
}

runtime_account_home() {
  getent passwd "$JENKINS_AGENT_ACCOUNT" | awk -F: '{print $6}'
}

sshd_pid_matches_config() {
  local pid expected_config cmdline
  pid="${1:?pid required}"
  expected_config="${2:?config required}"
  case "$pid" in
    ""|*[!0-9]*)
      return 1
      ;;
  esac
  [ -r "/proc/$pid/cmdline" ] || return 1
  cmdline="$(tr '\0' ' ' <"/proc/$pid/cmdline")"
  case "$cmdline" in
    *sshd*" -f $expected_config"*|*sshd*" -f"*" $expected_config"*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

process_is_zombie() {
  local pid state
  pid="${1:?pid required}"
  [ -r "/proc/$pid/stat" ] || return 1
  state="$(awk '{print $3}' "/proc/$pid/stat")"
  [ "$state" = "Z" ]
}

stop_helper_owned_sshd() {
  local pidfile expected_config pid attempt
  pidfile="${1:?pidfile required}"
  expected_config="${2:?config required}"
  [ -f "$pidfile" ] || return 0
  pid="$(cat "$pidfile")"
  if ! kill -0 "$pid" 2>/dev/null; then
    rm -f "$pidfile"
    return 0
  fi
  if process_is_zombie "$pid"; then
    rm -f "$pidfile"
    return 0
  fi
  if ! sshd_pid_matches_config "$pid" "$expected_config"; then
    die "Refusing to stop non-helper-owned sshd pid $pid from $pidfile"
  fi
  kill "$pid" 2>/dev/null || true
  for attempt in 1 2 3 4 5; do
    if ! kill -0 "$pid" 2>/dev/null || process_is_zombie "$pid"; then
      rm -f "$pidfile"
      return 0
    fi
    sleep 1
  done
  die "Helper-owned sshd pid $pid did not stop"
}

start_sshd_service() {
  local pidfile log_file sshd_config sshd_bin pid
  pidfile="$JENKINS_AGENT_STATE_DIR/run/sshd.pid"
  log_file="$JENKINS_AGENT_STATE_DIR/logs/sshd.log"
  sshd_config="$JENKINS_AGENT_STATE_DIR/etc/sshd_config"
  sshd_bin="$(command -v sshd)"
  mkdir -p "$JENKINS_AGENT_STATE_DIR/run" "$JENKINS_AGENT_STATE_DIR/logs" /run/sshd /var/run/sshd
  stop_helper_owned_sshd "$pidfile" "$sshd_config"
  : >"$log_file"
  ssh-keygen -A >>"$log_file" 2>&1
  cat >"$sshd_config" <<EOF
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
  {
    printf 'timestamp=%s\n' "$(iso_timestamp_utc)"
    printf 'service=sshd\n'
    printf 'mode=%s\n' "$JENKINS_AGENT_VERIFICATION_MODE"
    printf 'account=%s\n' "$JENKINS_AGENT_ACCOUNT"
    printf 'node_name=%s\n' "$JENKINS_AGENT_NODE_NAME"
    printf 'labels=%s\n' "$JENKINS_AGENT_LABELS"
    printf 'remote_fs=%s\n' "$JENKINS_AGENT_REMOTE_FS"
    printf 'sshd_config=%s\n' "$sshd_config"
  } >>"$log_file"
  "$sshd_bin" -t -f "$sshd_config" >>"$log_file" 2>&1 || die "sshd configuration validation failed; log=$log_file"
  "$sshd_bin" -D -e -f "$sshd_config" >>"$log_file" 2>&1 &
  pid="$!"
  printf '%s\n' "$pid" >"$pidfile"
  sleep 1
  if ! kill -0 "$pid" 2>/dev/null; then
    die "Jenkins agent sshd failed to start; log=$log_file"
  fi
}

cmd_configure_runtime() {
  local account_home
  load_env normal
  require_env_values
  validate_agent_render_inputs
  confirm_mutation configure-runtime || return 0
  require_docker_harness_simulation
  verify_staged_artifacts
  require_command ssh-keygen
  check_os_dependency_expectations
  create_runtime_account_if_needed
  ensure_runtime_account_accepts_publickey
  ensure_dirs
  mkdir -p "$JENKINS_AGENT_REMOTE_FS" "$JENKINS_AGENT_STATE_DIR/etc" "$JENKINS_AGENT_STATE_DIR/state"
  chown -R "$JENKINS_AGENT_ACCOUNT:$JENKINS_AGENT_GROUP" "$JENKINS_AGENT_REMOTE_FS"
  account_home="$(runtime_account_home)"
  [ -n "$account_home" ] || die "Could not determine home directory for $JENKINS_AGENT_ACCOUNT"
  render_template "$JENKINS_AGENT_STATE_DIR/templates/agent-runtime-profile.env.template" "$JENKINS_AGENT_STATE_DIR/etc/agent-runtime-profile.env"
  render_template "$JENKINS_AGENT_STATE_DIR/templates/sshd-policy.conf.template" "$JENKINS_AGENT_STATE_DIR/etc/sshd-policy.conf"
  assert_no_unresolved_placeholders "$JENKINS_AGENT_STATE_DIR/etc/agent-runtime-profile.env"
  assert_no_unresolved_placeholders "$JENKINS_AGENT_STATE_DIR/etc/sshd-policy.conf"
  write_text_file "$JENKINS_AGENT_STATE_DIR/state/runtime.status" \
    "account=$JENKINS_AGENT_ACCOUNT group=$JENKINS_AGENT_GROUP home=$account_home remote_fs=$JENKINS_AGENT_REMOTE_FS node_name=$JENKINS_AGENT_NODE_NAME labels=$JENKINS_AGENT_LABELS ssh_port=$JENKINS_AGENT_SSH_PORT executor_context=$JENKINS_AGENT_EXECUTOR_CONTEXT"
  start_sshd_service
  printf 'status=pass command=configure-runtime account=%s remote_fs=%s SSH_port=%s ssh_daemon=started\n' \
    "$JENKINS_AGENT_ACCOUNT" "$JENKINS_AGENT_REMOTE_FS" "$JENKINS_AGENT_SSH_PORT"
}

check_ssh_reachability() {
  local banner
  banner="$(timeout 5 bash -c 'exec 3<>"/dev/tcp/$0/$1"; IFS= read -r line <&3; printf "%s\n" "$line"' "$JENKINS_AGENT_HOST" "$JENKINS_AGENT_SSH_PORT")"
  grep -Eq '^SSH-2\.0-OpenSSH_' <<<"$banner" || die "Jenkins agent SSH endpoint did not return an OpenSSH banner"
  printf '%s\n' "$banner"
}

check_runtime_account() {
  id "$JENKINS_AGENT_ACCOUNT" >/dev/null 2>&1 || die "Runtime account does not exist: $JENKINS_AGENT_ACCOUNT"
}

check_remote_fs_ownership() {
  local owner group
  [ -d "$JENKINS_AGENT_REMOTE_FS" ] || die "Remote filesystem is missing: $JENKINS_AGENT_REMOTE_FS"
  owner="$(stat -c '%U' "$JENKINS_AGENT_REMOTE_FS")"
  group="$(stat -c '%G' "$JENKINS_AGENT_REMOTE_FS")"
  [ "$owner" = "$JENKINS_AGENT_ACCOUNT" ] || die "Remote filesystem owner mismatch: expected $JENKINS_AGENT_ACCOUNT got $owner"
  [ "$group" = "$JENKINS_AGENT_GROUP" ] || die "Remote filesystem group mismatch: expected $JENKINS_AGENT_GROUP got $group"
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
  [ -f "$JENKINS_AGENT_STATE_DIR/run/sshd.pid" ] || die "Jenkins agent sshd pid is missing"
  kill -0 "$(cat "$JENKINS_AGENT_STATE_DIR/run/sshd.pid")" 2>/dev/null ||
    die "Jenkins agent sshd process is not running"
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
  local q_command q_status q_input q_manifest q_checksum q_checks q_log q_redaction
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
  q_log="$(json_quote "$bounded_log;$service_log")"
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
      print-env-template|preflight|prepare-artifacts|install|configure-runtime|validate|collect-evidence)
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
    install) cmd_install ;;
    configure-runtime) cmd_configure_runtime ;;
    validate) cmd_validate ;;
    collect-evidence) cmd_collect_evidence ;;
    *) die_usage "Unknown command: $command_name" ;;
  esac
}

main "$@"
