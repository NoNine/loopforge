#!/usr/bin/env bash

set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(CDPATH= cd -- "$script_dir/.." && pwd)"
# shellcheck source=common.sh
. "$script_dir/common.sh"

role="jenkins-controller"
default_env_file="$repo_root/examples/jenkins-controller.env.example"
env_file=""
dry_run=0
assume_yes=0

supported_jenkins_version="2.555.3"
supported_jenkins_java_version="21"
supported_jenkins_plugin_manager_version="2.15.0"
supported_jenkins_ubuntu_release="24.04"
supported_jenkins_ubuntu_codename="noble"
readonly JENKINS_NATIVE_HOME="/var/lib/jenkins"
readonly JENKINS_BUNDLE_FACTORY_WORK_DIR="/var/lib/loopforge/preparing/jenkins-artifacts-bundle/jenkins"
readonly JENKINS_STAGED_BUNDLE_PAYLOAD_DIR="/var/lib/loopforge/staging/jenkins"
readonly JENKINS_ARTIFACT_BUNDLE_NAME="jenkins-artifacts-bundle"

usage() {
  cat <<'USAGE'
Usage:
  scripts/jenkins-controller-setup.sh [--env FILE] [--dry-run] [--yes] <command>

Commands:
  print-env-template
  preflight
  prepare-artifacts
  prepare-target-workspace
  install
  configure-service
  install-plugins
  configure-jcasc
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

shell_quote() {
  printf '%q' "${1:?value required}"
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
  [ -d "$JENKINS_HOME/plugins" ] || die "Missing Jenkins plugin directory: $JENKINS_HOME/plugins"
  (
    cd "$JENKINS_HOME/plugins"
    find . -type f \( -name '*.jpi' -o -name '*.hpi' \) -print0 |
      sort -z |
      while IFS= read -r -d '' file; do
        printf '%s %s\n' "${file#./}" "$(sha256_file "$file")"
      done |
      sha256sum |
      awk '{print $1}'
  )
}

template_set_digest() {
  file_set_digest "$JENKINS_HOME/templates" "*"
}

assert_no_artifact_key_material() {
  local dir bad_path
  dir="${1:?artifact directory required}"
  [ -d "$dir" ] || die "Missing artifact directory for key-material scan: $dir"
  bad_path="$(
    find "$dir" -type f \( \
      -name 'authorized_keys' -o \
      -name '*.pub' -o \
      -name '*_rsa' -o \
      -name '*_dsa' -o \
      -name '*_ecdsa' -o \
      -name '*_ed25519' -o \
      -name 'id_rsa' -o \
      -name 'id_dsa' -o \
      -name 'id_ecdsa' -o \
      -name 'id_ed25519' -o \
      -name 'jenkins-gerrit.pub' -o \
      -name 'jenkins-agent.pub' \
    \) -print -quit
  )"
  [ -z "$bad_path" ] || die "Artifact bundle must not contain SSH key handoff or authorized_keys files: $bad_path"
  if grep -RIlE --exclude='*.template' --exclude='*.md' --exclude='checksums.sha256' \
    '(^-----BEGIN (OPENSSH |RSA |DSA |EC |)PRIVATE KEY-----|^ssh-(ed25519|rsa) |^ecdsa-sha2-nistp(256|384|521) )' \
    "$dir" >/tmp/jenkins-controller-artifact-key-scan.$$ 2>/dev/null; then
    bad_path="$(sed -n '1p' "/tmp/jenkins-controller-artifact-key-scan.$$")"
    rm -f "/tmp/jenkins-controller-artifact-key-scan.$$"
    die "Artifact bundle must not contain SSH key material: $bad_path"
  fi
  rm -f "/tmp/jenkins-controller-artifact-key-scan.$$"
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
JENKINS_HOST
JENKINS_URL
JENKINS_HTTP_PORT
JENKINS_RUNTIME_ACCOUNT
JENKINS_RUNTIME_GROUP
JENKINS_RUNTIME_UID
JENKINS_RUNTIME_GID
LOOPFORGE_OPERATOR_ACCOUNT
LOOPFORGE_OPERATOR_GROUP
JENKINS_HOME
CASC_JENKINS_CONFIG
JENKINS_STAGED_ARTIFACT_DIR
JENKINS_ARTIFACT_OUTPUT_DIR
JENKINS_DIRECT_PLUGIN_NAMES
JENKINS_PLUGIN_LIST
JENKINS_DOWNLOAD_ARTIFACTS
LDAP_URL
LDAP_BIND_DN
LDAP_USER_BASE
LDAP_GROUP_BASE
JENKINS_ADMIN_ACCOUNT
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
  if [ "${JENKINS_DOWNLOAD_ARTIFACTS:-0}" != "1" ]; then
    require_reviewed_value JENKINS_WAR_SOURCE
    require_reviewed_value JENKINS_PLUGIN_MANAGER_SOURCE
    require_reviewed_value JENKINS_PLUGIN_SOURCE_DIR
  fi
  if [ -z "${LDAP_BIND_PASSWORD:-}" ]; then
    die "Missing reviewed LDAP bind password input: set LDAP_BIND_PASSWORD at execution time"
  fi
}

require_account_separation() {
  [ "$JENKINS_RUNTIME_ACCOUNT" != "$JENKINS_ADMIN_ACCOUNT" ] ||
    die "Jenkins runtime account must not match Jenkins admin account"
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

validate_runtime_account_name() {
  local value
  value="${JENKINS_RUNTIME_ACCOUNT:-}"
  reject_control_chars JENKINS_RUNTIME_ACCOUNT "$value"
  case "$value" in
    ""|*[!a-z_0-9-]*)
      die "JENKINS_RUNTIME_ACCOUNT must be a local account name using lowercase letters, digits, underscore, or dash"
      ;;
  esac
  case "$value" in
    -*|[0-9]*|root|daemon|bin|sys|sync|games|man|lp|mail|news|uucp|proxy|www-data|backup|list|irc|_apt|nobody|systemd-*)
      die "JENKINS_RUNTIME_ACCOUNT is not allowed for the Jenkins runtime account: $value"
      ;;
  esac
  [ "${#value}" -le 32 ] || die "JENKINS_RUNTIME_ACCOUNT must be 32 characters or fewer"
}

validate_runtime_group_name() {
  local value
  value="${JENKINS_RUNTIME_GROUP:-}"
  reject_control_chars JENKINS_RUNTIME_GROUP "$value"
  case "$value" in
    ""|*[!a-z_0-9-]*)
      die "JENKINS_RUNTIME_GROUP must be a local group name using lowercase letters, digits, underscore, or dash"
      ;;
  esac
  case "$value" in
    -*|[0-9]*|root|daemon|bin|sys|sync|games|man|lp|mail|news|uucp|proxy|www-data|backup|list|irc|_apt|nobody|systemd-*)
      die "JENKINS_RUNTIME_GROUP is not allowed for the Jenkins runtime group: $value"
      ;;
  esac
  [ "${#value}" -le 32 ] || die "JENKINS_RUNTIME_GROUP must be 32 characters or fewer"
}

validate_runtime_owner_inputs() {
  validate_runtime_account_name
  validate_runtime_group_name
}

apply_env_defaults() {
  JENKINS_VERSION="$supported_jenkins_version"
  JENKINS_JAVA_VERSION="$supported_jenkins_java_version"
  JENKINS_PLUGIN_MANAGER_VERSION="$supported_jenkins_plugin_manager_version"
  JENKINS_UBUNTU_RELEASE="$supported_jenkins_ubuntu_release"
  JENKINS_UBUNTU_CODENAME="$supported_jenkins_ubuntu_codename"
  JENKINS_HOST="${JENKINS_HOST:-jenkins-controller-target}"
  JENKINS_URL="${JENKINS_URL:-http://jenkins-controller-target:8080/}"
  JENKINS_HTTP_PORT="${JENKINS_HTTP_PORT:-8080}"
  JENKINS_RUNTIME_ACCOUNT="${JENKINS_RUNTIME_ACCOUNT:-jenkins}"
  JENKINS_RUNTIME_GROUP="${JENKINS_RUNTIME_GROUP:-jenkins}"
  LOOPFORGE_OPERATOR_ACCOUNT="${LOOPFORGE_OPERATOR_ACCOUNT:-ci-operator}"
  LOOPFORGE_OPERATOR_GROUP="${LOOPFORGE_OPERATOR_GROUP:-$LOOPFORGE_OPERATOR_ACCOUNT}"
  JENKINS_HOME="${JENKINS_HOME:-$JENKINS_NATIVE_HOME}"
  CASC_JENKINS_CONFIG="$JENKINS_HOME/jcasc/jenkins.yaml"
  JENKINS_STAGED_ARTIFACT_DIR="${JENKINS_STAGED_ARTIFACT_DIR:-$JENKINS_STAGED_BUNDLE_PAYLOAD_DIR}"
  JENKINS_ARTIFACT_OUTPUT_DIR="${JENKINS_ARTIFACT_OUTPUT_DIR:-$JENKINS_BUNDLE_FACTORY_WORK_DIR}"
  JENKINS_EVIDENCE_DIR="${JENKINS_EVIDENCE_DIR:-/var/lib/loopforge/evidence}"
  JENKINS_LOG_DIR="${JENKINS_LOG_DIR:-/var/log/loopforge}"
  JENKINS_VERIFICATION_MODE="${JENKINS_VERIFICATION_MODE:-docker-simulation}"
  JENKINS_DOWNLOAD_ARTIFACTS="${JENKINS_DOWNLOAD_ARTIFACTS:-0}"
  JENKINS_WAR_SOURCE="${JENKINS_WAR_SOURCE:-}"
  JENKINS_PLUGIN_MANAGER_SOURCE="${JENKINS_PLUGIN_MANAGER_SOURCE:-}"
  JENKINS_PLUGIN_SOURCE_DIR="${JENKINS_PLUGIN_SOURCE_DIR:-}"
  JENKINS_OS_DEPENDENCIES="${JENKINS_OS_DEPENDENCIES:-ca-certificates,curl,fontconfig,openjdk-21-jre,openssh-client,rsync,tar,wget}"
  JENKINS_DIRECT_PLUGIN_NAMES="${JENKINS_DIRECT_PLUGIN_NAMES:-configuration-as-code,credentials,git,gerrit-trigger,ldap,matrix-auth,ssh-credentials,ssh-slaves,workflow-aggregator,job-dsl,timestamper,ws-cleanup}"
  JENKINS_PLUGIN_LIST="${JENKINS_PLUGIN_LIST:-configuration-as-code:2100.vb_fd699d2a_09c,credentials:1506.v948b_b_b_7dec44,git:5.10.1,gerrit-trigger:3.1983.v57096fe9923c,ldap:807.809.vd3a_4e5e4ec98,matrix-auth:3.2.10,ssh-credentials:372.va_250881b_08cd,ssh-slaves:3.1097.v868116049892,workflow-aggregator:608.v67378e9d3db_1,job-dsl:3654.vdf58f53e2d15,timestamper:1.30,ws-cleanup:0.49}"
  LDAP_URL="${LDAP_URL:-ldap://ldap:389}"
  LDAP_BIND_DN="${LDAP_BIND_DN:-cn=readonly,dc=example,dc=test}"
  LDAP_BIND_PASSWORD="${LDAP_BIND_PASSWORD:-}"
  LDAP_USER_BASE="${LDAP_USER_BASE:-ou=people,dc=example,dc=test}"
  LDAP_GROUP_BASE="${LDAP_GROUP_BASE:-ou=groups,dc=example,dc=test}"
  JENKINS_ADMIN_ACCOUNT="${JENKINS_ADMIN_ACCOUNT:-jenkins-admin}"
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
  prepare_loopforge_helper_dirs "$JENKINS_EVIDENCE_DIR" "$JENKINS_LOG_DIR"
  prepare_jenkins_runtime_dirs
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
  prepare_loopforge_helper_dirs /var/lib/loopforge /var/log/loopforge /var/lib/loopforge/staging "$JENKINS_EVIDENCE_DIR" "$JENKINS_LOG_DIR"
  printf 'status=pass command=prepare-target-workspace state_root=/var/lib/loopforge log_root=/var/log/loopforge\n'
}

runtime_account_exists() {
  validate_runtime_owner_inputs
  [ "$JENKINS_HOME" = "$JENKINS_NATIVE_HOME" ] ||
    die "JENKINS_HOME must be $JENKINS_NATIVE_HOME, got $JENKINS_HOME"
  classify_runtime_identity_state \
    "$JENKINS_RUNTIME_ACCOUNT" "$JENKINS_RUNTIME_GROUP" \
    "$JENKINS_RUNTIME_UID" "$JENKINS_RUNTIME_GID" \
    "$JENKINS_NATIVE_HOME" "Jenkins" >/dev/null
}

run_as_runtime() {
  local command
  command="${1:?command required}"
  if [ "$(id -u)" -eq 0 ] && command -v runuser >/dev/null 2>&1; then
    runuser -u "$JENKINS_RUNTIME_ACCOUNT" -- sh -lc "$command"
  elif [ "$(id -u)" -eq 0 ] && command -v su >/dev/null 2>&1; then
    su -s /bin/sh "$JENKINS_RUNTIME_ACCOUNT" -c "$command"
  elif command -v sudo >/dev/null 2>&1; then
    sudo -n -u "$JENKINS_RUNTIME_ACCOUNT" sh -lc "$command"
  else
    die "Missing root runuser/su or passwordless sudo for Jenkins runtime execution"
  fi
}

run_with_privilege() {
  local command
  command="${1:?command required}"
  if [ "$(id -u)" -eq 0 ]; then
    sh -c "$command"
  elif command -v sudo >/dev/null 2>&1; then
    sudo -n sh -c "$command"
  else
    die "Missing root or passwordless sudo for Jenkins privileged operation"
  fi
}

prepare_jenkins_home_ownership() {
  run_with_privilege "chown -R $(shell_quote "$JENKINS_RUNTIME_ACCOUNT:$JENKINS_RUNTIME_GROUP") $(shell_quote "$JENKINS_HOME")"
}

prepare_jenkins_runtime_dirs() {
  run_with_privilege "install -d -m 0755 -o $(shell_quote "$JENKINS_RUNTIME_ACCOUNT") -g $(shell_quote "$JENKINS_RUNTIME_GROUP") $(shell_quote "$JENKINS_HOME") $(shell_quote "$JENKINS_HOME/state") $(shell_quote "$JENKINS_HOME/logs")"
}

install_file_as_runtime() {
  local source target mode target_dir
  source="${1:?source required}"
  target="${2:?target required}"
  mode="${3:?mode required}"
  target_dir="$(dirname "$target")"
  run_with_privilege "install -d -m 0755 -o $(shell_quote "$JENKINS_RUNTIME_ACCOUNT") -g $(shell_quote "$JENKINS_RUNTIME_GROUP") $(shell_quote "$target_dir") && install -m $(shell_quote "$mode") -o $(shell_quote "$JENKINS_RUNTIME_ACCOUNT") -g $(shell_quote "$JENKINS_RUNTIME_GROUP") $(shell_quote "$source") $(shell_quote "$target")"
}

copy_tree_as_runtime() {
  local source target mode
  source="${1:?source required}"
  target="${2:?target required}"
  mode="${3:-0755}"
  run_with_privilege "rm -rf $(shell_quote "$target") && install -d -m $(shell_quote "$mode") -o $(shell_quote "$JENKINS_RUNTIME_ACCOUNT") -g $(shell_quote "$JENKINS_RUNTIME_GROUP") $(shell_quote "$target") && cp -R $(shell_quote "$source/.") $(shell_quote "$target/") && chown -R $(shell_quote "$JENKINS_RUNTIME_ACCOUNT:$JENKINS_RUNTIME_GROUP") $(shell_quote "$target")"
}

write_text_file_as_runtime() {
  local target content
  target="${1:?target required}"
  content="${2:?content required}"
  run_as_runtime "mkdir -p $(shell_quote "$(dirname "$target")") && printf '%s\n' $(shell_quote "$content") >$(shell_quote "$target")"
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

require_simulation_runtime() {
  case "${HARNESS_MODE:-}:${HARNESS_ENVIRONMENT:-}:$JENKINS_VERIFICATION_MODE" in
    docker-simulation:jenkins-controller-target:docker-simulation|vm-simulation:jenkins-controller:vm-simulation) ;;
    ::target-deployment) ;;
    *) die "Harness and Jenkins verification modes must select a supported backend or target-deployment" ;;
  esac
}

is_docker_simulation() {
  [ "${HARNESS_MODE:-}" = "docker-simulation" ] &&
    [ "${HARNESS_ENVIRONMENT:-}" = "jenkins-controller-target" ] &&
    [ "$JENKINS_VERIFICATION_MODE" = "docker-simulation" ]
}

is_systemd_runtime() {
  case "$JENKINS_VERIFICATION_MODE" in
    vm-simulation|target-deployment) return 0 ;;
    *) return 1 ;;
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
  local source target text ldap_bind_password
  source="${1:?source required}"
  target="${2:?target required}"
  text="$(cat "$source")"
  ldap_bind_password="$(ldap_bind_password_value)"
  text="${text//\{\{JENKINS_HOME\}\}/$JENKINS_HOME}"
  text="${text//\{\{CASC_JENKINS_CONFIG\}\}/$CASC_JENKINS_CONFIG}"
  text="${text//\{\{JENKINS_HTTP_PORT\}\}/$JENKINS_HTTP_PORT}"
  text="${text//\{\{JENKINS_RUNTIME_ACCOUNT\}\}/$JENKINS_RUNTIME_ACCOUNT}"
  text="${text//\{\{JENKINS_RUNTIME_GROUP\}\}/$JENKINS_RUNTIME_GROUP}"
  text="${text//\{\{JENKINS_URL\}\}/$JENKINS_URL}"
  text="${text//\{\{LDAP_URL\}\}/$LDAP_URL}"
  text="${text//\{\{LDAP_BIND_DN\}\}/$LDAP_BIND_DN}"
  text="${text//\{\{LDAP_BIND_PASSWORD\}\}/$ldap_bind_password}"
  text="${text//\{\{LDAP_USER_BASE\}\}/$LDAP_USER_BASE}"
  text="${text//\{\{LDAP_GROUP_BASE\}\}/$LDAP_GROUP_BASE}"
  text="${text//\{\{JENKINS_ADMIN_ACCOUNT\}\}/$JENKINS_ADMIN_ACCOUNT}"
  text="${text//\{\{VERIFICATION_MODE\}\}/$JENKINS_VERIFICATION_MODE}"
  mkdir -p "$(dirname "$target")"
  printf '%s\n' "$text" >"$target"
  chmod 0600 "$target"
}

render_template_as_runtime() {
  local source target mode tmp
  source="${1:?source required}"
  target="${2:?target required}"
  mode="${3:-0600}"
  tmp="$(mktemp)"
  render_template "$source" "$tmp"
  install_file_as_runtime "$tmp" "$target" "$mode"
  rm -f "$tmp"
}

runtime_file_contains() {
  local file pattern
  file="${1:?file required}"
  pattern="${2:?pattern required}"
  run_as_runtime "grep -Fq -- $(shell_quote "$pattern") $(shell_quote "$file")"
}

runtime_file_has_no_unresolved_placeholders() {
  local file
  file="${1:?file required}"
  if run_as_runtime "grep -Eq '\\{\\{[^}]+\\}\\}' $(shell_quote "$file")"; then
    die "Rendered file contains unresolved template placeholders: $file"
  fi
}

ldap_bind_password_value() {
  local secret
  secret="${LDAP_BIND_PASSWORD:-}"
  [ -n "$secret" ] || die "LDAP bind password is required for Jenkins LDAP authenticated bind"
  is_placeholder "$secret" &&
    die "LDAP bind password must be reviewed and must not be a placeholder"
  printf '%s\n' "$secret"
}

assert_no_unresolved_placeholders() {
  local file
  file="${1:?file required}"
  if grep -Eq '\{\{[^}]+\}\}' "$file"; then
    die "Rendered file contains unresolved template placeholders: $file"
  fi
}

validate_plugin_identifier() {
  local name
  name="${1:?plugin name required}"
  case "$name" in
    ""|*[!A-Za-z0-9_.-]*|*/*|*'..'*|.*|*-|*.)
      die "Invalid Jenkins plugin identifier: $name"
      ;;
  esac
}

validate_direct_plugin_name() {
  validate_plugin_identifier "$1"
}

validate_plugin_spec() {
  local spec name version
  spec="${1:?plugin spec required}"
  case "$spec" in
    *:*) name="${spec%%:*}"; version="${spec#*:}" ;;
    *) die "JENKINS_PLUGIN_LIST entries must be name:version, got: $spec" ;;
  esac
  validate_plugin_identifier "$name"
  case "$version" in
    ""|*[!A-Za-z0-9_.+-]*|*/*|*'..'*|.*|*-|*.)
      die "Invalid Jenkins plugin version for $name: $version"
      ;;
  esac
}

validate_direct_plugins() {
  for_each_csv_value "$JENKINS_DIRECT_PLUGIN_NAMES" validate_direct_plugin_name "JENKINS_DIRECT_PLUGIN_NAMES"
}

validate_plugins() {
  for_each_csv_value "$JENKINS_PLUGIN_LIST" validate_plugin_spec "JENKINS_PLUGIN_LIST"
}

enforce_version_baseline() {
  [ "$JENKINS_VERSION" = "$supported_jenkins_version" ] || die "Jenkins controller baseline must be $supported_jenkins_version unless the reviewed baseline is updated"
  [ "$JENKINS_JAVA_VERSION" = "$supported_jenkins_java_version" ] || die "Jenkins Java baseline must be OpenJDK $supported_jenkins_java_version"
  [ "$JENKINS_PLUGIN_MANAGER_VERSION" = "$supported_jenkins_plugin_manager_version" ] || die "Jenkins Plugin Installation Manager baseline must be $supported_jenkins_plugin_manager_version"
  [ "$JENKINS_UBUNTU_RELEASE" = "$supported_jenkins_ubuntu_release" ] || die "Ubuntu release baseline must be $supported_jenkins_ubuntu_release"
  [ "$JENKINS_UBUNTU_CODENAME" = "$supported_jenkins_ubuntu_codename" ] || die "Ubuntu codename baseline must be $supported_jenkins_ubuntu_codename"
}

validate_accepted_direct_plugins() {
  local name spec expected_count actual_count
  validate_direct_plugins
  validate_plugins
  expected_count=0
  for name in ${JENKINS_DIRECT_PLUGIN_NAMES//,/ }; do
    expected_count=$((expected_count + 1))
    case ",$JENKINS_PLUGIN_LIST," in
      *",$name:"*) ;;
      *) die "JENKINS_PLUGIN_LIST is missing accepted direct plugin pin for $name" ;;
    esac
  done
  actual_count=0
  for spec in ${JENKINS_PLUGIN_LIST//,/ }; do
    actual_count=$((actual_count + 1))
    name="$(plugin_name "$spec")"
    case ",$JENKINS_DIRECT_PLUGIN_NAMES," in
      *",$name,"*) ;;
      *) die "JENKINS_PLUGIN_LIST must contain only accepted direct plugin pins, not transitive dependency: $name" ;;
    esac
  done
  [ "$actual_count" -eq "$expected_count" ] ||
    die "JENKINS_PLUGIN_LIST must contain one accepted pin for each JENKINS_DIRECT_PLUGIN_NAMES entry"
}

plugin_name() {
  printf '%s\n' "${1%%:*}"
}

plugin_version() {
  printf '%s\n' "${1#*:}"
}

jenkins_war_artifact() {
  printf '%s/jenkins-%s.war\n' "$JENKINS_ARTIFACT_OUTPUT_DIR" "$JENKINS_VERSION"
}

jenkins_plugin_manager_artifact() {
  printf '%s/jenkins-plugin-manager-%s.jar\n' "$JENKINS_ARTIFACT_OUTPUT_DIR" "$JENKINS_PLUGIN_MANAGER_VERSION"
}

factory_download_log_path() {
  local payload_dir bundle_dir preparing_dir
  payload_dir="$JENKINS_ARTIFACT_OUTPUT_DIR"
  bundle_dir="$(dirname "$payload_dir")"
  preparing_dir="$(dirname "$bundle_dir")"
  printf '%s/%s.download.log\n' "$preparing_dir" "$JENKINS_ARTIFACT_BUNDLE_NAME"
}

write_accepted_plugin_seed() {
  local target spec
  target="${1:?target required}"
  : >"$target"
  for spec in ${JENKINS_PLUGIN_LIST//,/ }; do
    validate_plugin_spec "$spec"
    printf '%s\n' "$spec" >>"$target"
  done
}

run_plugin_manager_resolve() {
  local plugin_file report_file
  plugin_file="${1:?plugin file required}"
  report_file="${2:?report file required}"
  require_command java
  printf 'simulation-only public internet use: resolving and downloading Jenkins plugin artifacts with dependencies\n' >>"$(factory_download_log_path)"
  java -jar "$(jenkins_plugin_manager_artifact)" \
    --war "$(jenkins_war_artifact)" \
    --plugin-file "$plugin_file" \
    --plugin-download-directory "$JENKINS_ARTIFACT_OUTPUT_DIR/plugins" \
    >"$report_file" 2>&1
}

plugin_fact_stream() {
  local plugin_dir plugin manifest short_name plugin_version
  plugin_dir="${1:?plugin directory required}"
  [ -d "$plugin_dir" ] || die "Missing Jenkins plugin directory: $plugin_dir"
  while IFS= read -r -d '' plugin; do
    manifest="$(unzip -p "$plugin" META-INF/MANIFEST.MF | tr -d '\r')" ||
      die "Could not read Jenkins plugin manifest: $plugin"
    short_name="$(printf '%s\n' "$manifest" | awk -F': ' '/^Short-Name:/ {print $2; exit}')"
    plugin_version="$(printf '%s\n' "$manifest" | awk -F': ' '/^Plugin-Version:/ {print $2; exit}')"
    validate_plugin_spec "$short_name:$plugin_version"
    printf '%s:%s\n' "$short_name" "$plugin_version"
  done < <(find "$plugin_dir" -type f \( -name '*.jpi' -o -name '*.hpi' \) -print0 | sort -z)
}

plugin_count_in_dir() {
  local plugin_dir count
  plugin_dir="${1:?plugin directory required}"
  count="$(find "$plugin_dir" -type f \( -name '*.jpi' -o -name '*.hpi' \) | wc -l | tr -d ' ')"
  [ "$count" -gt 0 ] || die "No Jenkins plugin artifacts were available in $plugin_dir"
  printf '%s\n' "$count"
}

assert_direct_plugin_pins_in_dir() {
  local plugin_dir facts spec name expected actual
  plugin_dir="${1:?plugin directory required}"
  validate_plugins
  facts="$(plugin_fact_stream "$plugin_dir" | sort -u)"
  [ -n "$facts" ] || die "No Jenkins plugin artifacts were available in $plugin_dir"
  for spec in ${JENKINS_PLUGIN_LIST//,/ }; do
    name="$(plugin_name "$spec")"
    expected="$(plugin_version "$spec")"
    actual="$(printf '%s\n' "$facts" | awk -F: -v name="$name" '$1 == name { print $2; found = 1 } END { exit !found }' 2>/dev/null || true)"
    [ -n "$actual" ] || die "Accepted direct Jenkins plugin pin is missing from resolved plugin artifacts: $name"
    [ "$actual" = "$expected" ] ||
      die "Direct Jenkins plugin pin drift for $name: accepted=$expected resolved=$actual"
  done
}

prepare_plugins() {
  local seed_file resolver_report tmp_dir
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' RETURN
  seed_file="$tmp_dir/accepted-direct-plugins.txt"
  resolver_report="$tmp_dir/plugin-resolution.log"
  write_accepted_plugin_seed "$seed_file"

  if [ -n "${JENKINS_PLUGIN_SOURCE_DIR:-}" ]; then
    find "$JENKINS_PLUGIN_SOURCE_DIR" -maxdepth 1 -type f \( -name '*.jpi' -o -name '*.hpi' \) -exec cp {} "$JENKINS_ARTIFACT_OUTPUT_DIR/plugins/" \;
  elif [ "${JENKINS_DOWNLOAD_ARTIFACTS:-0}" = "1" ]; then
    run_plugin_manager_resolve "$seed_file" "$resolver_report"
  else
    printf 'BLOCKED: prepare-artifacts requires JENKINS_PLUGIN_SOURCE_DIR or JENKINS_DOWNLOAD_ARTIFACTS=1 for selected Jenkins plugin artifacts\n' >&2
    rm -rf "$tmp_dir"
    exit 2
  fi

  assert_direct_plugin_pins_in_dir "$JENKINS_ARTIFACT_OUTPUT_DIR/plugins"
  rm -rf "$tmp_dir"
  trap - RETURN
}

prepare_jenkins_war() {
  local dest url
  dest="$(jenkins_war_artifact)"
  if [ -n "${JENKINS_WAR_SOURCE:-}" ]; then
    cp "$JENKINS_WAR_SOURCE" "$dest"
  elif [ "${JENKINS_DOWNLOAD_ARTIFACTS:-0}" = "1" ]; then
    require_command wget
    url="https://get.jenkins.io/war-stable/$JENKINS_VERSION/jenkins.war"
    printf 'simulation-only public internet use: downloading Jenkins controller WAR\n' >>"$(factory_download_log_path)"
    wget -nv --show-progress=off --tries=5 --timeout=30 --read-timeout=120 -O "$dest" "$url"
  else
    printf 'BLOCKED: prepare-artifacts requires JENKINS_WAR_SOURCE or JENKINS_DOWNLOAD_ARTIFACTS=1 in the bundle factory; target hosts never download Jenkins application artifacts as fallback\n' >&2
    exit 2
  fi
  unzip -p "$dest" META-INF/MANIFEST.MF >/dev/null 2>&1 ||
    die "Jenkins WAR is not a valid archive and cannot support real controller startup: $dest"
}

prepare_plugin_manager() {
  local dest url
  dest="$(jenkins_plugin_manager_artifact)"
  if [ -n "${JENKINS_PLUGIN_MANAGER_SOURCE:-}" ]; then
    cp "$JENKINS_PLUGIN_MANAGER_SOURCE" "$dest"
  elif [ "${JENKINS_DOWNLOAD_ARTIFACTS:-0}" = "1" ]; then
    require_command wget
    url="https://github.com/jenkinsci/plugin-installation-manager-tool/releases/download/$JENKINS_PLUGIN_MANAGER_VERSION/jenkins-plugin-manager-$JENKINS_PLUGIN_MANAGER_VERSION.jar"
    printf 'simulation-only public internet use: downloading Jenkins Plugin Installation Manager artifact\n' >>"$(factory_download_log_path)"
    wget -nv --show-progress=off --tries=5 --timeout=30 --read-timeout=120 -O "$dest" "$url"
  else
    printf 'BLOCKED: prepare-artifacts requires JENKINS_PLUGIN_MANAGER_SOURCE or JENKINS_DOWNLOAD_ARTIFACTS=1 in the bundle factory\n' >&2
    exit 2
  fi
  unzip -p "$dest" META-INF/MANIFEST.MF >/dev/null 2>&1 ||
    die "Jenkins Plugin Installation Manager artifact is not a valid archive: $dest"
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
    openjdk-21-jre|openjdk-21-jre-headless) command_name="java" ;;
    openssh-client) command_name="ssh" ;;
    rsync) command_name="rsync" ;;
    tar) command_name="tar" ;;
    wget) command_name="wget" ;;
    *) return 0 ;;
  esac
  if ! command -v "$command_name" >/dev/null 2>&1; then
    if is_docker_simulation; then
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
  local dir allowed_work base suffix
  dir="${JENKINS_ARTIFACT_OUTPUT_DIR:-}"
  allowed_work="$JENKINS_BUNDLE_FACTORY_WORK_DIR"
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
    "$allowed_work"|"$allowed_work"/*)
      ;;
    /|/tmp|/tmp/*|/var|/var/*|/etc|/etc/*|/usr|/usr/*|"$repo_root"|"$repo_root"/*)
      die "Unsafe JENKINS_ARTIFACT_OUTPUT_DIR for prepare-artifacts: $dir"
      ;;
    /home|/home/*|"$HOME"|"$HOME"/*)
      die "Unsafe JENKINS_ARTIFACT_OUTPUT_DIR for prepare-artifacts: $dir"
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
            die "Unsafe JENKINS_ARTIFACT_OUTPUT_DIR suffix: $dir"
            ;;
        esac
        return 0
        ;;
    esac
  done
  die "JENKINS_ARTIFACT_OUTPUT_DIR must be under $allowed_work"
}

verify_staged_artifacts() {
  local manifest checksums
  manifest="$JENKINS_STAGED_ARTIFACT_DIR/manifest.txt"
  checksums="$JENKINS_STAGED_ARTIFACT_DIR/checksums.sha256"
  [ -f "$manifest" ] || die "Missing staged Jenkins controller manifest: $manifest"
  [ -f "$checksums" ] || die "Missing staged Jenkins controller checksums: $checksums"
  (cd "$JENKINS_STAGED_ARTIFACT_DIR" && sha256sum -c checksums.sha256) >/dev/null
  assert_direct_plugin_pins_in_dir "$JENKINS_STAGED_ARTIFACT_DIR/plugins"
  awk -F= '
    $1 == "harness_manifest_version" && $2 == "1" { h=1 }
    $1 == "role" && $2 == "jenkins-controller" { r=1 }
    $1 == "bundle_name" && $2 == "jenkins-artifacts-bundle" { b=1 }
    $1 == "gerrit_version" && $2 == "not-applicable" { g=1 }
    $1 == "jenkins_version" && $2 == "2.555.3" { jn=1 }
    $1 == "jenkins_plugin_manager_version" && $2 == "2.15.0" { pm=1 }
    $1 == "java_version" && $2 == "21" { j=1 }
    $1 == "ubuntu_release" && $2 == "24.04" { u=1 }
    $1 == "ubuntu_codename" && $2 == "noble" { n=1 }
    $1 == "war" && $2 == "jenkins-2.555.3.war" { w=1 }
    $1 == "plugin_manager" && $2 == "jenkins-plugin-manager-2.15.0.jar" { m=1 }
    $1 == "resolved_plugin_count" && $2 > 0 { pc=1 }
    $1 == "template_count" && $2 == "2" { t=1 }
    END { exit !(h && r && b && g && jn && pm && j && u && n && w && m && pc && t) }
  ' "$manifest" || die "Staged manifest does not match the Jenkins controller Version Baseline"
  assert_no_artifact_key_material "$JENKINS_STAGED_ARTIFACT_DIR"
}

cmd_preflight() {
  load_env normal
  require_env_values
  require_command sha256sum
  require_command awk
  require_command sed
  validate_accepted_direct_plugins
  validate_os_dependencies
  require_account_separation
  validate_runtime_owner_inputs
  runtime_account_exists
  if [ "$dry_run" -eq 0 ]; then
    check_os_dependency_expectations
  fi
  enforce_version_baseline
  printf 'status=pass command=preflight dry_run=%s env=%s host=%s http_port=%s runtime_account=%s runtime_group=%s runtime_uid=%s runtime_gid=%s mode=%s plugins=accepted-direct-pins\n' \
    "$dry_run" "${env_file:-$default_env_file}" "$JENKINS_HOST" "$JENKINS_HTTP_PORT" \
    "$JENKINS_RUNTIME_ACCOUNT" "$JENKINS_RUNTIME_GROUP" "$JENKINS_RUNTIME_UID" \
    "$JENKINS_RUNTIME_GID" "$JENKINS_VERIFICATION_MODE"
}

write_manifest() {
  local manifest resolved_plugin_count
  manifest="$JENKINS_ARTIFACT_OUTPUT_DIR/manifest.txt"
  resolved_plugin_count="$(plugin_count_in_dir "$JENKINS_ARTIFACT_OUTPUT_DIR/plugins")"
  cat >"$manifest" <<EOF
harness_manifest_version=1
role=jenkins-controller
bundle_name=$JENKINS_ARTIFACT_BUNDLE_NAME
ubuntu_release=24.04
ubuntu_codename=noble
java_version=21
gerrit_version=not-applicable
jenkins_version=2.555.3
jenkins_plugin_manager_version=2.15.0
resolved_plugin_count=$resolved_plugin_count
war=jenkins-2.555.3.war
plugin_manager=jenkins-plugin-manager-2.15.0.jar
template_count=2
EOF
}

package_artifact_bundle() {
  local payload_dir bundle_dir preparing_dir archive checksum
  payload_dir="$JENKINS_ARTIFACT_OUTPUT_DIR"
  bundle_dir="$(dirname "$payload_dir")"
  preparing_dir="$(dirname "$bundle_dir")"
  [ "$(basename "$bundle_dir")" = "$JENKINS_ARTIFACT_BUNDLE_NAME" ] ||
    die "JENKINS_ARTIFACT_OUTPUT_DIR must end with $JENKINS_ARTIFACT_BUNDLE_NAME/jenkins"
  archive="$preparing_dir/$JENKINS_ARTIFACT_BUNDLE_NAME.tar.gz"
  checksum="$archive.sha256"
  rm -f "$archive" "$checksum"
  tar -C "$bundle_dir" -czf "$archive" "$(basename "$payload_dir")"
  (cd "$preparing_dir" && sha256sum "$(basename "$archive")" >"$(basename "$checksum")")
  chmod u+rw,go+r "$archive" "$checksum"
}

prepare_artifact_bundle_workspace() {
  local payload_dir bundle_dir preparing_dir
  payload_dir="$JENKINS_ARTIFACT_OUTPUT_DIR"
  bundle_dir="$(dirname "$payload_dir")"
  preparing_dir="$(dirname "$bundle_dir")"
  [ "$payload_dir" = "$JENKINS_BUNDLE_FACTORY_WORK_DIR" ] ||
    die "JENKINS_ARTIFACT_OUTPUT_DIR must be $JENKINS_BUNDLE_FACTORY_WORK_DIR"
  prepare_loopforge_helper_dirs "$preparing_dir"
  rm -rf "$bundle_dir"
  mkdir -p "$payload_dir/plugins" "$payload_dir/templates"
}

cmd_prepare_artifacts() {
  load_env normal
  require_command sha256sum
  require_command unzip
  validate_accepted_direct_plugins
  enforce_version_baseline
  validate_artifact_output_dir
  prepare_artifact_bundle_workspace
  : >"$(factory_download_log_path)"
  prepare_jenkins_war
  prepare_plugin_manager
  prepare_plugins
  cp "$repo_root/templates/jenkins-controller/jenkins-service.env.template" "$JENKINS_ARTIFACT_OUTPUT_DIR/templates/jenkins-service.env.template"
  cp "$repo_root/templates/jenkins-controller/jenkins.service.template" "$JENKINS_ARTIFACT_OUTPUT_DIR/templates/jenkins.service.template"
  cp "$repo_root/templates/jenkins-controller/jenkins-jcasc.yaml.template" "$JENKINS_ARTIFACT_OUTPUT_DIR/templates/jenkins-jcasc.yaml.template"
  write_manifest
  assert_no_artifact_key_material "$JENKINS_ARTIFACT_OUTPUT_DIR"
  (
    cd "$JENKINS_ARTIFACT_OUTPUT_DIR"
    rm -f checksums.sha256
    find . -type f ! -name checksums.sha256 -print0 |
      sort -z |
      xargs -0 sha256sum >checksums.sha256
  )
  package_artifact_bundle
  printf 'status=pass command=prepare-artifacts artifact_dir=%s manifest=%s checksums=%s archive=%s archive_checksum=%s plugins=resolved-direct-pins\n' \
    "$JENKINS_ARTIFACT_OUTPUT_DIR" \
    "$JENKINS_ARTIFACT_OUTPUT_DIR/manifest.txt" \
    "$JENKINS_ARTIFACT_OUTPUT_DIR/checksums.sha256" \
    "$(dirname "$(dirname "$JENKINS_ARTIFACT_OUTPUT_DIR")")/$JENKINS_ARTIFACT_BUNDLE_NAME.tar.gz" \
    "$(dirname "$(dirname "$JENKINS_ARTIFACT_OUTPUT_DIR")")/$JENKINS_ARTIFACT_BUNDLE_NAME.tar.gz.sha256"
}

cmd_install() {
  local identity_action pids
  load_env normal
  require_env_values
  validate_runtime_owner_inputs
  runtime_account_exists
  confirm_mutation install || return 0
  verify_staged_artifacts
  identity_action="$(realize_runtime_identity \
    "$JENKINS_RUNTIME_ACCOUNT" "$JENKINS_RUNTIME_GROUP" \
    "$JENKINS_RUNTIME_UID" "$JENKINS_RUNTIME_GID" \
    "$JENKINS_NATIVE_HOME" "Jenkins")"
  ensure_dirs
  if [ -f "$JENKINS_HOME/run/jenkins.pid" ] && kill -0 "$(cat "$JENKINS_HOME/run/jenkins.pid")" 2>/dev/null; then
    run_with_privilege "kill $(shell_quote "$(cat "$JENKINS_HOME/run/jenkins.pid")") 2>/dev/null || true"
  fi
  pids="$(ps -eo pid=,args= | awk -v home="$JENKINS_HOME" 'index($0, home) && index($0, "jenkins.war") {print $1}')"
  if [ -n "$pids" ]; then
    run_with_privilege "kill $pids 2>/dev/null || true"
    sleep 2
    run_with_privilege "kill -9 $pids 2>/dev/null || true"
  fi
  run_with_privilege "rm -rf $(shell_quote "$JENKINS_HOME/war") $(shell_quote "$JENKINS_HOME/war-cache") $(shell_quote "$JENKINS_HOME/plugins") $(shell_quote "$JENKINS_HOME/templates") $(shell_quote "$JENKINS_HOME/state") $(shell_quote "$JENKINS_HOME/etc") $(shell_quote "$JENKINS_HOME/jcasc") $(shell_quote "$JENKINS_HOME/run") $(shell_quote "$JENKINS_HOME/artifact-manifest.txt") $(shell_quote "$JENKINS_HOME/artifact-checksums.sha256")"
  prepare_jenkins_runtime_dirs
  install_file_as_runtime "$JENKINS_STAGED_ARTIFACT_DIR/jenkins-2.555.3.war" "$JENKINS_HOME/war/jenkins.war" 0644
  copy_tree_as_runtime "$JENKINS_STAGED_ARTIFACT_DIR/templates" "$JENKINS_HOME/templates" 0755
  write_text_file_as_runtime "$JENKINS_HOME/state/install.status" "installed"
  printf 'status=pass command=install home=%s staged=%s runtime_identity=%s\n' \
    "$JENKINS_HOME" "$JENKINS_STAGED_ARTIFACT_DIR" "$identity_action"
}

jenkins_process_running() {
  local pid args
  pid="${1:-}"
  case "$pid" in
    ''|*[!0-9]*)
      return 1
      ;;
  esac
  args="$(ps -p "$pid" -o args= 2>/dev/null || true)"
  [ -n "$args" ] || return 1
  printf '%s\n' "$args" | grep -Fq 'jenkins.war' || return 1
  printf '%s\n' "$args" | grep -Fq "$JENKINS_HOME" || return 1
}

start_real_jenkins() {
  local pidfile log_file pid deadline response
  is_docker_simulation || die "Detached Jenkins startup is supported only in Docker simulation"
  runtime_account_exists
  pidfile="$JENKINS_HOME/run/jenkins.pid"
  log_file="$JENKINS_HOME/logs/jenkins-controller.log"
  prepare_jenkins_runtime_dirs
  run_with_privilege "install -d -m 0755 -o $(shell_quote "$JENKINS_RUNTIME_ACCOUNT") -g $(shell_quote "$JENKINS_RUNTIME_GROUP") $(shell_quote "$JENKINS_HOME/run") $(shell_quote "$JENKINS_HOME/war-cache")"
  if [ -f "$pidfile" ] && jenkins_process_running "$(cat "$pidfile")"; then
    return 0
  fi
  export JENKINS_HOME
  export CASC_JENKINS_CONFIG
  export JAVA_OPTS="-Djava.awt.headless=true -Djenkins.install.runSetupWizard=false"
  prepare_jenkins_home_ownership
  run_as_runtime "JENKINS_HOME=$(shell_quote "$JENKINS_HOME") CASC_JENKINS_CONFIG=$(shell_quote "$CASC_JENKINS_CONFIG") nohup java $JAVA_OPTS -jar $(shell_quote "$JENKINS_HOME/war/jenkins.war") --httpPort=$(shell_quote "$JENKINS_HTTP_PORT") --webroot=$(shell_quote "$JENKINS_HOME/war-cache") >$(shell_quote "$log_file") 2>&1 & echo \$! >$(shell_quote "$pidfile")"
  pid="$(cat "$pidfile")"
  deadline=$((SECONDS + 240))
  while [ "$SECONDS" -lt "$deadline" ]; do
    if ! jenkins_process_running "$pid"; then
      tail -40 "$log_file" >&2 || true
      die "Jenkins controller process exited before readiness; log=$log_file"
    fi
    response="$(check_http_endpoint || true)"
    if printf '%s' "$response" | grep -Fq "X-Jenkins: 2.555.3"; then
      write_text_file_as_runtime "$JENKINS_HOME/state/runtime.status" "pid=$pid endpoint=http://$JENKINS_HOST:$JENKINS_HTTP_PORT/ log=$log_file"
      return 0
    fi
    sleep 3
  done
  tail -40 "$log_file" >&2 || true
  die "Jenkins controller did not become ready before timeout; log=$log_file"
}

install_jenkins_systemd_unit() {
  local rendered
  rendered="$(mktemp)"
  render_template "$JENKINS_STAGED_ARTIFACT_DIR/templates/jenkins.service.template" "$rendered"
  assert_no_unresolved_placeholders "$rendered"
  run_with_privilege "install -D -m 0644 -o root -g root $(shell_quote "$rendered") /etc/systemd/system/jenkins.service"
  run_with_privilege "systemctl daemon-reload"
  rm -f "$rendered"
}

start_systemd_jenkins() {
  local pid deadline response
  install_jenkins_systemd_unit
  run_with_privilege "systemctl enable jenkins.service"
  if systemctl is-active --quiet jenkins.service; then
    run_with_privilege "systemctl restart jenkins.service"
  else
    run_with_privilege "systemctl start jenkins.service"
  fi
  deadline=$((SECONDS + 240))
  while [ "$SECONDS" -lt "$deadline" ]; do
    if systemctl is-active --quiet jenkins.service; then
      response="$(check_http_endpoint || true)"
      if printf '%s' "$response" | grep -Fq "X-Jenkins: 2.555.3"; then
        pid="$(systemctl show jenkins.service --property=MainPID --value)"
        case "$pid" in ''|0|*[!0-9]*) die "Jenkins systemd service has no MainPID" ;; esac
        jenkins_process_running "$pid" || die "Jenkins systemd MainPID is not the controller runtime"
        write_text_file_as_runtime "$JENKINS_HOME/run/jenkins.pid" "$pid"
        write_text_file_as_runtime "$JENKINS_HOME/state/runtime.status" "pid=$pid endpoint=http://$JENKINS_HOST:$JENKINS_HTTP_PORT/ manager=systemd"
        return 0
      fi
    fi
    sleep 3
  done
  die "Jenkins systemd service did not become ready before timeout"
}

start_jenkins_runtime() {
  if is_systemd_runtime; then
    start_systemd_jenkins
  else
    start_real_jenkins
  fi
}

assert_jenkins_runtime() {
  local pid
  if is_systemd_runtime; then
    systemctl is-enabled --quiet jenkins.service || die "Jenkins systemd service is not enabled"
    systemctl is-active --quiet jenkins.service || die "Jenkins systemd service is not active"
    pid="$(systemctl show jenkins.service --property=MainPID --value)"
  else
    pid="$(cat "$JENKINS_HOME/run/jenkins.pid" 2>/dev/null || true)"
  fi
  jenkins_process_running "$pid" || die "Jenkins controller runtime is not active"
}

cmd_configure_service() {
  load_env normal
  require_env_values
  validate_runtime_owner_inputs
  runtime_account_exists
  confirm_mutation configure-service || return 0
  verify_staged_artifacts
  ensure_dirs
  prepare_jenkins_runtime_dirs
  render_template_as_runtime "$JENKINS_STAGED_ARTIFACT_DIR/templates/jenkins-service.env.template" "$JENKINS_HOME/etc/jenkins-service.env" 0644
  assert_no_unresolved_placeholders "$JENKINS_HOME/etc/jenkins-service.env"
  if is_systemd_runtime; then
    install_jenkins_systemd_unit
  fi
  write_text_file_as_runtime "$JENKINS_HOME/state/service-configured.status" \
    "runtime_account=$JENKINS_RUNTIME_ACCOUNT port=$JENKINS_HTTP_PORT controller_executors=0"
  printf 'status=pass command=configure-service service_env=%s runtime_account=%s\n' \
    "$JENKINS_HOME/etc/jenkins-service.env" "$JENKINS_RUNTIME_ACCOUNT"
}

cmd_install_plugins() {
  load_env normal
  require_env_values
  validate_runtime_owner_inputs
  runtime_account_exists
  confirm_mutation install-plugins || return 0
  verify_staged_artifacts
  prepare_jenkins_runtime_dirs
  copy_tree_as_runtime "$JENKINS_STAGED_ARTIFACT_DIR/plugins" "$JENKINS_HOME/plugins" 0755
  plugin_set_digest >/dev/null
  write_text_file_as_runtime "$JENKINS_HOME/state/plugins.status" "installed plugins=$JENKINS_PLUGIN_LIST digest=$(plugin_set_digest)"
  printf 'status=pass command=install-plugins plugin_digest=%s\n' "$(plugin_set_digest)"
}

cmd_configure_jcasc() {
  load_env normal
  require_env_values
  validate_runtime_owner_inputs
  runtime_account_exists
  confirm_mutation configure-jcasc || return 0
  verify_staged_artifacts
  prepare_jenkins_runtime_dirs
  run_with_privilege "install -d -m 0700 -o $(shell_quote "$JENKINS_RUNTIME_ACCOUNT") -g $(shell_quote "$JENKINS_RUNTIME_GROUP") $(shell_quote "$JENKINS_HOME/jcasc")"
  render_template_as_runtime "$JENKINS_STAGED_ARTIFACT_DIR/templates/jenkins-jcasc.yaml.template" "$CASC_JENKINS_CONFIG"
  runtime_file_has_no_unresolved_placeholders "$CASC_JENKINS_CONFIG"
  runtime_file_contains "$CASC_JENKINS_CONFIG" 'numExecutors: 0' || die "JCasC must keep built-in node executors at zero"
  runtime_file_contains "$CASC_JENKINS_CONFIG" 'ldap:' || die "JCasC LDAP security realm is missing"
  runtime_file_contains "$CASC_JENKINS_CONFIG" 'managerPasswordSecret:' || die "JCasC LDAP manager password secret is missing"
  runtime_file_contains "$CASC_JENKINS_CONFIG" 'globalMatrix:' || die "JCasC matrix authorization strategy is missing"
  runtime_file_contains "$CASC_JENKINS_CONFIG" "name: \"$JENKINS_ADMIN_ACCOUNT\"" || die "JCasC administrator account is missing"
  runtime_file_contains "$CASC_JENKINS_CONFIG" 'name: "authenticated"' || die "JCasC authenticated SID is missing"
  runtime_file_contains "$CASC_JENKINS_CONFIG" '"Overall/Administer"' || die "JCasC administrator permission is missing"
  runtime_file_contains "$CASC_JENKINS_CONFIG" '"Overall/Read"' || die "JCasC authenticated read permission is missing"
  runtime_file_contains "$CASC_JENKINS_CONFIG" '"Job/Read"' || die "JCasC authenticated job read permission is missing"
  runtime_file_contains "$CASC_JENKINS_CONFIG" '"Job/Build"' || die "JCasC authenticated job build permission is missing"
  if runtime_file_contains "$CASC_JENKINS_CONFIG" 'loggedInUsersCanDoAnything:'; then
    die "JCasC must not use loggedInUsersCanDoAnything authorization"
  fi
  write_text_file_as_runtime "$JENKINS_HOME/state/jcasc.status" "configured ldap=$LDAP_URL admin_account=$JENKINS_ADMIN_ACCOUNT authorization=global-matrix"
  start_jenkins_runtime
  printf 'status=pass command=configure-jcasc jcasc=%s ldap=configured\n' "$CASC_JENKINS_CONFIG"
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
  for attempt in $(seq 1 60); do
    response="$(timeout 5 bash -c 'exec 3<>"/dev/tcp/$0/$1"; printf "GET /login HTTP/1.0\r\nHost: $0\r\n\r\n" >&3; cat <&3 2>/dev/null || true' "$JENKINS_HOST" "$JENKINS_HTTP_PORT" || true)"
    if grep -Fq -- 'HTTP/1.1 200 OK' <<<"$response" &&
      grep -Fq -- 'X-Jenkins: 2.555.3' <<<"$response"; then
      printf '%s\n' "$response"
      return 0
    fi
    sleep 2
  done
  grep -Fq -- 'HTTP/1.1 200 OK' <<<"$response" || die "Jenkins HTTP endpoint did not return 200"
  grep -Fq -- 'X-Jenkins: 2.555.3' <<<"$response" || die "Jenkins HTTP endpoint did not report Jenkins 2.555.3"
}

check_jenkins_api() {
  local response
  response="$(timeout 10 bash -c 'exec 3<>"/dev/tcp/$0/$1"; printf "GET /api/json HTTP/1.0\r\nHost: $0\r\n\r\n" >&3; cat <&3 2>/dev/null || true' "$JENKINS_HOST" "$JENKINS_HTTP_PORT" || true)"
  grep -Eq 'HTTP/1\.[01] (200|403)' <<<"$response" ||
    die "Jenkins API endpoint did not return a controller HTTP response"
  grep -Fq -- 'X-Jenkins: 2.555.3' <<<"$response" ||
    die "Jenkins API endpoint did not report Jenkins 2.555.3"
}

check_ldap_access() {
  local host port
  read -r host port <<EOF
$(ldap_host_port)
EOF
  check_tcp_connect "$host" "$port" || die "LDAP endpoint is not reachable: $host:$port"
}

check_plugin_readiness() {
  local spec name missing
  validate_plugins
  missing=0
  for spec in ${JENKINS_PLUGIN_LIST//,/ }; do
    name="$(plugin_name "$spec")"
    [ -f "$JENKINS_HOME/plugins/${name}.jpi" ] ||
      [ -f "$JENKINS_HOME/plugins/${name}.hpi" ] ||
      missing=1
  done
  [ "$missing" -eq 0 ] || die "One or more curated Jenkins plugins are not installed"
  [ -s "$JENKINS_HOME/state/plugins.status" ] || die "Plugin readiness marker is missing"
}

check_runtime_plugin_load_log() {
  local log_file markers_file transient_log
  transient_log=0
  if is_systemd_runtime; then
    log_file="$(mktemp "$JENKINS_LOG_DIR/jenkins-systemd-plugin-load.XXXXXX")"
    transient_log=1
    if ! run_with_privilege "journalctl -u jenkins.service -n 100 --no-pager >$(shell_quote "$log_file")"; then
      rm -f "$log_file"
      die "Jenkins systemd journal capture failed"
    fi
    if [ ! -s "$log_file" ]; then
      rm -f "$log_file"
      die "Jenkins systemd journal capture is missing: $log_file"
    fi
  else
    log_file="$JENKINS_HOME/logs/jenkins-controller.log"
    [ -s "$log_file" ] || die "Jenkins controller startup log is missing: $log_file"
  fi
  markers_file="$log_file.plugin-load-failures"
  grep -En 'Failed Loading plugin|Update required:|Failed to load:' "$log_file" >"$markers_file" || true
  if [ -s "$markers_file" ]; then
    sed -n '1,20p' "$markers_file" >&2
    rm -f "$markers_file"
    [ "$transient_log" -eq 0 ] || rm -f "$log_file"
    die "Jenkins runtime log contains plugin load failure marker: $log_file"
  fi
  rm -f "$markers_file"
  [ "$transient_log" -eq 0 ] || rm -f "$log_file"
}

check_jcasc_readiness() {
  [ -s "$CASC_JENKINS_CONFIG" ] || die "JCasC file is missing"
  runtime_file_contains "$CASC_JENKINS_CONFIG" 'ldap:' || die "JCasC LDAP realm is missing"
  runtime_file_contains "$CASC_JENKINS_CONFIG" 'managerPasswordSecret:' || die "JCasC LDAP manager password secret is missing"
  runtime_file_contains "$CASC_JENKINS_CONFIG" 'numExecutors: 0' || die "JCasC built-in executor policy is missing"
  runtime_file_contains "$CASC_JENKINS_CONFIG" 'globalMatrix:' || die "JCasC matrix authorization strategy is missing"
  runtime_file_contains "$CASC_JENKINS_CONFIG" "name: \"$JENKINS_ADMIN_ACCOUNT\"" || die "JCasC administrator account is missing"
  runtime_file_contains "$CASC_JENKINS_CONFIG" 'name: "authenticated"' || die "JCasC authenticated SID is missing"
  runtime_file_contains "$CASC_JENKINS_CONFIG" '"Overall/Administer"' || die "JCasC administrator permission is missing"
  runtime_file_contains "$CASC_JENKINS_CONFIG" '"Overall/Read"' || die "JCasC authenticated read permission is missing"
  runtime_file_contains "$CASC_JENKINS_CONFIG" '"Job/Read"' || die "JCasC authenticated job read permission is missing"
  runtime_file_contains "$CASC_JENKINS_CONFIG" '"Job/Build"' || die "JCasC authenticated job build permission is missing"
  if runtime_file_contains "$CASC_JENKINS_CONFIG" 'loggedInUsersCanDoAnything:'; then
    die "JCasC must not use loggedInUsersCanDoAnything authorization"
  fi
}

verify_base_readiness_facts() {
  runtime_account_exists
  verify_staged_artifacts
  assert_jenkins_runtime
  [ -s "$JENKINS_HOME/state/install.status" ] || die "Install marker missing"
  [ -s "$JENKINS_HOME/state/service-configured.status" ] || die "Service configuration marker missing"
  [ -s "$JENKINS_HOME/war/jenkins.war" ] || die "Jenkins WAR is not installed"
  check_plugin_readiness
  check_jcasc_readiness
  [ -s "$JENKINS_HOME/state/runtime.status" ] || die "Jenkins runtime status marker is missing"
  check_runtime_plugin_load_log
  check_ldap_access
}

cmd_validate() {
  load_env normal
  require_env_values
  verify_base_readiness_facts
  check_http_endpoint >/dev/null
  check_jenkins_api
  cmd_collect_evidence >/dev/null
  printf 'status=pass command=validate proof=real-controller-runtime startup=pass endpoint=pass api=pass ldap=pass plugins=pass JCasC=pass integration=deferred evidence_dir=%s\n' "$JENKINS_EVIDENCE_DIR"
}

cmd_collect_evidence() {
  load_env normal
  apply_env_defaults
  require_env_values
  verify_base_readiness_facts
  ensure_dirs
  local evidence input_fingerprint manifest checksum bounded_log service_log runtime_status jenkins_pid
  local q_mode q_time q_role q_checkpoint q_command q_status q_input q_manifest q_checksum q_checks q_log q_service_log q_runtime_status q_redaction q_proof q_real q_step11
  evidence="$JENKINS_EVIDENCE_DIR/jenkins-controller-readiness-$(timestamp_utc).json"
  bounded_log="$JENKINS_LOG_DIR/jenkins-controller-collect-evidence-$(timestamp_utc).log"
  if is_systemd_runtime; then
    service_log="$JENKINS_LOG_DIR/jenkins-systemd-$(timestamp_utc).log"
    run_with_privilege "{ systemctl show jenkins.service --property=Id --property=LoadState --property=ActiveState --property=SubState --property=MainPID; journalctl -u jenkins.service -n 100 --no-pager; } >$(shell_quote "$service_log")"
  else
    service_log="$JENKINS_HOME/logs/jenkins-controller.log"
  fi
  runtime_status="$JENKINS_HOME/state/runtime.status"
  jenkins_pid="$JENKINS_HOME/run/jenkins.pid"
  input_fingerprint="$(printf '%s\n%s\n%s\n%s\n%s\n' "$JENKINS_HOST" "$JENKINS_HTTP_PORT" "$LDAP_URL" "$JENKINS_HOME" "$JENKINS_ADMIN_ACCOUNT" | sha256sum | awk '{print $1}')"
  manifest="$JENKINS_STAGED_ARTIFACT_DIR/manifest.txt"
  checksum="$JENKINS_STAGED_ARTIFACT_DIR/checksums.sha256"
  {
    printf 'timestamp=%s\n' "$(iso_timestamp_utc)"
    printf 'command=collect-evidence\n'
    printf 'proof_scope=controller-runtime\n'
    printf 'verification_mode=%s\n' "$JENKINS_VERIFICATION_MODE"
    printf 'real_execution=true\n'
    printf 'step11_required_for_real_execution=false\n'
    printf 'artifact_manifest=%s\n' "$manifest"
    printf 'checksum_reference=%s\n' "$checksum"
    printf 'observed=staged-artifacts,real-jenkins-startup,http-endpoint,api-json,ldap,plugins,JCasC-global-matrix,service-manager\n'
    printf 'redaction=secrets-not-recorded\n'
  } >"$bounded_log"
  [ -s "$bounded_log" ] || die "Bounded evidence log was not written: $bounded_log"
  [ -s "$service_log" ] || die "Jenkins controller log is missing: $service_log"
  [ -s "$runtime_status" ] || die "Jenkins runtime status marker is missing: $runtime_status"
  [ -s "$jenkins_pid" ] || die "Jenkins PID marker is missing: $jenkins_pid"
  q_mode="$(json_quote "$JENKINS_VERIFICATION_MODE")"
  q_time="$(json_quote "$(iso_timestamp_utc)")"
  q_role="$(json_quote "jenkins-controller")"
  q_checkpoint="$(json_quote "jenkins-controller-readiness")"
  q_command="$(json_quote "jenkins-controller-setup.sh collect-evidence")"
  q_status="$(json_quote "pass")"
  q_input="$(json_quote "$input_fingerprint")"
  q_manifest="$(json_quote "$manifest")"
  q_checksum="$(json_quote "$checksum")"
  q_checks="$(json_quote "Real Jenkins controller process started from staged WAR, responded on /login and /api/json, retained plugin and JCasC global-matrix readiness for the reviewed administrator account and authenticated SID, and wrote bounded logs without secrets.")"
  q_log="$(json_quote "$bounded_log")"
  q_service_log="$(json_quote "$service_log")"
  q_runtime_status="$(json_quote "$runtime_status")"
  q_redaction="$(json_quote "secrets-redacted; private keys, passwords, tokens, and LDAP bind secrets not recorded")"
  q_proof="$(json_quote "controller-runtime")"
  q_real="$(json_quote "true")"
  q_step11="$(json_quote "false")"
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
  "service_log_reference": $q_service_log,
  "runtime_status_reference": $q_runtime_status,
  "redaction_status": $q_redaction
}
EOF
  printf 'status=pass command=collect-evidence proof=real-controller-runtime verification_mode=%s real_execution=true evidence=%s\n' "$JENKINS_VERIFICATION_MODE" "$evidence"
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
      print-env-template|preflight|prepare-artifacts|prepare-target-workspace|install|configure-service|install-plugins|configure-jcasc|validate|collect-evidence)
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
    configure-service) cmd_configure_service ;;
    install-plugins) cmd_install_plugins ;;
    configure-jcasc) cmd_configure_jcasc ;;
    validate) cmd_validate ;;
    collect-evidence) cmd_collect_evidence ;;
    *) die_usage "Unknown command: $command_name" ;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
