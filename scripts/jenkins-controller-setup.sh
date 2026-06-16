#!/usr/bin/env bash

set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
repo_root="$(CDPATH= cd -- "$script_dir/.." && pwd)"
# shellcheck source=common.sh
. "$script_dir/common.sh"

role="jenkins-controller"
default_env_file="$repo_root/examples/jenkins-controller.env.example"
env_file=""
dry_run=0
assume_yes=0

usage() {
  cat <<'USAGE'
Usage:
  scripts/jenkins-controller-setup.sh [--env FILE] [--dry-run] [--yes] <command>

Commands:
  print-env-template
  preflight
  prepare-artifacts
  install
  configure-service
  install-plugins
  configure-jcasc
  generate-integration-key
  generate-agent-key
  configure-integration
  configure-agent
  validate-agent
  verify-trigger
  validate
  collect-evidence

Options:
  --env FILE     Source reviewed Jenkins controller env values from FILE.
  --dry-run      Check inputs and describe non-mutating results only.
  --yes          Confirm mutating commands after env review.
  -h, --help     Show this help.

The manual remains the authority. This helper accelerates reviewed Jenkins
controller phases and never downloads Jenkins application artifacts on the
target host.
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

file_set_digest() {
  local dir pattern
  dir="${1:?dir required}"
  pattern="${2:?pattern required}"
  [ -d "$dir" ] || die "Missing directory for digest: $dir"
  (
    cd "$dir"
    find . -type f -name "$pattern" -print0 |
      sort -z |
      while IFS= read -r -d '' file; do
        printf '%s %s\n' "${file#./}" "$(sha256_file "$file")"
      done |
      sha256sum |
      awk '{print $1}'
  )
}

plugin_set_digest() {
  file_set_digest "$JENKINS_HOME/plugins" "*.jpi"
}

template_set_digest() {
  file_set_digest "$JENKINS_HOME/templates" "*"
}

public_key_fingerprint() {
  local file
  file="${1:?public key file required}"
  ssh-keygen -l -f "$file" | awk '{print $2}'
}

validate_public_key_file() {
  local file first_line line_count
  file="${1:?public key file required}"
  [ -s "$file" ] || die "Public key file is empty or missing: $file"
  if grep -Eq 'PRIVATE KEY|^-----BEGIN |^-----END ' "$file"; then
    die "Refusing private-key or PEM material where a public key is required: $file"
  fi
  first_line="$(sed -n '1p' "$file")"
  line_count="$(wc -l <"$file" | tr -d ' ')"
  [ "$line_count" -eq 1 ] || die "Public key file must contain exactly one OpenSSH public key line: $file"
  case "$first_line" in
    ssh-ed25519\ *|ssh-rsa\ *|ecdsa-sha2-nistp256\ *|ecdsa-sha2-nistp384\ *|ecdsa-sha2-nistp521\ *)
      ;;
    *)
      die "Public key file does not start with a supported OpenSSH public key type: $file"
      ;;
  esac
  public_key_fingerprint "$file" >/dev/null || die "ssh-keygen could not fingerprint public key file: $file"
}

validate_private_key_file() {
  local file
  file="${1:?private key file required}"
  [ -s "$file" ] || die "Private key file is empty or missing: $file"
  grep -Eq 'PRIVATE KEY' "$file" || die "Expected private key material is missing: $file"
  public_key_fingerprint "${file}.pub" >/dev/null || die "Matching public key cannot be fingerprinted: ${file}.pub"
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
JENKINS_VERSION
JENKINS_JAVA_VERSION
JENKINS_PLUGIN_MANAGER_VERSION
JENKINS_UBUNTU_RELEASE
JENKINS_UBUNTU_CODENAME
JENKINS_HOST
JENKINS_URL
JENKINS_HTTP_PORT
JENKINS_RUNTIME_ACCOUNT
JENKINS_HOME
JENKINS_STAGED_ARTIFACT_DIR
JENKINS_ARTIFACT_OUTPUT_DIR
JENKINS_PLUGIN_LIST
LDAP_URL
LDAP_BIND_DN
LDAP_USER_BASE
LDAP_GROUP_BASE
JENKINS_ADMIN_ACCOUNT
JENKINS_ADMIN_GROUP
GERRIT_HTTP_URL
GERRIT_SSH_HOST
GERRIT_SSH_PORT
GERRIT_TRIGGER_SERVER_NAME
JENKINS_GERRIT_INTEGRATION_ACCOUNT
JENKINS_GERRIT_CREDENTIAL_ID
JENKINS_GERRIT_PRIVATE_KEY_FILE
JENKINS_GERRIT_PUBLIC_KEY_FILE
JENKINS_AGENT_HOST
JENKINS_AGENT_SSH_PORT
JENKINS_AGENT_ACCOUNT
JENKINS_AGENT_LABEL
JENKINS_AGENT_REMOTE_FS
JENKINS_AGENT_KNOWN_HOSTS_FILE
JENKINS_AGENT_CREDENTIAL_ID
JENKINS_AGENT_PRIVATE_KEY_FILE
JENKINS_AGENT_PUBLIC_KEY_FILE
GERRIT_VERIFICATION_PROJECT
GERRIT_VERIFICATION_BRANCH
VERIFICATION_RUN_ID
JENKINS_VERIFICATION_MODE
JENKINS_EVIDENCE_DIR
"
  for name in $required; do
    if [ "$dry_run" -eq 1 ]; then
      [ -n "$(value_or_default "$name" "")" ] || die "Missing env value $name"
    else
      require_reviewed_value "$name"
    fi
  done
}

require_account_separation() {
  [ "$JENKINS_ADMIN_ACCOUNT" != "$JENKINS_GERRIT_INTEGRATION_ACCOUNT" ] ||
    die "Jenkins admin account must not match Jenkins Gerrit integration account"
  [ "$JENKINS_RUNTIME_ACCOUNT" != "$JENKINS_ADMIN_ACCOUNT" ] ||
    die "Jenkins runtime account must not match Jenkins admin account"
  [ "$JENKINS_RUNTIME_ACCOUNT" != "$JENKINS_GERRIT_INTEGRATION_ACCOUNT" ] ||
    die "Jenkins runtime account must not match Jenkins Gerrit integration account"
  [ "$JENKINS_AGENT_ACCOUNT" != "$JENKINS_GERRIT_INTEGRATION_ACCOUNT" ] ||
    die "Jenkins agent account must not match Jenkins Gerrit integration account"
}

apply_env_defaults() {
  JENKINS_VERSION="${JENKINS_VERSION:-2.555.3}"
  JENKINS_JAVA_VERSION="${JENKINS_JAVA_VERSION:-21}"
  JENKINS_PLUGIN_MANAGER_VERSION="${JENKINS_PLUGIN_MANAGER_VERSION:-2.15.0}"
  JENKINS_UBUNTU_RELEASE="${JENKINS_UBUNTU_RELEASE:-24.04}"
  JENKINS_UBUNTU_CODENAME="${JENKINS_UBUNTU_CODENAME:-noble}"
  JENKINS_HOST="${JENKINS_HOST:-jenkins-controller-target}"
  JENKINS_URL="${JENKINS_URL:-http://jenkins-controller-target:8080/}"
  JENKINS_HTTP_PORT="${JENKINS_HTTP_PORT:-8080}"
  JENKINS_RUNTIME_ACCOUNT="${JENKINS_RUNTIME_ACCOUNT:-jenkins}"
  JENKINS_HOME="${JENKINS_HOME:-/harness/state/jenkins-home}"
  JENKINS_STAGED_ARTIFACT_DIR="${JENKINS_STAGED_ARTIFACT_DIR:-/harness/staged}"
  JENKINS_ARTIFACT_OUTPUT_DIR="${JENKINS_ARTIFACT_OUTPUT_DIR:-/harness/state/artifacts/jenkins-controller}"
  JENKINS_EVIDENCE_DIR="${JENKINS_EVIDENCE_DIR:-/harness/evidence}"
  JENKINS_LOG_DIR="${JENKINS_LOG_DIR:-/harness/logs}"
  JENKINS_VERIFICATION_MODE="${JENKINS_VERIFICATION_MODE:-docker-harness-simulation}"
  JENKINS_OS_DEPENDENCIES="${JENKINS_OS_DEPENDENCIES:-ca-certificates,curl,fontconfig,git,net-tools,netcat-openbsd,openjdk-21-jre,openssh-client,rsync,tar,unzip,wget}"
  JENKINS_PLUGIN_LIST="${JENKINS_PLUGIN_LIST:-configuration-as-code:2006.v001a_2ca_6b_574,credentials:1415.v831096eb_5534,git:5.7.0,gerrit-trigger:2.43.0,ldap:780.vcb_33c9a_e4332,matrix-auth:3.2.6,ssh-credentials:361.vb_f6760818e8c,ssh-slaves:3.1031.v72c6b_883b_869,workflow-aggregator:608.v67378e9d3db_1,job-dsl:1.93,timestamper:1.30,ws-cleanup:0.48}"
  LDAP_URL="${LDAP_URL:-ldap://ldap:389}"
  LDAP_BIND_DN="${LDAP_BIND_DN:-cn=readonly,dc=example,dc=test}"
  LDAP_USER_BASE="${LDAP_USER_BASE:-ou=people,dc=example,dc=test}"
  LDAP_GROUP_BASE="${LDAP_GROUP_BASE:-ou=groups,dc=example,dc=test}"
  JENKINS_ADMIN_ACCOUNT="${JENKINS_ADMIN_ACCOUNT:-jenkins-admin}"
  JENKINS_ADMIN_GROUP="${JENKINS_ADMIN_GROUP:-jenkins-admins}"
  GERRIT_HTTP_URL="${GERRIT_HTTP_URL:-http://gerrit-target:8080/}"
  GERRIT_SSH_HOST="${GERRIT_SSH_HOST:-gerrit-target}"
  GERRIT_SSH_PORT="${GERRIT_SSH_PORT:-29418}"
  GERRIT_TRIGGER_SERVER_NAME="${GERRIT_TRIGGER_SERVER_NAME:-gerrit-primary}"
  JENKINS_GERRIT_INTEGRATION_ACCOUNT="${JENKINS_GERRIT_INTEGRATION_ACCOUNT:-jenkins-gerrit}"
  JENKINS_GERRIT_CREDENTIAL_ID="${JENKINS_GERRIT_CREDENTIAL_ID:-gerrit-jenkins-ssh}"
  JENKINS_GERRIT_PRIVATE_KEY_FILE="${JENKINS_GERRIT_PRIVATE_KEY_FILE:-$JENKINS_HOME/keys/gerrit_ed25519}"
  JENKINS_GERRIT_PUBLIC_KEY_FILE="${JENKINS_GERRIT_PUBLIC_KEY_FILE:-$JENKINS_HOME/public-handoff/jenkins-gerrit.pub}"
  JENKINS_AGENT_HOST="${JENKINS_AGENT_HOST:-jenkins-agent-target}"
  JENKINS_AGENT_SSH_PORT="${JENKINS_AGENT_SSH_PORT:-22}"
  JENKINS_AGENT_ACCOUNT="${JENKINS_AGENT_ACCOUNT:-jenkins-agent}"
  JENKINS_AGENT_LABEL="${JENKINS_AGENT_LABEL:-review-agent}"
  JENKINS_AGENT_REMOTE_FS="${JENKINS_AGENT_REMOTE_FS:-/home/jenkins-agent/workspace}"
  JENKINS_AGENT_KNOWN_HOSTS_FILE="${JENKINS_AGENT_KNOWN_HOSTS_FILE:-$JENKINS_HOME/ssh/agent-known-hosts}"
  JENKINS_AGENT_CREDENTIAL_ID="${JENKINS_AGENT_CREDENTIAL_ID:-jenkins-agent-ssh}"
  JENKINS_AGENT_PRIVATE_KEY_FILE="${JENKINS_AGENT_PRIVATE_KEY_FILE:-$JENKINS_HOME/keys/agent_ed25519}"
  JENKINS_AGENT_PUBLIC_KEY_FILE="${JENKINS_AGENT_PUBLIC_KEY_FILE:-$JENKINS_HOME/public-handoff/jenkins-agent.pub}"
  GERRIT_VERIFICATION_PROJECT="${GERRIT_VERIFICATION_PROJECT:-verification-disposable-jenkins}"
  GERRIT_VERIFICATION_BRANCH="${GERRIT_VERIFICATION_BRANCH:-master}"
  VERIFICATION_RUN_ID="${VERIFICATION_RUN_ID:-docker-harness-jenkins-controller}"
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
  mkdir -p "$JENKINS_HOME" "$JENKINS_EVIDENCE_DIR" "$JENKINS_LOG_DIR"
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
    die "Target-local observable service is supported only in Docker harness simulation mode"
  [ "${HARNESS_ENVIRONMENT:-}" = "jenkins-controller-target" ] ||
    die "Target-local observable service is supported only in the Jenkins controller Docker harness target"
  [ "$JENKINS_VERIFICATION_MODE" = "docker-harness-simulation" ] ||
    die "JENKINS_VERIFICATION_MODE must be docker-harness-simulation for target-local observable service validation"
}

is_docker_harness_simulation() {
  [ "${HARNESS_MODE:-}" = "docker-harness-simulation" ] &&
    [ "${HARNESS_ENVIRONMENT:-}" = "jenkins-controller-target" ] &&
    [ "$JENKINS_VERIFICATION_MODE" = "docker-harness-simulation" ]
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
  die "$command_name mutates Jenkins controller target state; rerun with --yes after reviewing the env file"
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
  text="${text//\{\{JENKINS_HOME\}\}/$JENKINS_HOME}"
  text="${text//\{\{JENKINS_HTTP_PORT\}\}/$JENKINS_HTTP_PORT}"
  text="${text//\{\{JENKINS_RUNTIME_ACCOUNT\}\}/$JENKINS_RUNTIME_ACCOUNT}"
  text="${text//\{\{JENKINS_URL\}\}/$JENKINS_URL}"
  text="${text//\{\{LDAP_URL\}\}/$LDAP_URL}"
  text="${text//\{\{LDAP_BIND_DN\}\}/$LDAP_BIND_DN}"
  text="${text//\{\{LDAP_USER_BASE\}\}/$LDAP_USER_BASE}"
  text="${text//\{\{LDAP_GROUP_BASE\}\}/$LDAP_GROUP_BASE}"
  text="${text//\{\{GERRIT_HTTP_URL\}\}/$GERRIT_HTTP_URL}"
  text="${text//\{\{GERRIT_SSH_HOST\}\}/$GERRIT_SSH_HOST}"
  text="${text//\{\{GERRIT_SSH_PORT\}\}/$GERRIT_SSH_PORT}"
  text="${text//\{\{GERRIT_TRIGGER_SERVER_NAME\}\}/$GERRIT_TRIGGER_SERVER_NAME}"
  text="${text//\{\{JENKINS_GERRIT_INTEGRATION_ACCOUNT\}\}/$JENKINS_GERRIT_INTEGRATION_ACCOUNT}"
  text="${text//\{\{JENKINS_GERRIT_CREDENTIAL_ID\}\}/$JENKINS_GERRIT_CREDENTIAL_ID}"
  text="${text//\{\{JENKINS_AGENT_HOST\}\}/$JENKINS_AGENT_HOST}"
  text="${text//\{\{JENKINS_AGENT_SSH_PORT\}\}/$JENKINS_AGENT_SSH_PORT}"
  text="${text//\{\{JENKINS_AGENT_ACCOUNT\}\}/$JENKINS_AGENT_ACCOUNT}"
  text="${text//\{\{JENKINS_AGENT_LABEL\}\}/$JENKINS_AGENT_LABEL}"
  text="${text//\{\{JENKINS_AGENT_REMOTE_FS\}\}/$JENKINS_AGENT_REMOTE_FS}"
  text="${text//\{\{JENKINS_AGENT_KNOWN_HOSTS_FILE\}\}/$JENKINS_AGENT_KNOWN_HOSTS_FILE}"
  text="${text//\{\{JENKINS_AGENT_CREDENTIAL_ID\}\}/$JENKINS_AGENT_CREDENTIAL_ID}"
  text="${text//\{\{GERRIT_VERIFICATION_PROJECT\}\}/$GERRIT_VERIFICATION_PROJECT}"
  text="${text//\{\{GERRIT_VERIFICATION_BRANCH\}\}/$GERRIT_VERIFICATION_BRANCH}"
  text="${text//\{\{VERIFICATION_RUN_ID\}\}/$VERIFICATION_RUN_ID}"
  text="${text//\{\{VERIFICATION_MODE\}\}/$JENKINS_VERIFICATION_MODE}"
  text="${text//\{\{VERIFICATION_SUCCESS_MESSAGE\}\}/Jenkins verification succeeded}"
  text="${text//\{\{VERIFICATION_FAILURE_MESSAGE\}\}/Jenkins verification failed}"
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

validate_plugin_spec() {
  local spec name version
  spec="${1:?plugin spec required}"
  case "$spec" in
    *:*) name="${spec%%:*}"; version="${spec#*:}" ;;
    *) die "JENKINS_PLUGIN_LIST entries must be name:version, got: $spec" ;;
  esac
  case "$name" in
    ""|*[!A-Za-z0-9_.-]*|*/*|*'..'*|.*|*-|*.)
      die "Invalid Jenkins plugin identifier: $name"
      ;;
  esac
  case "$version" in
    ""|*[!A-Za-z0-9_.+-]*|*/*|*'..'*|.*|*-|*.)
      die "Invalid Jenkins plugin version for $name: $version"
      ;;
  esac
}

validate_plugins() {
  for_each_csv_value "$JENKINS_PLUGIN_LIST" validate_plugin_spec "JENKINS_PLUGIN_LIST"
}

plugin_name() {
  printf '%s\n' "${1%%:*}"
}

plugin_version() {
  printf '%s\n' "${1#*:}"
}

write_plugin_artifact() {
  local spec name version
  spec="${1:?plugin spec required}"
  name="$(plugin_name "$spec")"
  version="$(plugin_version "$spec")"
  write_text_file "$JENKINS_ARTIFACT_OUTPUT_DIR/plugins/${name}.jpi" \
    "Jenkins plugin marker: $name version $version for Jenkins 2.555.3."
}

validate_os_dependency_identifier() {
  local package
  package="${1:?package required}"
  case "$package" in
    *[!a-z0-9+.-]*|.*|*-|*.)
      die "Invalid Jenkins controller OS dependency identifier: $package"
      ;;
  esac
}

validate_os_dependencies() {
  for_each_csv_value "$JENKINS_OS_DEPENDENCIES" validate_os_dependency_identifier "JENKINS_OS_DEPENDENCIES"
}

check_os_dependency_command() {
  local package command_name
  package="${1:?package required}"
  case "$package" in
    ca-certificates) command_name="update-ca-certificates" ;;
    curl) command_name="curl" ;;
    fontconfig) command_name="fc-cache" ;;
    git) command_name="git" ;;
    net-tools) command_name="netstat" ;;
    netcat-openbsd) command_name="nc" ;;
    openjdk-21-jre|openjdk-21-jre-headless) command_name="java" ;;
    openssh-client) command_name="ssh" ;;
    rsync) command_name="rsync" ;;
    tar) command_name="tar" ;;
    unzip) command_name="unzip" ;;
    wget) command_name="wget" ;;
    *) return 0 ;;
  esac
  if ! command -v "$command_name" >/dev/null 2>&1; then
    if is_docker_harness_simulation; then
      return 0
    fi
    die "Missing Jenkins controller OS dependency command '$command_name' for package '$package'"
  fi
}

check_os_dependency_expectations() {
  validate_os_dependencies
  for_each_csv_value "$JENKINS_OS_DEPENDENCIES" check_os_dependency_command "JENKINS_OS_DEPENDENCIES"
}

validate_artifact_output_dir() {
  local dir repo_generated allowed_harness allowed_repo base suffix
  dir="${JENKINS_ARTIFACT_OUTPUT_DIR:-}"
  repo_generated="$repo_root/simulation/state/generated-artifacts/jenkins-controller"
  allowed_harness="/harness/state/artifacts/jenkins-controller"
  allowed_repo="$repo_generated"
  [ -n "$dir" ] || die "JENKINS_ARTIFACT_OUTPUT_DIR must not be empty"
  case "$dir" in
    /*) ;;
    *) die "JENKINS_ARTIFACT_OUTPUT_DIR must be an absolute path: $dir" ;;
  esac
  case "$dir" in
    *"/../"*|*"/.."|"../"*|".."|*"//"*)
      die "Unsafe JENKINS_ARTIFACT_OUTPUT_DIR path traversal or repeated slash: $dir"
      ;;
  esac
  case "$dir" in
    /|/tmp|/tmp/*|/var|/var/*|/etc|/etc/*|/usr|/usr/*|/home|/home/*|"$HOME"|"$HOME"/*|"$repo_root"|"$repo_root"/*)
      case "$dir" in
        "$allowed_repo"|"$allowed_repo"/*)
          ;;
        *)
          die "Unsafe JENKINS_ARTIFACT_OUTPUT_DIR for prepare-artifacts: $dir"
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
            die "Unsafe JENKINS_ARTIFACT_OUTPUT_DIR suffix: $dir"
            ;;
        esac
        return 0
        ;;
    esac
  done
  die "JENKINS_ARTIFACT_OUTPUT_DIR must be under $allowed_harness or $allowed_repo"
}

verify_staged_artifacts() {
  local manifest checksums
  manifest="$JENKINS_STAGED_ARTIFACT_DIR/manifest.txt"
  checksums="$JENKINS_STAGED_ARTIFACT_DIR/checksums.sha256"
  [ -f "$manifest" ] || die "Missing staged Jenkins controller manifest: $manifest"
  [ -f "$checksums" ] || die "Missing staged Jenkins controller checksums: $checksums"
  (cd "$JENKINS_STAGED_ARTIFACT_DIR" && sha256sum -c checksums.sha256) >/dev/null
  awk -F= '
    $1 == "harness_manifest_version" && $2 == "1" { h=1 }
    $1 == "role" && $2 == "jenkins-controller" { r=1 }
    $1 == "gerrit_version" && $2 == "not-applicable" { g=1 }
    $1 == "jenkins_version" && $2 == "2.555.3" { jn=1 }
    $1 == "jenkins_plugin_manager_version" && $2 == "2.15.0" { pm=1 }
    $1 == "java_version" && $2 == "21" { j=1 }
    $1 == "ubuntu_release" && $2 == "24.04" { u=1 }
    $1 == "ubuntu_codename" && $2 == "noble" { n=1 }
    END { exit !(h && r && g && jn && pm && j && u && n) }
  ' "$manifest" || die "Staged manifest does not match the Jenkins controller Version Baseline"
}

cmd_preflight() {
  load_env normal
  require_env_values
  require_command sha256sum
  require_command ssh-keygen
  require_command awk
  require_command sed
  require_command perl
  validate_plugins
  validate_os_dependencies
  require_account_separation
  if [ "$dry_run" -eq 0 ]; then
    check_os_dependency_expectations
  fi
  [ "$JENKINS_VERSION" = "2.555.3" ] || die "Jenkins controller baseline must be 2.555.3 unless the reviewed baseline is updated"
  [ "$JENKINS_JAVA_VERSION" = "21" ] || die "Jenkins Java baseline must be OpenJDK 21"
  [ "$JENKINS_PLUGIN_MANAGER_VERSION" = "2.15.0" ] || die "Jenkins Plugin Installation Manager baseline must be 2.15.0"
  [ "$JENKINS_UBUNTU_RELEASE" = "24.04" ] || die "Ubuntu release baseline must be 24.04"
  [ "$JENKINS_UBUNTU_CODENAME" = "noble" ] || die "Ubuntu codename baseline must be noble"
  printf 'status=pass command=preflight dry_run=%s env=%s host=%s http_port=%s mode=%s plugins=curated\n' \
    "$dry_run" "${env_file:-$default_env_file}" "$JENKINS_HOST" "$JENKINS_HTTP_PORT" "$JENKINS_VERIFICATION_MODE"
}

write_manifest() {
  local manifest
  manifest="$JENKINS_ARTIFACT_OUTPUT_DIR/manifest.txt"
  cat >"$manifest" <<EOF
harness_manifest_version=1
role=jenkins-controller
ubuntu_release=24.04
ubuntu_codename=noble
java_version=21
gerrit_version=not-applicable
jenkins_version=2.555.3
jenkins_plugin_manager_version=2.15.0
artifact_source=curated-bundle-factory
public_internet_fallback=simulation-only
plugins=$JENKINS_PLUGIN_LIST
war=jenkins-2.555.3.war
plugin_manager=jenkins-plugin-manager-2.15.0.jar
EOF
}

cmd_prepare_artifacts() {
  load_env normal
  apply_env_defaults
  require_command sha256sum
  validate_plugins
  validate_artifact_output_dir
  rm -rf "$JENKINS_ARTIFACT_OUTPUT_DIR"
  mkdir -p "$JENKINS_ARTIFACT_OUTPUT_DIR/plugins" "$JENKINS_ARTIFACT_OUTPUT_DIR/templates"
  write_text_file "$JENKINS_ARTIFACT_OUTPUT_DIR/jenkins-2.555.3.war" \
    "Jenkins 2.555.3 curated controller artifact marker for Docker harness validation."
  write_text_file "$JENKINS_ARTIFACT_OUTPUT_DIR/jenkins-plugin-manager-2.15.0.jar" \
    "Jenkins Plugin Installation Manager 2.15.0 curated artifact marker."
  for_each_csv_value "$JENKINS_PLUGIN_LIST" write_plugin_artifact "JENKINS_PLUGIN_LIST"
  cp "$repo_root/templates/jenkins-controller/jenkins-service.env.template" "$JENKINS_ARTIFACT_OUTPUT_DIR/templates/jenkins-service.env.template"
  cp "$repo_root/templates/jenkins-controller/jenkins-jcasc.yaml.template" "$JENKINS_ARTIFACT_OUTPUT_DIR/templates/jenkins-jcasc.yaml.template"
  cp "$repo_root/templates/jenkins-controller/jenkins-credentials.yaml.template" "$JENKINS_ARTIFACT_OUTPUT_DIR/templates/jenkins-credentials.yaml.template"
  cp "$repo_root/templates/jenkins-controller/gerrit-trigger-server.yaml.template" "$JENKINS_ARTIFACT_OUTPUT_DIR/templates/gerrit-trigger-server.yaml.template"
  cp "$repo_root/templates/jenkins-controller/agent-node.yaml.template" "$JENKINS_ARTIFACT_OUTPUT_DIR/templates/agent-node.yaml.template"
  cp "$repo_root/templates/jenkins-controller/disposable-verification-job.yaml.template" "$JENKINS_ARTIFACT_OUTPUT_DIR/templates/disposable-verification-job.yaml.template"
  cp "$repo_root/templates/jenkins-controller/trigger-verification.env.template" "$JENKINS_ARTIFACT_OUTPUT_DIR/templates/trigger-verification.env.template"
  write_manifest
  (
    cd "$JENKINS_ARTIFACT_OUTPUT_DIR"
    rm -f checksums.sha256
    find . -type f ! -name checksums.sha256 -print0 |
      sort -z |
      xargs -0 sha256sum >checksums.sha256
  )
  printf 'status=pass command=prepare-artifacts artifact_dir=%s manifest=%s checksums=%s plugins=curated\n' \
    "$JENKINS_ARTIFACT_OUTPUT_DIR" "$JENKINS_ARTIFACT_OUTPUT_DIR/manifest.txt" "$JENKINS_ARTIFACT_OUTPUT_DIR/checksums.sha256"
}

cmd_install() {
  load_env normal
  require_env_values
  confirm_mutation install || return 0
  verify_staged_artifacts
  ensure_dirs
  mkdir -p "$JENKINS_HOME/war" "$JENKINS_HOME/plugins" "$JENKINS_HOME/templates" "$JENKINS_HOME/state" "$JENKINS_HOME/logs"
  cp "$JENKINS_STAGED_ARTIFACT_DIR/jenkins-2.555.3.war" "$JENKINS_HOME/war/jenkins.war"
  cp "$JENKINS_STAGED_ARTIFACT_DIR/jenkins-plugin-manager-2.15.0.jar" "$JENKINS_HOME/war/jenkins-plugin-manager.jar"
  cp -R "$JENKINS_STAGED_ARTIFACT_DIR/templates/." "$JENKINS_HOME/templates/"
  cp "$JENKINS_STAGED_ARTIFACT_DIR/manifest.txt" "$JENKINS_HOME/artifact-manifest.txt"
  cp "$JENKINS_STAGED_ARTIFACT_DIR/checksums.sha256" "$JENKINS_HOME/artifact-checksums.sha256"
  write_text_file "$JENKINS_HOME/state/install.status" "installed"
  printf 'status=pass command=install home=%s staged=%s\n' "$JENKINS_HOME" "$JENKINS_STAGED_ARTIFACT_DIR"
}

start_observable_service() {
  local service_script pidfile log_file war_sha jcasc_sha plugin_digest agent_digest trigger_digest pid
  require_docker_harness_simulation
  service_script="$JENKINS_HOME/bin/jenkins-observable-service.pl"
  pidfile="$JENKINS_HOME/run/jenkins-observable.pid"
  log_file="$JENKINS_HOME/logs/jenkins-observable.log"
  mkdir -p "$JENKINS_HOME/bin" "$JENKINS_HOME/run" "$JENKINS_HOME/logs"
  war_sha="$(sha256_file "$JENKINS_HOME/war/jenkins.war")"
  jcasc_sha="$(sha256_file "$JENKINS_HOME/jcasc/jenkins.yaml")"
  plugin_digest="$(plugin_set_digest)"
  agent_digest="$(sha256_file "$JENKINS_HOME/nodes/$JENKINS_AGENT_LABEL.yaml")"
  trigger_digest="$(sha256_file "$JENKINS_HOME/gerrit-trigger/server.yaml")"
  {
    printf 'timestamp=%s\n' "$(iso_timestamp_utc)"
    printf 'service=jenkins-controller-observable\n'
    printf 'mode=docker-harness-simulation\n'
    printf 'war_sha256=%s\n' "$war_sha"
    printf 'jcasc_sha256=%s\n' "$jcasc_sha"
    printf 'plugin_set_digest=%s\n' "$plugin_digest"
    printf 'agent_digest=%s\n' "$agent_digest"
    printf 'trigger_digest=%s\n' "$trigger_digest"
  } >"$log_file"
  cat >"$service_script" <<'PERL'
#!/usr/bin/env perl
use strict;
use warnings;
use IO::Socket::INET;
use IO::Handle;

my ($http_port, $war_sha, $jcasc_sha, $plugin_digest, $agent_digest, $trigger_digest) = @ARGV;
my $listener = IO::Socket::INET->new(
  LocalAddr => '0.0.0.0',
  LocalPort => $http_port,
  Proto => 'tcp',
  Listen => 16,
  ReuseAddr => 1,
) or die "jenkins http listen failed: $!";

while (my $client = $listener->accept()) {
  $client->autoflush(1);
  print {$client} "HTTP/1.1 200 OK\r\n";
  print {$client} "X-Jenkins: 2.555.3\r\n";
  print {$client} "Content-Type: text/plain\r\n";
  print {$client} "Connection: close\r\n\r\n";
  print {$client} "Jenkins 2.555.3\n";
  print {$client} "war_sha256=$war_sha\n";
  print {$client} "jcasc_sha256=$jcasc_sha\n";
  print {$client} "plugin_set_digest=$plugin_digest\n";
  print {$client} "agent_digest=$agent_digest\n";
  print {$client} "trigger_digest=$trigger_digest\n";
  close $client;
}
PERL
  chmod +x "$service_script"
  if [ -f "$pidfile" ] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
    kill "$(cat "$pidfile")" 2>/dev/null || true
  fi
  "$service_script" "$JENKINS_HTTP_PORT" "$war_sha" "$jcasc_sha" "$plugin_digest" "$agent_digest" "$trigger_digest" >>"$log_file" 2>&1 &
  pid="$!"
  printf '%s\n' "$pid" >"$pidfile"
  sleep 1
  if ! kill -0 "$pid" 2>/dev/null; then
    die "Jenkins observable service failed to start; log=$log_file"
  fi
}

cmd_configure_service() {
  load_env normal
  require_env_values
  confirm_mutation configure-service || return 0
  verify_staged_artifacts
  ensure_dirs
  mkdir -p "$JENKINS_HOME/etc" "$JENKINS_HOME/state"
  render_template "$JENKINS_STAGED_ARTIFACT_DIR/templates/jenkins-service.env.template" "$JENKINS_HOME/etc/jenkins-service.env"
  assert_no_unresolved_placeholders "$JENKINS_HOME/etc/jenkins-service.env"
  write_text_file "$JENKINS_HOME/state/service-configured.status" \
    "runtime_account=$JENKINS_RUNTIME_ACCOUNT port=$JENKINS_HTTP_PORT controller_executors=0"
  printf 'status=pass command=configure-service service_env=%s runtime_account=%s\n' \
    "$JENKINS_HOME/etc/jenkins-service.env" "$JENKINS_RUNTIME_ACCOUNT"
}

cmd_install_plugins() {
  load_env normal
  require_env_values
  confirm_mutation install-plugins || return 0
  verify_staged_artifacts
  mkdir -p "$JENKINS_HOME/plugins" "$JENKINS_HOME/state"
  cp -R "$JENKINS_STAGED_ARTIFACT_DIR/plugins/." "$JENKINS_HOME/plugins/"
  plugin_set_digest >/dev/null
  write_text_file "$JENKINS_HOME/state/plugins.status" "installed plugins=$JENKINS_PLUGIN_LIST digest=$(plugin_set_digest)"
  printf 'status=pass command=install-plugins plugin_digest=%s\n' "$(plugin_set_digest)"
}

cmd_configure_jcasc() {
  load_env normal
  require_env_values
  confirm_mutation configure-jcasc || return 0
  verify_staged_artifacts
  mkdir -p "$JENKINS_HOME/jcasc" "$JENKINS_HOME/state"
  render_template "$JENKINS_STAGED_ARTIFACT_DIR/templates/jenkins-jcasc.yaml.template" "$JENKINS_HOME/jcasc/jenkins.yaml"
  assert_no_unresolved_placeholders "$JENKINS_HOME/jcasc/jenkins.yaml"
  grep -Fq -- 'numExecutors: 0' "$JENKINS_HOME/jcasc/jenkins.yaml" || die "JCasC must keep built-in node executors at zero"
  grep -Fq -- 'ldap:' "$JENKINS_HOME/jcasc/jenkins.yaml" || die "JCasC LDAP security realm is missing"
  write_text_file "$JENKINS_HOME/state/jcasc.status" "configured ldap=$LDAP_URL admin_group=$JENKINS_ADMIN_GROUP"
  printf 'status=pass command=configure-jcasc jcasc=%s ldap=configured\n' "$JENKINS_HOME/jcasc/jenkins.yaml"
}

generate_keypair() {
  local private_file comment public_file
  private_file="${1:?private key file required}"
  comment="${2:?comment required}"
  public_file="${private_file}.pub"
  mkdir -p "$(dirname "$private_file")"
  rm -f "$private_file" "$public_file"
  ssh-keygen -q -t ed25519 -N '' -C "$comment" -f "$private_file"
  chmod 0600 "$private_file"
  chmod 0644 "$public_file"
}

cmd_generate_integration_key() {
  load_env normal
  require_env_values
  confirm_mutation generate-integration-key || return 0
  verify_staged_artifacts
  require_command ssh-keygen
  generate_keypair "$JENKINS_GERRIT_PRIVATE_KEY_FILE" "$JENKINS_GERRIT_INTEGRATION_ACCOUNT"
  mkdir -p "$(dirname "$JENKINS_GERRIT_PUBLIC_KEY_FILE")"
  cp "${JENKINS_GERRIT_PRIVATE_KEY_FILE}.pub" "$JENKINS_GERRIT_PUBLIC_KEY_FILE"
  validate_private_key_file "$JENKINS_GERRIT_PRIVATE_KEY_FILE"
  validate_public_key_file "$JENKINS_GERRIT_PUBLIC_KEY_FILE"
  write_text_file "$JENKINS_HOME/state/gerrit-key.status" "public_key=$JENKINS_GERRIT_PUBLIC_KEY_FILE fingerprint=$(public_key_fingerprint "$JENKINS_GERRIT_PUBLIC_KEY_FILE")"
  printf 'status=pass command=generate-integration-key public_key=%s fingerprint=%s private_key=redacted\n' \
    "$JENKINS_GERRIT_PUBLIC_KEY_FILE" "$(public_key_fingerprint "$JENKINS_GERRIT_PUBLIC_KEY_FILE")"
}

cmd_generate_agent_key() {
  load_env normal
  require_env_values
  confirm_mutation generate-agent-key || return 0
  verify_staged_artifacts
  require_command ssh-keygen
  generate_keypair "$JENKINS_AGENT_PRIVATE_KEY_FILE" "$JENKINS_AGENT_ACCOUNT"
  mkdir -p "$(dirname "$JENKINS_AGENT_PUBLIC_KEY_FILE")"
  cp "${JENKINS_AGENT_PRIVATE_KEY_FILE}.pub" "$JENKINS_AGENT_PUBLIC_KEY_FILE"
  validate_private_key_file "$JENKINS_AGENT_PRIVATE_KEY_FILE"
  validate_public_key_file "$JENKINS_AGENT_PUBLIC_KEY_FILE"
  write_text_file "$JENKINS_HOME/state/agent-key.status" "public_key=$JENKINS_AGENT_PUBLIC_KEY_FILE fingerprint=$(public_key_fingerprint "$JENKINS_AGENT_PUBLIC_KEY_FILE")"
  printf 'status=pass command=generate-agent-key public_key=%s fingerprint=%s private_key=redacted\n' \
    "$JENKINS_AGENT_PUBLIC_KEY_FILE" "$(public_key_fingerprint "$JENKINS_AGENT_PUBLIC_KEY_FILE")"
}

cmd_configure_integration() {
  load_env normal
  require_env_values
  confirm_mutation configure-integration || return 0
  verify_staged_artifacts
  validate_private_key_file "$JENKINS_GERRIT_PRIVATE_KEY_FILE"
  validate_public_key_file "$JENKINS_GERRIT_PUBLIC_KEY_FILE"
  mkdir -p "$JENKINS_HOME/credentials" "$JENKINS_HOME/gerrit-trigger" "$JENKINS_HOME/state"
  render_template "$JENKINS_STAGED_ARTIFACT_DIR/templates/jenkins-credentials.yaml.template" "$JENKINS_HOME/credentials/credentials.yaml"
  render_template "$JENKINS_STAGED_ARTIFACT_DIR/templates/gerrit-trigger-server.yaml.template" "$JENKINS_HOME/gerrit-trigger/server.yaml"
  assert_no_unresolved_placeholders "$JENKINS_HOME/credentials/credentials.yaml"
  assert_no_unresolved_placeholders "$JENKINS_HOME/gerrit-trigger/server.yaml"
  grep -Fq -- "$JENKINS_GERRIT_CREDENTIAL_ID" "$JENKINS_HOME/gerrit-trigger/server.yaml" || die "Gerrit Trigger credential ID is missing"
  grep -Fq -- "$JENKINS_GERRIT_INTEGRATION_ACCOUNT" "$JENKINS_HOME/gerrit-trigger/server.yaml" || die "Gerrit Trigger integration account is missing"
  write_text_file "$JENKINS_HOME/state/gerrit-trigger.status" \
    "server=$GERRIT_TRIGGER_SERVER_NAME account=$JENKINS_GERRIT_INTEGRATION_ACCOUNT credential=$JENKINS_GERRIT_CREDENTIAL_ID ssh=$GERRIT_SSH_HOST:$GERRIT_SSH_PORT"
  printf 'status=pass command=configure-integration server=%s account=%s credential=%s\n' \
    "$GERRIT_TRIGGER_SERVER_NAME" "$JENKINS_GERRIT_INTEGRATION_ACCOUNT" "$JENKINS_GERRIT_CREDENTIAL_ID"
}

cmd_configure_agent() {
  load_env normal
  require_env_values
  confirm_mutation configure-agent || return 0
  verify_staged_artifacts
  validate_private_key_file "$JENKINS_AGENT_PRIVATE_KEY_FILE"
  validate_public_key_file "$JENKINS_AGENT_PUBLIC_KEY_FILE"
  mkdir -p "$JENKINS_HOME/nodes" "$JENKINS_HOME/state"
  render_template "$JENKINS_STAGED_ARTIFACT_DIR/templates/agent-node.yaml.template" "$JENKINS_HOME/nodes/$JENKINS_AGENT_LABEL.yaml"
  assert_no_unresolved_placeholders "$JENKINS_HOME/nodes/$JENKINS_AGENT_LABEL.yaml"
  grep -Fq -- "$JENKINS_AGENT_CREDENTIAL_ID" "$JENKINS_HOME/nodes/$JENKINS_AGENT_LABEL.yaml" || die "Agent credential ID is missing from node config"
  write_text_file "$JENKINS_HOME/state/agent-configured.status" \
    "agent=$JENKINS_AGENT_HOST label=$JENKINS_AGENT_LABEL credential=$JENKINS_AGENT_CREDENTIAL_ID remote_fs=$JENKINS_AGENT_REMOTE_FS"
  printf 'status=pass command=configure-agent host=%s label=%s credential=%s\n' \
    "$JENKINS_AGENT_HOST" "$JENKINS_AGENT_LABEL" "$JENKINS_AGENT_CREDENTIAL_ID"
}

ldap_host_port() {
  local target host port
  target="${LDAP_URL#ldap://}"
  target="${target#ldaps://}"
  target="${target%%/*}"
  host="${target%%:*}"
  port="${target##*:}"
  if [ "$port" = "$target" ]; then
    port="389"
  fi
  printf '%s %s\n' "$host" "$port"
}

check_tcp_connect() {
  local host port
  host="${1:?host required}"
  port="${2:?port required}"
  timeout 5 bash -c 'exec 3<>"/dev/tcp/$0/$1"' "$host" "$port"
}

tcp_exchange() {
  local host port request
  host="${1:?host required}"
  port="${2:?port required}"
  request="${3:?request required}"
  timeout 5 bash -c 'exec 3<>"/dev/tcp/$0/$1"; printf "%s\n" "$2" >&3; IFS= read -r line <&3; printf "%s\n" "$line"' "$host" "$port" "$request"
}

check_http_endpoint() {
  local response attempt
  response=""
  for attempt in 1 2 3 4 5; do
    response="$(timeout 5 bash -c 'exec 3<>"/dev/tcp/$0/$1"; printf "GET /login HTTP/1.0\r\nHost: $0\r\n\r\n" >&3; cat <&3 2>/dev/null || true' "$JENKINS_HOST" "$JENKINS_HTTP_PORT" || true)"
    if grep -Fq -- 'HTTP/1.1 200 OK' <<<"$response" &&
      grep -Fq -- 'X-Jenkins: 2.555.3' <<<"$response"; then
      printf '%s\n' "$response"
      return 0
    fi
    sleep 1
  done
  grep -Fq -- 'HTTP/1.1 200 OK' <<<"$response" || die "Jenkins HTTP endpoint did not return 200"
  grep -Fq -- 'X-Jenkins: 2.555.3' <<<"$response" || die "Jenkins HTTP endpoint did not report Jenkins 2.555.3"
}

response_field() {
  local field response
  field="${1:?field required}"
  response="${2:?response required}"
  awk -F= -v field="$field" '$1 == field { print substr($0, length(field) + 2); found = 1; exit } END { exit !found }' <<<"$response"
}

check_observable_service_matches_install() {
  local response reported_war reported_jcasc reported_plugins reported_agent reported_trigger
  require_docker_harness_simulation
  response="$(check_http_endpoint)"
  reported_war="$(response_field war_sha256 "$response")" || die "Observable service did not report war_sha256"
  reported_jcasc="$(response_field jcasc_sha256 "$response")" || die "Observable service did not report jcasc_sha256"
  reported_plugins="$(response_field plugin_set_digest "$response")" || die "Observable service did not report plugin_set_digest"
  reported_agent="$(response_field agent_digest "$response")" || die "Observable service did not report agent_digest"
  reported_trigger="$(response_field trigger_digest "$response")" || die "Observable service did not report trigger_digest"
  [ "$reported_war" = "$(sha256_file "$JENKINS_HOME/war/jenkins.war")" ] || die "Observable service WAR hash does not match installed Jenkins WAR"
  [ "$reported_jcasc" = "$(sha256_file "$JENKINS_HOME/jcasc/jenkins.yaml")" ] || die "Observable service JCasC hash does not match installed config"
  [ "$reported_plugins" = "$(plugin_set_digest)" ] || die "Observable service plugin digest does not match installed plugins"
  [ "$reported_agent" = "$(sha256_file "$JENKINS_HOME/nodes/$JENKINS_AGENT_LABEL.yaml")" ] || die "Observable service agent digest does not match node config"
  [ "$reported_trigger" = "$(sha256_file "$JENKINS_HOME/gerrit-trigger/server.yaml")" ] || die "Observable service trigger digest does not match Gerrit Trigger config"
}

check_ldap_access() {
  local host port
  read -r host port <<EOF
$(ldap_host_port)
EOF
  check_tcp_connect "$host" "$port" || die "LDAP endpoint is not reachable: $host:$port"
}

check_gerrit_ssh_connectivity() {
  check_tcp_connect "$GERRIT_SSH_HOST" "$GERRIT_SSH_PORT" || die "Gerrit SSH endpoint is not reachable: $GERRIT_SSH_HOST:$GERRIT_SSH_PORT"
}

check_plugin_readiness() {
  local spec name missing
  validate_plugins
  missing=0
  for spec in ${JENKINS_PLUGIN_LIST//,/ }; do
    name="$(plugin_name "$spec")"
    [ -f "$JENKINS_HOME/plugins/${name}.jpi" ] || missing=1
  done
  [ "$missing" -eq 0 ] || die "One or more curated Jenkins plugins are not installed"
  [ -s "$JENKINS_HOME/state/plugins.status" ] || die "Plugin readiness marker is missing"
}

check_jcasc_readiness() {
  [ -s "$JENKINS_HOME/jcasc/jenkins.yaml" ] || die "JCasC file is missing"
  grep -Fq -- 'ldap:' "$JENKINS_HOME/jcasc/jenkins.yaml" || die "JCasC LDAP realm is missing"
  grep -Fq -- 'numExecutors: 0' "$JENKINS_HOME/jcasc/jenkins.yaml" || die "JCasC built-in executor policy is missing"
}

check_gerrit_trigger_readiness() {
  [ -s "$JENKINS_HOME/gerrit-trigger/server.yaml" ] || die "Gerrit Trigger server config is missing"
  grep -Fq -- 'gerrit-trigger:' "$JENKINS_HOME/gerrit-trigger/server.yaml" || die "Gerrit Trigger JCasC block is missing"
  grep -Fq -- "$JENKINS_GERRIT_INTEGRATION_ACCOUNT" "$JENKINS_HOME/gerrit-trigger/server.yaml" || die "Gerrit Trigger integration account missing"
  [ -s "$JENKINS_HOME/state/gerrit-trigger.status" ] || die "Gerrit Trigger readiness marker is missing"
}

check_agent_registration() {
  [ -s "$JENKINS_HOME/nodes/$JENKINS_AGENT_LABEL.yaml" ] || die "Jenkins agent node config is missing"
  grep -Fq -- "$JENKINS_AGENT_LABEL" "$JENKINS_HOME/nodes/$JENKINS_AGENT_LABEL.yaml" || die "Jenkins agent label is missing from node config"
  grep -Fq -- "$JENKINS_AGENT_CREDENTIAL_ID" "$JENKINS_HOME/nodes/$JENKINS_AGENT_LABEL.yaml" || die "Jenkins agent credential is missing from node config"
  [ -s "$JENKINS_HOME/state/agent-configured.status" ] || die "Agent configured marker is missing"
}

check_agent_observed_status() {
  local file key_fp node_sha
  file="$JENKINS_HOME/state/agent-validation.status"
  [ -s "$file" ] || die "Step 8 modeled agent validation record is missing"
  key_fp="$(public_key_fingerprint "$JENKINS_AGENT_PUBLIC_KEY_FILE")"
  node_sha="$(sha256_file "$JENKINS_HOME/nodes/$JENKINS_AGENT_LABEL.yaml")"
  grep -Fqx "proof_scope=step8-modeled" "$file" || die "Agent validation is not labeled step8-modeled"
  grep -Fqx "verification_mode=simulation-only" "$file" || die "Agent validation is not labeled simulation-only"
  grep -Fqx "real_execution=false" "$file" || die "Agent validation must state real_execution=false"
  grep -Fqx "step11_required_for_real_execution=true" "$file" || die "Agent validation must defer real execution to Step 11"
  grep -Fqx "run_id=$VERIFICATION_RUN_ID" "$file" || die "Agent validation run ID mismatch"
  grep -Fqx "label=$JENKINS_AGENT_LABEL" "$file" || die "Agent validation label mismatch"
  grep -Fqx "account=$JENKINS_AGENT_ACCOUNT" "$file" || die "Agent validation account mismatch"
  grep -Fqx "public_key_fingerprint=$key_fp" "$file" || die "Agent validation key fingerprint mismatch"
  grep -Fqx "node_config_sha256=$node_sha" "$file" || die "Agent validation node config hash mismatch"
  grep -Fqx "modeled_scheduling=pass" "$file" || die "Modeled agent scheduling result is missing"
}

check_trigger_observed_status() {
  local file gerrit_key_fp agent_key_fp node_sha trigger_sha
  file="$JENKINS_HOME/state/trigger-verification.status"
  [ -s "$file" ] || die "Step 8 modeled trigger verification record is missing"
  gerrit_key_fp="$(public_key_fingerprint "$JENKINS_GERRIT_PUBLIC_KEY_FILE")"
  agent_key_fp="$(public_key_fingerprint "$JENKINS_AGENT_PUBLIC_KEY_FILE")"
  node_sha="$(sha256_file "$JENKINS_HOME/nodes/$JENKINS_AGENT_LABEL.yaml")"
  trigger_sha="$(sha256_file "$JENKINS_HOME/gerrit-trigger/server.yaml")"
  grep -Fqx "proof_scope=step8-modeled" "$file" || die "Trigger verification is not labeled step8-modeled"
  grep -Fqx "verification_mode=simulation-only" "$file" || die "Trigger verification is not labeled simulation-only"
  grep -Fqx "real_execution=false" "$file" || die "Trigger verification must state real_execution=false"
  grep -Fqx "step11_required_for_real_execution=true" "$file" || die "Trigger verification must defer real execution to Step 11"
  grep -Fqx "run_id=$VERIFICATION_RUN_ID" "$file" || die "Trigger verification run ID mismatch"
  grep -Fqx "project=$GERRIT_VERIFICATION_PROJECT" "$file" || die "Trigger verification project mismatch"
  grep -Fqx "branch=$GERRIT_VERIFICATION_BRANCH" "$file" || die "Trigger verification branch mismatch"
  grep -Fqx "agent_label=$JENKINS_AGENT_LABEL" "$file" || die "Trigger verification agent label mismatch"
  grep -Fqx "gerrit_public_key_fingerprint=$gerrit_key_fp" "$file" || die "Trigger verification Gerrit key fingerprint mismatch"
  grep -Fqx "agent_public_key_fingerprint=$agent_key_fp" "$file" || die "Trigger verification agent key fingerprint mismatch"
  grep -Fqx "node_config_sha256=$node_sha" "$file" || die "Trigger verification node config hash mismatch"
  grep -Fqx "trigger_config_sha256=$trigger_sha" "$file" || die "Trigger verification config hash mismatch"
  grep -Fqx "modeled_patchset_created=pass" "$file" || die "Modeled patchset-created result is missing"
  grep -Fqx "modeled_agent_build=pass" "$file" || die "Modeled agent build result is missing"
  grep -Fqx "modeled_verified_vote=pass" "$file" || die "Modeled Verified vote result is missing"
}

verify_base_readiness_facts() {
  verify_staged_artifacts
  [ -s "$JENKINS_HOME/state/install.status" ] || die "Install marker missing"
  [ -s "$JENKINS_HOME/state/service-configured.status" ] || die "Service configuration marker missing"
  [ -s "$JENKINS_HOME/war/jenkins.war" ] || die "Jenkins WAR is not installed"
  [ -s "$JENKINS_HOME/war/jenkins-plugin-manager.jar" ] || die "Jenkins plugin manager is not installed"
  check_plugin_readiness
  check_jcasc_readiness
  validate_private_key_file "$JENKINS_GERRIT_PRIVATE_KEY_FILE"
  validate_public_key_file "$JENKINS_GERRIT_PUBLIC_KEY_FILE"
  validate_private_key_file "$JENKINS_AGENT_PRIVATE_KEY_FILE"
  validate_public_key_file "$JENKINS_AGENT_PUBLIC_KEY_FILE"
  check_gerrit_trigger_readiness
  check_agent_registration
  check_agent_observed_status
  check_trigger_observed_status
  check_ldap_access
  check_gerrit_ssh_connectivity
}

cmd_validate_agent() {
  local key_fp node_sha
  load_env normal
  require_env_values
  confirm_mutation validate-agent || return 0
  verify_staged_artifacts
  check_agent_registration
  validate_private_key_file "$JENKINS_AGENT_PRIVATE_KEY_FILE"
  validate_public_key_file "$JENKINS_AGENT_PUBLIC_KEY_FILE"
  key_fp="$(public_key_fingerprint "$JENKINS_AGENT_PUBLIC_KEY_FILE")"
  node_sha="$(sha256_file "$JENKINS_HOME/nodes/$JENKINS_AGENT_LABEL.yaml")"
  mkdir -p "$JENKINS_HOME/state"
  {
    printf 'proof_scope=step8-modeled\n'
    printf 'verification_mode=simulation-only\n'
    printf 'real_execution=false\n'
    printf 'step11_required_for_real_execution=true\n'
    printf 'run_id=%s\n' "$VERIFICATION_RUN_ID"
    printf 'label=%s\n' "$JENKINS_AGENT_LABEL"
    printf 'account=%s\n' "$JENKINS_AGENT_ACCOUNT"
    printf 'public_key_fingerprint=%s\n' "$key_fp"
    printf 'node_config_sha256=%s\n' "$node_sha"
    printf 'remote_fs=%s\n' "$JENKINS_AGENT_REMOTE_FS"
    printf 'modeled_scheduling=pass\n'
  } >"$JENKINS_HOME/state/agent-validation.status"
  check_agent_observed_status
  printf 'status=pass command=validate-agent proof=modeled verification_mode=simulation-only real_execution=false step11_required=true label=%s\n' "$JENKINS_AGENT_LABEL"
}

cmd_verify_trigger() {
  local gerrit_key_fp agent_key_fp node_sha trigger_sha modeled_change
  load_env normal
  require_env_values
  confirm_mutation verify-trigger || return 0
  verify_staged_artifacts
  check_gerrit_trigger_readiness
  check_agent_observed_status
  mkdir -p "$JENKINS_HOME/jobs" "$JENKINS_HOME/state"
  render_template "$JENKINS_STAGED_ARTIFACT_DIR/templates/disposable-verification-job.yaml.template" "$JENKINS_HOME/jobs/verification-disposable-${VERIFICATION_RUN_ID}.yaml"
  render_template "$JENKINS_STAGED_ARTIFACT_DIR/templates/trigger-verification.env.template" "$JENKINS_HOME/jobs/trigger-verification-${VERIFICATION_RUN_ID}.env"
  assert_no_unresolved_placeholders "$JENKINS_HOME/jobs/verification-disposable-${VERIFICATION_RUN_ID}.yaml"
  assert_no_unresolved_placeholders "$JENKINS_HOME/jobs/trigger-verification-${VERIFICATION_RUN_ID}.env"
  gerrit_key_fp="$(public_key_fingerprint "$JENKINS_GERRIT_PUBLIC_KEY_FILE")"
  agent_key_fp="$(public_key_fingerprint "$JENKINS_AGENT_PUBLIC_KEY_FILE")"
  node_sha="$(sha256_file "$JENKINS_HOME/nodes/$JENKINS_AGENT_LABEL.yaml")"
  trigger_sha="$(sha256_file "$JENKINS_HOME/gerrit-trigger/server.yaml")"
  modeled_change="modeled-${VERIFICATION_RUN_ID}"
  {
    printf 'proof_scope=step8-modeled\n'
    printf 'verification_mode=simulation-only\n'
    printf 'real_execution=false\n'
    printf 'step11_required_for_real_execution=true\n'
    printf 'run_id=%s\n' "$VERIFICATION_RUN_ID"
    printf 'project=%s\n' "$GERRIT_VERIFICATION_PROJECT"
    printf 'branch=%s\n' "$GERRIT_VERIFICATION_BRANCH"
    printf 'modeled_change=%s\n' "$modeled_change"
    printf 'agent_label=%s\n' "$JENKINS_AGENT_LABEL"
    printf 'gerrit_public_key_fingerprint=%s\n' "$gerrit_key_fp"
    printf 'agent_public_key_fingerprint=%s\n' "$agent_key_fp"
    printf 'node_config_sha256=%s\n' "$node_sha"
    printf 'trigger_config_sha256=%s\n' "$trigger_sha"
    printf 'modeled_patchset_created=pass\n'
    printf 'modeled_agent_build=pass\n'
    printf 'modeled_verified_vote=pass\n'
  } >"$JENKINS_HOME/state/trigger-verification.status"
  check_trigger_observed_status
  if is_docker_harness_simulation; then
    start_observable_service
  fi
  printf 'status=pass command=verify-trigger proof=modeled verification_mode=simulation-only real_execution=false step11_required=true modeled_event=patchset-created modeled_vote=Verified+1 modeled_change=%s\n' "$modeled_change"
}

cmd_validate() {
  load_env normal
  require_env_values
  require_command ssh-keygen
  verify_base_readiness_facts
  [ -f "$JENKINS_HOME/run/jenkins-observable.pid" ] || die "Jenkins observable service pid is missing"
  kill -0 "$(cat "$JENKINS_HOME/run/jenkins-observable.pid")" 2>/dev/null || die "Jenkins observable service process is not running"
  check_observable_service_matches_install
  cmd_collect_evidence >/dev/null
  printf 'status=pass command=validate proof=modeled verification_mode=simulation-only real_execution=false startup=simulation-only endpoint=simulation-only ldap=pass plugins=pass JCasC=pass gerrit_ssh=pass Gerrit_Trigger=modeled agent=modeled trigger_vote=modeled evidence_dir=%s\n' "$JENKINS_EVIDENCE_DIR"
}

cmd_collect_evidence() {
  load_env normal
  apply_env_defaults
  require_env_values
  require_command ssh-keygen
  verify_base_readiness_facts
  [ -f "$JENKINS_HOME/run/jenkins-observable.pid" ] || die "Jenkins observable service pid is missing"
  kill -0 "$(cat "$JENKINS_HOME/run/jenkins-observable.pid")" 2>/dev/null || die "Jenkins observable service process is not running"
  check_observable_service_matches_install
  ensure_dirs
  local evidence input_fingerprint manifest checksum bounded_log service_log agent_status trigger_status gerrit_fp agent_fp
  local q_mode q_time q_role q_checkpoint q_command q_status q_input q_manifest q_checksum q_checks q_log q_redaction q_proof q_real q_step11
  evidence="$JENKINS_EVIDENCE_DIR/jenkins-controller-readiness-$(timestamp_utc).json"
  bounded_log="$JENKINS_LOG_DIR/jenkins-controller-collect-evidence-$(timestamp_utc).log"
  service_log="$JENKINS_HOME/logs/jenkins-observable.log"
  agent_status="$JENKINS_HOME/state/agent-validation.status"
  trigger_status="$JENKINS_HOME/state/trigger-verification.status"
  input_fingerprint="$(printf '%s\n%s\n%s\n%s\n%s\n%s\n' "$JENKINS_HOST" "$JENKINS_HTTP_PORT" "$LDAP_URL" "$GERRIT_SSH_HOST:$GERRIT_SSH_PORT" "$JENKINS_AGENT_HOST" "$JENKINS_AGENT_LABEL" | sha256sum | awk '{print $1}')"
  manifest="$JENKINS_STAGED_ARTIFACT_DIR/manifest.txt"
  checksum="$JENKINS_STAGED_ARTIFACT_DIR/checksums.sha256"
  gerrit_fp="$(public_key_fingerprint "$JENKINS_GERRIT_PUBLIC_KEY_FILE")"
  agent_fp="$(public_key_fingerprint "$JENKINS_AGENT_PUBLIC_KEY_FILE")"
  {
    printf 'timestamp=%s\n' "$(iso_timestamp_utc)"
    printf 'command=collect-evidence\n'
    printf 'proof_scope=step8-modeled\n'
    printf 'verification_mode=simulation-only\n'
    printf 'real_execution=false\n'
    printf 'step11_required_for_real_execution=true\n'
    printf 'artifact_manifest=%s\n' "$manifest"
    printf 'checksum_reference=%s\n' "$checksum"
    printf 'observed=startup-simulation-only,http-simulation-only,ldap,plugins,JCasC,gerrit-ssh,Gerrit Trigger modeled,agent scheduling modeled,patchset-created modeled,agent build modeled,Verified+1 modeled\n'
    printf 'gerrit_public_key_fingerprint=%s\n' "$gerrit_fp"
    printf 'agent_public_key_fingerprint=%s\n' "$agent_fp"
    printf 'redaction=secrets-not-recorded\n'
  } >"$bounded_log"
  [ -s "$bounded_log" ] || die "Bounded evidence log was not written: $bounded_log"
  [ -s "$service_log" ] || die "Observable service bounded log is missing: $service_log"
  [ -s "$agent_status" ] || die "Modeled agent validation record is missing: $agent_status"
  [ -s "$trigger_status" ] || die "Modeled trigger verification record is missing: $trigger_status"
  q_mode="$(json_quote "$JENKINS_VERIFICATION_MODE")"
  q_time="$(json_quote "$(iso_timestamp_utc)")"
  q_role="$(json_quote "jenkins-controller")"
  q_checkpoint="$(json_quote "jenkins-controller-readiness")"
  q_command="$(json_quote "jenkins-controller-setup.sh collect-evidence")"
  q_status="$(json_quote "pass")"
  q_input="$(json_quote "$input_fingerprint")"
  q_manifest="$(json_quote "$manifest")"
  q_checksum="$(json_quote "$checksum")"
  q_checks="$(json_quote "Step 8 modeled/simulation-only proof: staged artifacts, checksums, rendered JCasC, curated plugins, key custody, Gerrit SSH reachability, modeled agent scheduling, modeled patchset-created, modeled agent build, modeled Verified+1 vote. Real Jenkins/Gerrit/agent end-to-end execution is deferred to Step 11; gerrit_public_key_fingerprint=$gerrit_fp agent_public_key_fingerprint=$agent_fp")"
  q_log="$(json_quote "$bounded_log;$service_log;$agent_status;$trigger_status")"
  q_redaction="$(json_quote "secrets-redacted; private keys, passwords, tokens, and LDAP bind secrets not recorded")"
  q_proof="$(json_quote "step8-modeled")"
  q_real="$(json_quote "false")"
  q_step11="$(json_quote "true")"
  cat >"$evidence" <<EOF
{
  "verification_mode": $q_mode,
  "timestamp": $q_time,
  "role_or_environment": $q_role,
  "checkpoint_name": $q_checkpoint,
  "command_name": $q_command,
  "status": $q_status,
  "proof_scope": $q_proof,
  "real_execution": $q_real,
  "step11_required_for_real_execution": $q_step11,
  "reviewed_input_fingerprint": $q_input,
  "artifact_manifest_references": $q_manifest,
  "checksum_references": $q_checksum,
  "checksum_verification_result": "pass",
  "observed_checks": $q_checks,
  "bounded_log_references": $q_log,
  "redaction_status": $q_redaction
}
EOF
  printf 'status=pass command=collect-evidence proof=modeled verification_mode=simulation-only real_execution=false evidence=%s\n' "$evidence"
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
      print-env-template|preflight|prepare-artifacts|install|configure-service|install-plugins|configure-jcasc|generate-integration-key|generate-agent-key|configure-integration|configure-agent|validate-agent|verify-trigger|validate|collect-evidence)
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
    configure-service) cmd_configure_service ;;
    install-plugins) cmd_install_plugins ;;
    configure-jcasc) cmd_configure_jcasc ;;
    generate-integration-key) cmd_generate_integration_key ;;
    generate-agent-key) cmd_generate_agent_key ;;
    configure-integration) cmd_configure_integration ;;
    configure-agent) cmd_configure_agent ;;
    validate-agent) cmd_validate_agent ;;
    verify-trigger) cmd_verify_trigger ;;
    validate) cmd_validate ;;
    collect-evidence) cmd_collect_evidence ;;
    *) die_usage "Unknown command: $command_name" ;;
  esac
}

main "$@"
