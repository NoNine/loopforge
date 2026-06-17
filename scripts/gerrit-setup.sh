#!/usr/bin/env bash

set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
repo_root="$(CDPATH= cd -- "$script_dir/.." && pwd)"
# shellcheck source=common.sh
. "$script_dir/common.sh"

role="gerrit"
default_env_file="$repo_root/examples/gerrit.env.example"
env_file=""
dry_run=0
assume_yes=0

usage() {
  cat <<'USAGE'
Usage:
  scripts/gerrit-setup.sh [--env FILE] [--dry-run] [--yes] <command>

Commands:
  print-env-template
  preflight
  prepare-artifacts
  install
  configure
  configure-integration
  validate
  collect-evidence

Options:
  --env FILE     Source reviewed Gerrit env values from FILE.
  --dry-run      Check inputs and describe non-mutating results only.
  --yes          Confirm mutating commands after env review.
  -h, --help     Show this help.

The manual remains the authority. This helper accelerates reviewed Gerrit
setup phases and never downloads application artifacts on the target host.
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

plugin_set_digest() {
  local plugin_dir
  plugin_dir="${1:?plugin dir required}"
  [ -d "$plugin_dir" ] || die "Missing Gerrit plugin directory: $plugin_dir"
  (
    cd "$plugin_dir"
    find . -type f -name '*.jar' -print0 |
      sort -z |
      while IFS= read -r -d '' file; do
        printf '%s %s\n' "${file#./}" "$(sha256_file "$file")"
      done |
      sha256sum |
      awk '{print $1}'
  )
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

load_env_file() {
  local file prior_ldap_bind_password_file prior_ldap_bind_password
  file="${env_file:-$default_env_file}"
  [ -f "$file" ] || die "Missing env file: $file"
  prior_ldap_bind_password_file="${LDAP_BIND_PASSWORD_FILE-__UNSET__}"
  prior_ldap_bind_password="${LDAP_BIND_PASSWORD-__UNSET__}"
  set -a
  # shellcheck disable=SC1090
  . "$file"
  set +a
  prefer_existing_reviewed_secret LDAP_BIND_PASSWORD_FILE "$prior_ldap_bind_password_file"
  prefer_existing_reviewed_secret LDAP_BIND_PASSWORD "$prior_ldap_bind_password"
}

prefer_existing_reviewed_secret() {
  local var_name prior_value current_value
  var_name="${1:?var name required}"
  prior_value="${2-__UNSET__}"
  eval "current_value=\${$var_name-}"
  if [ -z "$current_value" ] && [ "$prior_value" != "__UNSET__" ] && [ -n "$prior_value" ]; then
    printf -v "$var_name" '%s' "$prior_value"
  fi
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
GERRIT_VERSION
GERRIT_JAVA_VERSION
GERRIT_UBUNTU_RELEASE
GERRIT_UBUNTU_CODENAME
GERRIT_HOST
GERRIT_HTTP_PORT
GERRIT_SSH_PORT
GERRIT_RUNTIME_ACCOUNT
GERRIT_SITE_PATH
GERRIT_STAGED_ARTIFACT_DIR
GERRIT_ARTIFACT_OUTPUT_DIR
GERRIT_LOCAL_ARTIFACT_OUTPUT_DIR
GERRIT_PLUGIN_LIST
LDAP_URL
LDAP_BIND_DN
LDAP_USER_BASE
LDAP_GROUP_BASE
GERRIT_ADMIN_ACCOUNT
GERRIT_ADMIN_GROUP
GERRIT_VERIFICATION_PROJECT
GERRIT_VERIFICATION_REF_PATTERN
GERRIT_VERIFICATION_MODE
GERRIT_EVIDENCE_DIR
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
  GERRIT_VERSION="${GERRIT_VERSION:-3.13.6}"
  GERRIT_JAVA_VERSION="${GERRIT_JAVA_VERSION:-21}"
  GERRIT_UBUNTU_RELEASE="${GERRIT_UBUNTU_RELEASE:-24.04}"
  GERRIT_UBUNTU_CODENAME="${GERRIT_UBUNTU_CODENAME:-noble}"
  GERRIT_HOST="${GERRIT_HOST:-gerrit-target}"
  GERRIT_HTTP_PORT="${GERRIT_HTTP_PORT:-8080}"
  GERRIT_SSH_PORT="${GERRIT_SSH_PORT:-29418}"
  GERRIT_RUNTIME_ACCOUNT="${GERRIT_RUNTIME_ACCOUNT:-gerrit}"
  GERRIT_RUNTIME_GROUP="${GERRIT_RUNTIME_GROUP:-$GERRIT_RUNTIME_ACCOUNT}"
  GERRIT_JAVA_HOME="${GERRIT_JAVA_HOME:-/usr/lib/jvm/java-${GERRIT_JAVA_VERSION}-openjdk-amd64}"
  GERRIT_SITE_PATH="${GERRIT_SITE_PATH:-/harness/state/site}"
  GERRIT_STAGED_ARTIFACT_DIR="${GERRIT_STAGED_ARTIFACT_DIR:-/harness/staged}"
  GERRIT_LOCAL_ARTIFACT_OUTPUT_DIR="${GERRIT_LOCAL_ARTIFACT_OUTPUT_DIR:-$repo_root/simulation/state/local/gerrit/artifacts}"
  if [ "${HARNESS_ENVIRONMENT:-}" = "bundle-factory" ]; then
    GERRIT_ARTIFACT_OUTPUT_DIR="${GERRIT_ARTIFACT_OUTPUT_DIR:-/harness/state/artifacts/gerrit}"
  else
    GERRIT_ARTIFACT_OUTPUT_DIR="${GERRIT_ARTIFACT_OUTPUT_DIR:-$GERRIT_LOCAL_ARTIFACT_OUTPUT_DIR}"
  fi
  GERRIT_PLUGIN_LIST="${GERRIT_PLUGIN_LIST:-events-log,metrics-reporter-prometheus,healthcheck}"
  GERRIT_PLUGIN_SOURCE_DIR="${GERRIT_PLUGIN_SOURCE_DIR:-}"
  GERRIT_DOWNLOAD_ARTIFACTS="${GERRIT_DOWNLOAD_ARTIFACTS:-0}"
  GERRIT_OS_DEPENDENCIES="${GERRIT_OS_DEPENDENCIES:-ca-certificates,curl,git,ldap-utils,openssh-client,openjdk-21-jre-headless,rsync,tar,unzip,wget}"
  GERRIT_VERIFICATION_MODE="${GERRIT_VERIFICATION_MODE:-docker-harness-simulation}"
  GERRIT_EVIDENCE_DIR="${GERRIT_EVIDENCE_DIR:-/harness/evidence}"
  GERRIT_LOG_DIR="${GERRIT_LOG_DIR:-/harness/logs}"
  LDAP_URL="${LDAP_URL:-ldap://ldap:389}"
  LDAP_BIND_DN="${LDAP_BIND_DN:-cn=readonly,dc=example,dc=test}"
  LDAP_BIND_PASSWORD_FILE="${LDAP_BIND_PASSWORD_FILE:-}"
  LDAP_BIND_PASSWORD="${LDAP_BIND_PASSWORD:-}"
  LDAP_USER_BASE="${LDAP_USER_BASE:-ou=people,dc=example,dc=test}"
  LDAP_GROUP_BASE="${LDAP_GROUP_BASE:-ou=groups,dc=example,dc=test}"
  GERRIT_ADMIN_ACCOUNT="${GERRIT_ADMIN_ACCOUNT:-gerrit-admin}"
  GERRIT_ADMIN_GROUP="${GERRIT_ADMIN_GROUP:-gerrit-admins}"
  GERRIT_INTEGRATION_CONFIG_MODE="${GERRIT_INTEGRATION_CONFIG_MODE:-site-git}"
  GERRIT_INTEGRATION_ACCOUNT_ID="${GERRIT_INTEGRATION_ACCOUNT_ID:-1000001}"
  GERRIT_INTEGRATION_GROUP_ID="${GERRIT_INTEGRATION_GROUP_ID:-1000001}"
  GERRIT_ADMIN_SSH_ACCOUNT="${GERRIT_ADMIN_SSH_ACCOUNT:-$GERRIT_ADMIN_ACCOUNT}"
  GERRIT_ADMIN_PRIVATE_KEY_FILE="${GERRIT_ADMIN_PRIVATE_KEY_FILE:-}"
  GERRIT_VERIFICATION_PROJECT="${GERRIT_VERIFICATION_PROJECT:-verification-disposable-gerrit}"
  GERRIT_VERIFICATION_REF_PATTERN="${GERRIT_VERIFICATION_REF_PATTERN:-refs/*}"
  case "${HARNESS_ENVIRONMENT:-}" in
    bundle-factory)
      GERRIT_ARTIFACT_OUTPUT_DIR="/harness/state/artifacts/gerrit"
      GERRIT_EVIDENCE_DIR="/harness/evidence"
      GERRIT_LOG_DIR="/harness/logs"
      ;;
    gerrit-target)
      GERRIT_SITE_PATH="/harness/state/site"
      GERRIT_STAGED_ARTIFACT_DIR="/harness/staged"
      GERRIT_ARTIFACT_OUTPUT_DIR="/harness/state/artifacts/gerrit"
      JENKINS_GERRIT_PUBLIC_KEY_FILE="/harness/staged/jenkins-gerrit.pub"
      GERRIT_EVIDENCE_DIR="/harness/evidence"
      GERRIT_LOG_DIR="/harness/logs"
      ;;
  esac
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
  mkdir -p "$GERRIT_SITE_PATH" "$GERRIT_EVIDENCE_DIR" "$GERRIT_LOG_DIR"
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

is_docker_harness_simulation() {
  [ "${HARNESS_MODE:-}" = "docker-harness-simulation" ] &&
    [ "${HARNESS_ENVIRONMENT:-}" = "gerrit-target" ] &&
    [ "$GERRIT_VERIFICATION_MODE" = "docker-harness-simulation" ]
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
  die "$command_name mutates Gerrit target state; rerun with --yes after reviewing the env file"
}

write_text_file() {
  local target content
  target="${1:?target required}"
  content="${2:?content required}"
  mkdir -p "$(dirname "$target")"
  printf '%s\n' "$content" >"$target"
}

replace_optional_placeholder() {
  local text placeholder name template_source value
  text="${1:?text required}"
  placeholder="${2:?placeholder required}"
  name="${3:?name required}"
  template_source="${4:?template source required}"
  if [[ "$text" != *"$placeholder"* ]]; then
    printf '%s\n' "$text"
    return 0
  fi
  value="$(value_or_default "$name" "")"
  [ -n "$value" ] ||
    die "Template $template_source requires deferred env value $name; run this template only in the later integration step with reviewed Jenkins integration inputs"
  printf '%s\n' "${text//"$placeholder"/$value}"
}

render_template() {
  local source target text
  source="${1:?source required}"
  target="${2:?target required}"
  text="$(cat "$source")"
  text="${text//\{\{GERRIT_CANONICAL_WEB_URL\}\}/http:\/\/$GERRIT_HOST:$GERRIT_HTTP_PORT\/}"
  text="${text//\{\{GERRIT_HTTP_LISTEN_URL\}\}/http:\/\/*:$(printf '%s' "$GERRIT_HTTP_PORT")\/}"
  text="${text//\{\{GERRIT_SSH_LISTEN_ADDRESS\}\}/\*:$(printf '%s' "$GERRIT_SSH_PORT")}"
  text="${text//\{\{GERRIT_JAVA_HOME\}\}/$GERRIT_JAVA_HOME}"
  text="${text//\{\{LDAP_URL\}\}/$LDAP_URL}"
  text="${text//\{\{LDAP_BIND_DN\}\}/$LDAP_BIND_DN}"
  text="${text//\{\{LDAP_USER_BASE\}\}/$LDAP_USER_BASE}"
  text="${text//\{\{LDAP_GROUP_BASE\}\}/$LDAP_GROUP_BASE}"
  text="${text//\{\{GERRIT_ADMIN_GROUP\}\}/$GERRIT_ADMIN_GROUP}"
  text="${text//\{\{GERRIT_REF_PATTERN\}\}/$GERRIT_VERIFICATION_REF_PATTERN}"
  text="${text//\{\{GERRIT_VERIFICATION_REF_PATTERN\}\}/$GERRIT_VERIFICATION_REF_PATTERN}"
  text="$(replace_optional_placeholder "$text" "{{JENKINS_GERRIT_INTEGRATION_GROUP}}" JENKINS_GERRIT_INTEGRATION_GROUP "$source")"
  text="$(replace_optional_placeholder "$text" "{{JENKINS_GERRIT_INTEGRATION_ACCOUNT}}" JENKINS_GERRIT_INTEGRATION_ACCOUNT "$source")"
  mkdir -p "$(dirname "$target")"
  printf '%s\n' "$text" >"$target"
}

read_reviewed_secret_value() {
  local password_file secret
  password_file="$(ldap_bind_password_file)"
  secret="$(tr -d '\r\n' <"$password_file")"
  [ -n "$secret" ] || die "Reviewed secret input is empty"
  is_placeholder "$secret" &&
    die "Reviewed secret input must not be a placeholder"
  printf '%s\n' "$secret"
  [ "$password_file" = "$LDAP_BIND_PASSWORD_FILE" ] || rm -f "$password_file"
}

write_secure_config() {
  local secret
  secret="$(read_reviewed_secret_value)"
  mkdir -p "$GERRIT_SITE_PATH/etc"
  {
    printf '%s\n' "# Gerrit secure config written from reviewed LDAP bind secret input."
    printf '\n[ldap]\n'
    printf 'password = %s\n' "$secret"
  } >"$GERRIT_SITE_PATH/etc/secure.config"
  chmod 0600 "$GERRIT_SITE_PATH/etc/secure.config"
}

secure_config_password_value() {
  config_value "$GERRIT_SITE_PATH/etc/secure.config" ldap.password
}

config_value() {
  local file key
  file="${1:?file required}"
  key="${2:?key required}"
  git config -f "$file" --get "$key" 2>/dev/null || true
}

assert_config_key_matches() {
  local expected_file actual_file key expected_value actual_value
  expected_file="${1:?expected file required}"
  actual_file="${2:?actual file required}"
  key="${3:?key required}"
  expected_value="$(config_value "$expected_file" "$key")"
  actual_value="$(config_value "$actual_file" "$key")"
  [ -n "$expected_value" ] || die "Rendered Gerrit config is missing required helper-owned key: $key"
  [ "$actual_value" = "$expected_value" ] ||
    die "Installed Gerrit config key '$key' does not match the rendered staged config input"
}

assert_no_unresolved_placeholders() {
  local file
  file="${1:?file required}"
  if grep -Eq '\{\{[^}]+\}\}' "$file"; then
    die "Rendered file contains unresolved template placeholders: $file"
  fi
}

for_each_plugin() {
  local callback
  callback="${1:?callback required}"
  for_each_csv_value "$GERRIT_PLUGIN_LIST" "$callback" "GERRIT_PLUGIN_LIST"
}

validate_plugin_identifier() {
  local plugin
  plugin="${1:?plugin required}"
  case "$plugin" in
    *[!A-Za-z0-9_.-]*|*/*|*'..'*|.*|*-|*.)
      die "Invalid Gerrit plugin identifier: $plugin"
      ;;
  esac
}

validate_plugins() {
  for_each_plugin validate_plugin_identifier
}

validate_os_dependency_identifier() {
  local package
  package="${1:?package required}"
  case "$package" in
    *[!a-z0-9+.-]*|.*|*-|*.)
      die "Invalid Gerrit OS dependency identifier: $package"
      ;;
  esac
}

validate_os_dependencies() {
  local expected sorted_actual sorted_expected
  expected="ca-certificates,curl,git,ldap-utils,openssh-client,openjdk-21-jre-headless,rsync,tar,unzip,wget"
  for_each_csv_value "$GERRIT_OS_DEPENDENCIES" validate_os_dependency_identifier "GERRIT_OS_DEPENDENCIES"
  sorted_actual="$(printf '%s\n' "$GERRIT_OS_DEPENDENCIES" | tr ',' '\n' | sort | paste -sd, -)"
  sorted_expected="$(printf '%s\n' "$expected" | tr ',' '\n' | sort | paste -sd, -)"
  [ "$sorted_actual" = "$sorted_expected" ] ||
    die "GERRIT_OS_DEPENDENCIES must match the static Gerrit OS dependency baseline installed from approved internal Ubuntu/OS package repositories"
}

check_os_dependency_command() {
  local package command_name
  package="${1:?package required}"
  case "$package" in
    ca-certificates) command_name="update-ca-certificates" ;;
    curl) command_name="curl" ;;
    git) command_name="git" ;;
    ldap-utils) command_name="ldapsearch" ;;
    openssh-client) command_name="ssh" ;;
    openjdk-21-jre-headless) command_name="java" ;;
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
    die "Missing Gerrit OS dependency command '$command_name' for package '$package'"
  fi
}

check_os_dependency_expectations() {
  validate_os_dependencies
  for_each_csv_value "$GERRIT_OS_DEPENDENCIES" check_os_dependency_command "GERRIT_OS_DEPENDENCIES"
}

check_disk_space() {
  local path check_path available_kb min_kb
  path="${1:?path required}"
  min_kb="${2:?minimum KB required}"
  check_path="$path"
  while [ ! -e "$check_path" ] && [ "$check_path" != "/" ]; do
    check_path="$(dirname "$check_path")"
  done
  [ -e "$check_path" ] || die "Could not find an existing parent path for disk-space check: $path"
  available_kb="$(df -Pk "$check_path" | awk 'NR == 2 { print $4 }')"
  [ -n "$available_kb" ] || die "Could not determine available disk space for $path"
  [ "$available_kb" -ge "$min_kb" ] ||
    die "Insufficient disk space for $path: available_kb=$available_kb required_kb=$min_kb"
}

check_host_resolution() {
  getent hosts "$GERRIT_HOST" >/dev/null 2>&1 ||
    die "Gerrit host does not resolve: $GERRIT_HOST"
}

check_runtime_account_readiness() {
  getent passwd "$GERRIT_RUNTIME_ACCOUNT" >/dev/null 2>&1 ||
    die "Missing Gerrit runtime account: $GERRIT_RUNTIME_ACCOUNT"
  getent group "$GERRIT_RUNTIME_GROUP" >/dev/null 2>&1 ||
    die "Missing Gerrit runtime group: $GERRIT_RUNTIME_GROUP"
}

write_plugin_artifact() {
  local plugin source jar url
  plugin="${1:?plugin required}"
  jar="$GERRIT_ARTIFACT_OUTPUT_DIR/plugins/${plugin}.jar"
  mkdir -p "$(dirname "$jar")"
  if [ -n "$GERRIT_PLUGIN_SOURCE_DIR" ]; then
    source="$GERRIT_PLUGIN_SOURCE_DIR/${plugin}.jar"
    [ -f "$source" ] || die "GERRIT_PLUGIN_SOURCE_DIR is missing selected plugin artifact: $source"
    cp "$source" "$jar"
  elif [ "$GERRIT_DOWNLOAD_ARTIFACTS" = "1" ]; then
    require_command wget
    case "$plugin" in
      events-log)
        url="https://gerrit-ci.gerritforge.com/job/plugin-events-log-bazel-stable-3.13/lastSuccessfulBuild/artifact/bazel-bin/plugins/events-log/events-log.jar"
        ;;
      metrics-reporter-prometheus)
        url="https://gerrit-ci.gerritforge.com/job/plugin-metrics-reporter-prometheus-bazel-stable-3.13/lastSuccessfulBuild/artifact/bazel-bin/plugins/metrics-reporter-prometheus/metrics-reporter-prometheus.jar"
        ;;
      healthcheck)
        url="https://gerrit-ci.gerritforge.com/job/plugin-healthcheck-bazel-stable-3.13/lastSuccessfulBuild/artifact/bazel-bin/plugins/healthcheck/healthcheck.jar"
        ;;
      *)
        die "No approved plugin download URL configured for selected Gerrit plugin: $plugin"
        ;;
    esac
    printf 'simulation-only public internet use: downloading Gerrit plugin artifact %s\n' "$plugin" >>"$GERRIT_ARTIFACT_OUTPUT_DIR/source-boundary.log"
    rm -f "$jar"
    wget -q --show-progress=off --tries=5 --timeout=30 --read-timeout=60 \
      -O "$jar" "$url" >>"$GERRIT_ARTIFACT_OUTPUT_DIR/source-boundary.log" 2>&1
  else
    printf 'BLOCKED: prepare-artifacts requires GERRIT_PLUGIN_SOURCE_DIR or GERRIT_DOWNLOAD_ARTIFACTS=1 for selected Gerrit plugin jars\n' >&2
    return 1
  fi
  verify_plugin_artifact_file "$jar"
}

verify_staged_artifacts() {
  local manifest checksums
  manifest="$GERRIT_STAGED_ARTIFACT_DIR/manifest.txt"
  checksums="$GERRIT_STAGED_ARTIFACT_DIR/checksums.sha256"
  [ -f "$manifest" ] || die "Missing staged Gerrit manifest: $manifest"
  [ -f "$checksums" ] || die "Missing staged Gerrit checksums: $checksums"
  (cd "$GERRIT_STAGED_ARTIFACT_DIR" && sha256sum -c checksums.sha256) >/dev/null
  awk -F= '
    $1 == "harness_manifest_version" && $2 == "1" { h=1 }
    $1 == "role" && $2 == "gerrit" { r=1 }
    $1 == "gerrit_version" && $2 == "3.13.6" { g=1 }
    $1 == "java_version" && $2 == "21" { j=1 }
    $1 == "ubuntu_release" && $2 == "24.04" { u=1 }
    $1 == "ubuntu_codename" && $2 == "noble" { n=1 }
    END { exit !(h && r && g && j && u && n) }
  ' "$manifest" || die "Staged manifest does not match the Gerrit Version Baseline"
}

cmd_preflight() {
  load_env normal
  require_env_values
  require_command sha256sum
  require_command ssh-keygen
  require_command awk
  require_command sed
  require_command getent
  require_command df
  validate_plugins
  validate_os_dependencies
  if [ "$dry_run" -eq 0 ]; then
    check_os_dependency_expectations
    check_disk_space "$GERRIT_ARTIFACT_OUTPUT_DIR" 1048576
    check_disk_space "$GERRIT_SITE_PATH" 1048576
    check_host_resolution
    check_runtime_account_readiness
    check_ldap_access
  fi
  [ "$GERRIT_VERSION" = "3.13.6" ] || die "Gerrit default baseline must be 3.13.6 unless the reviewed baseline is updated"
  [ "$GERRIT_JAVA_VERSION" = "21" ] || die "Gerrit Java baseline must be OpenJDK 21"
  [ "$GERRIT_UBUNTU_RELEASE" = "24.04" ] || die "Ubuntu release baseline must be 24.04"
  [ "$GERRIT_UBUNTU_CODENAME" = "noble" ] || die "Ubuntu codename baseline must be noble"
  printf 'status=pass command=preflight dry_run=%s env=%s host=%s http_port=%s ssh_port=%s mode=%s checks=%s\n' \
    "$dry_run" "${env_file:-$default_env_file}" "$GERRIT_HOST" "$GERRIT_HTTP_PORT" "$GERRIT_SSH_PORT" "$GERRIT_VERIFICATION_MODE" \
    "disk,host-resolution,runtime-account-group,ldap-bind-search"
}

write_manifest() {
  local manifest
  manifest="$GERRIT_ARTIFACT_OUTPUT_DIR/manifest.txt"
  cat >"$manifest" <<EOF
harness_manifest_version=1
role=gerrit
ubuntu_release=24.04
ubuntu_codename=noble
java_version=21
gerrit_version=3.13.6
jenkins_version=not-applicable
jenkins_plugin_manager_version=not-applicable
artifact_source=curated-bundle-factory
public_internet_fallback=simulation-only
plugins=$GERRIT_PLUGIN_LIST
war=gerrit-3.13.6.war
plugin_artifacts=plugin-artifacts.manifest
EOF
}

write_plugin_manifests() {
  (
    cd "$GERRIT_ARTIFACT_OUTPUT_DIR"
    find plugins -type f -name '*.jar' -printf '%f\n' | sort >plugin-artifacts.manifest
    printf '%s\n' "$GERRIT_PLUGIN_LIST" |
      tr ',' '\n' |
      sed 's/$/.jar/' |
      sort >plugin-seed-jars.expected
    comm -23 plugin-seed-jars.expected plugin-artifacts.manifest >plugin-artifacts.missing
    test ! -s plugin-artifacts.missing
  ) || die "Prepared Gerrit plugin set does not match GERRIT_PLUGIN_LIST"
}

prepare_real_gerrit_war() {
  local war source
  war="$GERRIT_ARTIFACT_OUTPUT_DIR/gerrit-3.13.6.war"
  source="${GERRIT_WAR_SOURCE:-}"
  if [ -n "$source" ]; then
    [ -f "$source" ] || die "GERRIT_WAR_SOURCE does not exist: $source"
    cp "$source" "$war"
  elif [ "${GERRIT_DOWNLOAD_ARTIFACTS:-0}" = "1" ]; then
    require_command wget
    printf 'simulation-only public internet use: downloading Gerrit application artifact in bundle factory\n' >"$GERRIT_ARTIFACT_OUTPUT_DIR/source-boundary.log"
    rm -f "$war"
    wget -q --show-progress=off --tries=5 --timeout=30 --read-timeout=60 \
      -O "$war" \
      "https://gerrit-releases.storage.googleapis.com/gerrit-3.13.6.war" \
      >>"$GERRIT_ARTIFACT_OUTPUT_DIR/source-boundary.log" 2>&1
  else
    printf 'BLOCKED: prepare-artifacts requires GERRIT_WAR_SOURCE or GERRIT_DOWNLOAD_ARTIFACTS=1 in the bundle factory; target hosts never download Gerrit application artifacts as fallback\n' >&2
    return 1
  fi
  verify_war_artifact "$war"
}

verify_war_artifact() {
  local war war_entries
  war="${1:?war required}"
  [ -s "$war" ] || die "Gerrit WAR is missing or empty: $war"
  if ! unzip -t "$war" >/dev/null 2>&1; then
    die "BLOCKED: Gerrit WAR is not a valid archive and cannot support real Gerrit startup: $war"
  fi
  war_entries="$(unzip -Z1 "$war")" ||
    die "BLOCKED: Gerrit WAR entries could not be listed for artifact validation: $war"
  if ! printf '%s\n' "$war_entries" | grep -Eq '^(Main\.class|WEB-INF/web\.xml|com/google/gerrit/launcher/GerritLauncher\.class)$'; then
    die "BLOCKED: Gerrit WAR does not look like a real Gerrit application artifact: $war"
  fi
}

verify_plugin_artifact_file() {
  local jar
  jar="${1:?plugin jar required}"
  [ -s "$jar" ] || die "Gerrit plugin jar is missing or empty: $jar"
  unzip -t "$jar" >/dev/null 2>&1 ||
    die "BLOCKED: Gerrit plugin artifact is not a valid jar archive: $jar"
}

cmd_prepare_artifacts() {
  load_env normal
  apply_env_defaults
  confirm_mutation prepare-artifacts || return 0
  require_command sha256sum
  require_command unzip
  validate_plugins
  mkdir -p "$GERRIT_ARTIFACT_OUTPUT_DIR/plugins"
  rm -f "$GERRIT_ARTIFACT_OUTPUT_DIR/plugins/"*.jar
  prepare_real_gerrit_war
  for_each_plugin write_plugin_artifact
  write_plugin_manifests
  rm -f "$GERRIT_ARTIFACT_OUTPUT_DIR/jenkins-gerrit.pub"
  cp "$repo_root/templates/gerrit/gerrit.config.template" "$GERRIT_ARTIFACT_OUTPUT_DIR/gerrit.config.template"
  cp "$repo_root/templates/gerrit/secure.config.template" "$GERRIT_ARTIFACT_OUTPUT_DIR/secure.config.template"
  cp "$repo_root/templates/gerrit/verified-label.config.template" "$GERRIT_ARTIFACT_OUTPUT_DIR/verified-label.config.template"
  cp "$repo_root/templates/gerrit/jenkins-integration-access.config.template" "$GERRIT_ARTIFACT_OUTPUT_DIR/jenkins-integration-access.config.template"
  write_manifest
  (
    cd "$GERRIT_ARTIFACT_OUTPUT_DIR"
    rm -f checksums.sha256
    find . -type f ! -name checksums.sha256 -print0 |
      sort -z |
      xargs -0 sha256sum >checksums.sha256
  )
  printf 'status=pass command=prepare-artifacts artifact_dir=%s manifest=%s checksums=%s\n' \
    "$GERRIT_ARTIFACT_OUTPUT_DIR" "$GERRIT_ARTIFACT_OUTPUT_DIR/manifest.txt" "$GERRIT_ARTIFACT_OUTPUT_DIR/checksums.sha256"
}

cmd_install() {
  load_env normal
  require_env_values
  confirm_mutation install || return 0
  verify_staged_artifacts
  ensure_dirs
  mkdir -p "$GERRIT_SITE_PATH/bin" "$GERRIT_SITE_PATH/plugins" "$GERRIT_SITE_PATH/etc" "$GERRIT_SITE_PATH/logs"
  verify_war_artifact "$GERRIT_STAGED_ARTIFACT_DIR/gerrit-3.13.6.war"
  cp "$GERRIT_STAGED_ARTIFACT_DIR/gerrit-3.13.6.war" "$GERRIT_SITE_PATH/bin/gerrit.war"
  rm -f "$GERRIT_SITE_PATH/plugins/"*.jar
  cp -R "$GERRIT_STAGED_ARTIFACT_DIR/plugins/." "$GERRIT_SITE_PATH/plugins/"
  cp "$GERRIT_STAGED_ARTIFACT_DIR/manifest.txt" "$GERRIT_SITE_PATH/etc/artifact-manifest.txt"
  cp "$GERRIT_STAGED_ARTIFACT_DIR/checksums.sha256" "$GERRIT_SITE_PATH/etc/artifact-checksums.sha256"
  write_text_file "$GERRIT_SITE_PATH/state/install.status" "installed"
  printf 'status=pass command=install site=%s staged=%s\n' "$GERRIT_SITE_PATH" "$GERRIT_STAGED_ARTIFACT_DIR"
}

cmd_configure() {
  load_env normal
  require_env_values
  confirm_mutation configure || return 0
  verify_staged_artifacts
  ensure_dirs
  mkdir -p "$GERRIT_SITE_PATH/etc" "$GERRIT_SITE_PATH/state"
  render_template "$GERRIT_STAGED_ARTIFACT_DIR/gerrit.config.template" "$GERRIT_SITE_PATH/etc/gerrit.config"
  write_secure_config
  assert_no_unresolved_placeholders "$GERRIT_SITE_PATH/etc/gerrit.config"
  printf 'status=pass command=configure site=%s ldap=configured secure_config=written_from_reviewed_secret real_gerrit_start=deferred-to-validate\n' "$GERRIT_SITE_PATH"
}

ensure_git_identity() {
  git config user.name "Gerrit setup helper"
  git config user.email "gerrit-setup@example.invalid"
}

ensure_site_repo_worktree() {
  local repo_dir work_dir
  repo_dir="${1:?repo dir required}"
  work_dir="${2:?work dir required}"
  mkdir -p "$(dirname "$repo_dir")" "$(dirname "$work_dir")"
  if [ ! -d "$repo_dir" ] || [ ! -f "$repo_dir/HEAD" ]; then
    rm -rf "$repo_dir"
    run_as_gerrit_runtime "git init --bare --initial-branch=master $(shell_quote "$repo_dir") >/dev/null"
  fi
  rm -rf "$work_dir"
  run_as_gerrit_runtime "git clone $(shell_quote "$repo_dir") $(shell_quote "$work_dir") >/dev/null 2>&1 && cd $(shell_quote "$work_dir") && git config user.name $(shell_quote "Gerrit setup helper") && git config user.email $(shell_quote "gerrit-setup@example.invalid")"
}

commit_if_changed() {
  git add -A
  if ! git diff --cached --quiet; then
    git commit -m "${1:?commit message required}" >/dev/null
  fi
}

seed_all_projects_config() {
  local repo_dir work_dir project_config groups_config group_uuid
  repo_dir="$GERRIT_SITE_PATH/git/All-Projects.git"
  work_dir="$GERRIT_SITE_PATH/tmp/all-projects-work"
  group_uuid="$(integration_group_uuid)"
  ensure_site_repo_worktree "$repo_dir" "$work_dir"
  run_as_gerrit_runtime "cd $(shell_quote "$work_dir") && if git ls-remote --exit-code origin refs/meta/config >/dev/null 2>&1; then git fetch origin refs/meta/config:refs/remotes/origin/meta-config >/dev/null 2>&1 && git checkout -B setup-meta-config refs/remotes/origin/meta-config >/dev/null; else git checkout --orphan setup-meta-config >/dev/null && { git rm -rf . >/dev/null 2>&1 || true; } && find . -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +; fi"
  project_config="$work_dir/project.config"
  groups_config="$work_dir/groups"
  [ -f "$project_config" ] || : >"$project_config"
  [ -f "$groups_config" ] || printf '# UUID\tGroup Name\n#\n' >"$groups_config"
  git config -f "$project_config" --replace-all label.Verified.function NoBlock
  git config -f "$project_config" --replace-all label.Verified.defaultValue 0
  git config -f "$project_config" --unset-all label.Verified.value >/dev/null 2>&1 || true
  git config -f "$project_config" --add label.Verified.value "-1 Fails"
  git config -f "$project_config" --add label.Verified.value " 0 No score"
  git config -f "$project_config" --add label.Verified.value "+1 Verified"
  git config -f "$project_config" --replace-all "access.$GERRIT_VERIFICATION_REF_PATTERN.read" "group $JENKINS_GERRIT_INTEGRATION_GROUP"
  git config -f "$project_config" --replace-all "access.$GERRIT_VERIFICATION_REF_PATTERN.label-Verified" "-1..+1 group $JENKINS_GERRIT_INTEGRATION_GROUP"
  git config -f "$project_config" --replace-all capability.streamEvents "group $JENKINS_GERRIT_INTEGRATION_GROUP"
  awk -v uuid="$group_uuid" '$1 != uuid { print }' "$groups_config" >"$groups_config.tmp"
  mv "$groups_config.tmp" "$groups_config"
  printf '%s\t%s\n' "$group_uuid" "$JENKINS_GERRIT_INTEGRATION_GROUP" >>"$groups_config"
  run_as_gerrit_runtime "cd $(shell_quote "$work_dir") && git add project.config groups && if ! git diff --cached --quiet; then git commit -m $(shell_quote "Configure Jenkins Gerrit integration access") >/dev/null; fi && git push origin HEAD:refs/meta/config >/dev/null"
}

account_ref_for_id() {
  local account_id suffix
  account_id="${1:?account id required}"
  suffix="$(printf '%02d' "$((account_id % 100))")"
  printf 'refs/users/%s/%s\n' "$suffix" "$account_id"
}

integration_group_uuid() {
  printf 'gerrit-internal-group:%s\n' "$JENKINS_GERRIT_INTEGRATION_GROUP" |
    sha1sum |
    awk '{print $1}'
}

group_ref_for_uuid() {
  local group_uuid shard
  group_uuid="${1:?group uuid required}"
  shard="${group_uuid:0:2}"
  printf 'refs/groups/%s/%s\n' "$shard" "$group_uuid"
}

seed_all_users_account() {
  local repo_dir work_dir account_config authorized_keys account_ref
  repo_dir="$GERRIT_SITE_PATH/git/All-Users.git"
  work_dir="$GERRIT_SITE_PATH/tmp/all-users-work"
  account_ref="$(account_ref_for_id "$GERRIT_INTEGRATION_ACCOUNT_ID")"
  ensure_site_repo_worktree "$repo_dir" "$work_dir"
  run_as_gerrit_runtime "cd $(shell_quote "$work_dir") && if git ls-remote --exit-code origin $(shell_quote "$account_ref") >/dev/null 2>&1; then git fetch origin $(shell_quote "$account_ref"):refs/remotes/origin/integration-account >/dev/null 2>&1 && git checkout -B $(shell_quote "setup-${GERRIT_INTEGRATION_ACCOUNT_ID}") refs/remotes/origin/integration-account >/dev/null; else git checkout --orphan $(shell_quote "setup-${GERRIT_INTEGRATION_ACCOUNT_ID}") >/dev/null && { git rm -rf . >/dev/null 2>&1 || true; } && find . -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +; fi && mkdir -p .ssh && git config -f account.config --replace-all account.fullName $(shell_quote "$JENKINS_GERRIT_INTEGRATION_ACCOUNT") && git config -f account.config --replace-all account.preferredEmail $(shell_quote "$JENKINS_GERRIT_INTEGRATION_ACCOUNT@example.invalid") && cp $(shell_quote "$GERRIT_SITE_PATH/keys/jenkins-gerrit.pub") .ssh/authorized_keys && git add account.config .ssh/authorized_keys && actual_paths=\$(git ls-files | sort) && expected_paths=\$(printf '%s\n' .ssh/authorized_keys account.config | sort) && test \"\$actual_paths\" = \"\$expected_paths\" && if ! git diff --cached --quiet; then git commit -m $(shell_quote "Seed Jenkins Gerrit integration account") >/dev/null; fi && git push origin HEAD:$(shell_quote "$account_ref") >/dev/null"
}

seed_all_users_group() {
  local repo_dir work_dir group_uuid group_ref name_sha name_file
  repo_dir="$GERRIT_SITE_PATH/git/All-Users.git"
  work_dir="$GERRIT_SITE_PATH/tmp/all-users-group-work"
  group_uuid="$(integration_group_uuid)"
  group_ref="$(group_ref_for_uuid "$group_uuid")"
  name_sha="$(printf '%s' "$JENKINS_GERRIT_INTEGRATION_GROUP" | sha1sum | awk '{print $1}')"
  name_file="$work_dir/$name_sha"
  ensure_site_repo_worktree "$repo_dir" "$work_dir"
  run_as_gerrit_runtime "cd $(shell_quote "$work_dir") && if git ls-remote --exit-code origin $(shell_quote "$group_ref") >/dev/null 2>&1; then git fetch origin $(shell_quote "$group_ref"):refs/remotes/origin/integration-group >/dev/null 2>&1 && git checkout -B $(shell_quote "setup-group-$group_uuid") refs/remotes/origin/integration-group >/dev/null; else git checkout --orphan $(shell_quote "setup-group-$group_uuid") >/dev/null && { git rm -rf . >/dev/null 2>&1 || true; } && find . -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +; fi && git config -f group.config --replace-all group.name $(shell_quote "$JENKINS_GERRIT_INTEGRATION_GROUP") && git config -f group.config --replace-all group.id $(shell_quote "$GERRIT_INTEGRATION_GROUP_ID") && git config -f group.config --replace-all group.visibleToAll false && git config -f group.config --replace-all group.description $(shell_quote "Jenkins Gerrit integration automation") && git config -f group.config --replace-all group.ownerGroupUuid $(shell_quote "$group_uuid") && printf '%s\n' $(shell_quote "$GERRIT_INTEGRATION_ACCOUNT_ID") >members && : >subgroups && git add group.config members subgroups && actual_paths=\$(git ls-files | sort) && expected_paths=\$(printf '%s\n' group.config members subgroups | sort) && test \"\$actual_paths\" = \"\$expected_paths\" && if ! git diff --cached --quiet; then git commit -m $(shell_quote "Seed Jenkins Gerrit integration group") >/dev/null; fi && git push origin HEAD:$(shell_quote "$group_ref") >/dev/null"
  run_as_gerrit_runtime "cd $(shell_quote "$work_dir") && if git ls-remote --exit-code --heads origin refs/meta/group-names >/dev/null 2>&1 || git ls-remote --exit-code origin refs/meta/group-names >/dev/null 2>&1; then git fetch origin refs/meta/group-names:refs/remotes/origin/meta-group-names >/dev/null 2>&1 && git checkout -B $(shell_quote "setup-group-name-$group_uuid") refs/remotes/origin/meta-group-names >/dev/null; else git checkout --orphan $(shell_quote "setup-group-name-$group_uuid") >/dev/null && { git rm -rf . >/dev/null 2>&1 || true; } && find . -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +; fi"
  run_as_gerrit_runtime "cat >$(shell_quote "$name_file") <<'EOF'
[group]
	name = $JENKINS_GERRIT_INTEGRATION_GROUP
	uuid = $group_uuid
EOF
cd $(shell_quote "$work_dir") && git add $(shell_quote "$name_sha") && git ls-files --error-unmatch $(shell_quote "$name_sha") >/dev/null && if ! git diff --cached --quiet; then git commit -m $(shell_quote "Map Jenkins Gerrit integration group name") >/dev/null; fi && git push origin HEAD:refs/meta/group-names >/dev/null"
}

configure_integration_site_git() {
  require_command git
  check_runtime_account_readiness
  prepare_gerrit_runtime_ownership
  mkdir -p "$GERRIT_SITE_PATH/git" "$GERRIT_SITE_PATH/tmp"
  seed_all_users_account
  seed_all_users_group
}

configure_integration_admin_ssh() {
  [ -n "$GERRIT_ADMIN_PRIVATE_KEY_FILE" ] || die "Missing GERRIT_ADMIN_PRIVATE_KEY_FILE for admin SSH integration configuration"
  [ -r "$GERRIT_ADMIN_PRIVATE_KEY_FILE" ] || die "Gerrit admin private key is not readable: $GERRIT_ADMIN_PRIVATE_KEY_FILE"
  ssh -o BatchMode=yes -o StrictHostKeyChecking=no \
    -i "$GERRIT_ADMIN_PRIVATE_KEY_FILE" \
    -p "$GERRIT_SSH_PORT" \
    "$GERRIT_ADMIN_SSH_ACCOUNT@$GERRIT_HOST" \
    gerrit version >/dev/null 2>&1 ||
    die "BLOCKED: Gerrit admin SSH prerequisite failed for configure-integration"
  die "BLOCKED: Admin SSH integration mutation is not implemented without Gerrit REST/account APIs in this step; use site-git bootstrap in the Docker harness or provide a reviewed implementation path"
}

cmd_configure_integration() {
  load_env normal
  require_env_values
  confirm_mutation configure-integration || return 0
  die "BLOCKED: Step 7 defers Jenkins integration prerequisites to the later integration step"
  require_command ssh-keygen
  mkdir -p "$GERRIT_SITE_PATH/etc" "$GERRIT_SITE_PATH/state" "$GERRIT_SITE_PATH/keys"
  validate_public_key_file "$JENKINS_GERRIT_PUBLIC_KEY_FILE"
  cp "$JENKINS_GERRIT_PUBLIC_KEY_FILE" "$GERRIT_SITE_PATH/keys/jenkins-gerrit.pub"
  validate_public_key_file "$GERRIT_SITE_PATH/keys/jenkins-gerrit.pub"
  render_template "$GERRIT_STAGED_ARTIFACT_DIR/verified-label.config.template" "$GERRIT_SITE_PATH/etc/verified-label.config"
  render_template "$GERRIT_STAGED_ARTIFACT_DIR/jenkins-integration-access.config.template" "$GERRIT_SITE_PATH/etc/jenkins-integration-access.config"
  assert_no_unresolved_placeholders "$GERRIT_SITE_PATH/etc/verified-label.config"
  assert_no_unresolved_placeholders "$GERRIT_SITE_PATH/etc/jenkins-integration-access.config"
  case "$GERRIT_INTEGRATION_CONFIG_MODE" in
    site-git)
      ensure_gerrit_site_initialized_for_site_git
      configure_integration_site_git
      ;;
    admin-ssh)
      configure_integration_admin_ssh
      ;;
    *)
      die "Unsupported GERRIT_INTEGRATION_CONFIG_MODE: $GERRIT_INTEGRATION_CONFIG_MODE"
      ;;
  esac
  write_text_file "$GERRIT_SITE_PATH/state/integration-applied.status" \
    "account=$JENKINS_GERRIT_INTEGRATION_ACCOUNT group=$JENKINS_GERRIT_INTEGRATION_GROUP mode=$GERRIT_INTEGRATION_CONFIG_MODE"
  printf 'status=pass command=configure-integration account=%s group=%s mode=%s public_key_fingerprint=%s\n' \
    "$JENKINS_GERRIT_INTEGRATION_ACCOUNT" "$JENKINS_GERRIT_INTEGRATION_GROUP" "$GERRIT_INTEGRATION_CONFIG_MODE" "$(public_key_fingerprint "$GERRIT_SITE_PATH/keys/jenkins-gerrit.pub")"
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

check_http_endpoint() {
  local status
  if command -v curl >/dev/null 2>&1; then
    status="$(curl -fsS -o /dev/null -w '%{http_code}' "http://$GERRIT_HOST:$GERRIT_HTTP_PORT/" 2>/dev/null || true)"
    case "$status" in
      200|302|303|401|403) return 0 ;;
    esac
  fi
  die "Gerrit HTTP endpoint did not return a Gerrit runtime response"
}

check_ssh_endpoint() {
  local banner
  banner="$(timeout 5 bash -c 'exec 3<>"/dev/tcp/$0/$1"; IFS= read -r line <&3; printf "%s\n" "$line"' "$GERRIT_HOST" "$GERRIT_SSH_PORT")"
  grep -q '^SSH-2.0-GerritCodeReview' <<<"$banner" || die "Gerrit SSH endpoint did not return a Gerrit SSH banner"
}

check_ldap_access() {
  local host port
  read -r host port <<EOF
$(ldap_host_port)
EOF
  check_tcp_connect "$host" "$port" || die "LDAP endpoint is not reachable: $host:$port"
  check_ldap_bind_search
}

ldap_bind_password_file() {
  if [ -n "$LDAP_BIND_PASSWORD_FILE" ]; then
    [ -r "$LDAP_BIND_PASSWORD_FILE" ] || die "LDAP bind password file is not readable: $LDAP_BIND_PASSWORD_FILE"
    local secret
    secret="$(tr -d '\r\n' <"$LDAP_BIND_PASSWORD_FILE")"
    [ -n "$secret" ] || die "LDAP bind password file is empty: $LDAP_BIND_PASSWORD_FILE"
    is_placeholder "$secret" &&
      die "LDAP bind password file contains a placeholder secret"
    printf '%s\n' "$LDAP_BIND_PASSWORD_FILE"
    return 0
  fi
  if [ -n "$LDAP_BIND_PASSWORD" ]; then
    is_placeholder "$LDAP_BIND_PASSWORD" &&
      die "LDAP bind password value must be reviewed and must not be a placeholder"
    local tmp_file
    tmp_file="$(mktemp)"
    chmod 0600 "$tmp_file"
    printf '%s' "$LDAP_BIND_PASSWORD" >"$tmp_file"
    printf '%s\n' "$tmp_file"
    return 0
  fi
  die "BLOCKED: LDAP bind/search proof requires LDAP_BIND_PASSWORD_FILE or LDAP_BIND_PASSWORD; TCP reachability alone is not LDAP access proof"
}

check_ldap_bind_search() {
  local password_file cleanup_password_file
  if ! command -v ldapsearch >/dev/null 2>&1; then
    die "BLOCKED: ldapsearch is required to prove LDAP bind/search readiness"
  fi
  password_file="$(ldap_bind_password_file)"
  cleanup_password_file=0
  [ "$password_file" != "$LDAP_BIND_PASSWORD_FILE" ] && cleanup_password_file=1
  ldapsearch -x -H "$LDAP_URL" -D "$LDAP_BIND_DN" -y "$password_file" \
    -b "$LDAP_USER_BASE" -s base dn >/dev/null 2>&1 ||
    {
      [ "$cleanup_password_file" -eq 0 ] || rm -f "$password_file"
      die "BLOCKED: LDAP bind/search proof failed for configured user base"
    }
  ldapsearch -x -H "$LDAP_URL" -D "$LDAP_BIND_DN" -y "$password_file" \
    -b "$LDAP_GROUP_BASE" -s base dn >/dev/null 2>&1 ||
    {
      [ "$cleanup_password_file" -eq 0 ] || rm -f "$password_file"
      die "BLOCKED: LDAP bind/search proof failed for configured group base"
    }
  [ "$cleanup_password_file" -eq 0 ] || rm -f "$password_file"
}

check_plugin_readiness() {
  local missing
  validate_plugins
  missing=0
  if ! for_each_plugin check_plugin_file; then
    missing=1
  fi
  [ "$missing" -eq 0 ] || die "One or more Gerrit plugins from GERRIT_PLUGIN_LIST are not installed"
  check_runtime_plugin_readiness
}

check_plugin_file() {
  local plugin
  plugin="${1:?plugin required}"
  [ -f "$GERRIT_SITE_PATH/plugins/${plugin}.jar" ]
}

gerrit_ssh_log() {
  local name
  name="${1:?log name required}"
  mkdir -p "$GERRIT_LOG_DIR"
  printf '%s/gerrit-ssh-%s-%s.log\n' "$GERRIT_LOG_DIR" "$name" "$(timestamp_utc)"
}

runtime_plugin_list_log() {
  local log marker
  log="$(gerrit_ssh_log plugin-loads)"
  marker="$GERRIT_SITE_PATH/state/plugin-runtime-start.marker"
  if [ ! -f "$marker" ]; then
    printf 'BLOCKED: Gerrit runtime plugin load marker is missing; rerun startup before plugin readiness; log=%s\n' "$log" >&2
    return 1
  fi
  if ! awk -v marker="$(cat "$marker")" '
    index($0, marker) { seen = 1 }
    seen && index($0, "com.google.gerrit.server.plugins.PluginLoader : Loaded plugin ") { print }
  ' "$(gerrit_runtime_log)" >"$log" || [ ! -s "$log" ]; then
    printf 'BLOCKED: Gerrit runtime plugin load evidence is missing; log=%s\n' "$log" >&2
    return 1
  fi
  printf '%s\n' "$log"
}

check_secure_config_secret_handling() {
  local password_file reviewed_secret configured_secret cleanup_password_file
  password_file="$(ldap_bind_password_file)"
  cleanup_password_file=0
  [ "$password_file" = "$LDAP_BIND_PASSWORD_FILE" ] || cleanup_password_file=1
  reviewed_secret="$(tr -d '\r\n' <"$password_file")"
  [ -n "$reviewed_secret" ] || die "Reviewed LDAP bind secret is empty"
  is_placeholder "$reviewed_secret" &&
    die "Reviewed LDAP bind secret is still a placeholder"
  configured_secret="$(secure_config_password_value)"
  [ -n "$configured_secret" ] || die "Gerrit secure config password is missing"
  [ "$configured_secret" = "$reviewed_secret" ] ||
    die "Gerrit secure config password does not match the reviewed LDAP bind secret input"
  [ "$cleanup_password_file" -eq 0 ] || rm -f "$password_file"
}

check_plugin_runtime_loaded() {
  local plugin
  plugin="${1:?plugin required}"
  grep -F "Loaded plugin $plugin" "$GERRIT_RUNTIME_PLUGIN_LIST_LOG" >/dev/null
}

check_runtime_plugin_readiness() {
  local missing
  GERRIT_RUNTIME_PLUGIN_LIST_LOG="$(runtime_plugin_list_log)"
  missing=0
  if ! for_each_plugin check_plugin_runtime_loaded; then
    missing=1
  fi
  [ "$missing" -eq 0 ] ||
    die "One or more Gerrit plugins from GERRIT_PLUGIN_LIST are not loaded/enabled in the running Gerrit daemon; log=$GERRIT_RUNTIME_PLUGIN_LIST_LOG"
}

gerrit_pid_file() {
  printf '%s\n' "$GERRIT_SITE_PATH/logs/gerrit.pid"
}

gerrit_runtime_log() {
  printf '%s\n' "$GERRIT_SITE_PATH/logs/gerrit.log"
}

is_gerrit_running() {
  gerrit_daemon_pid >/dev/null 2>&1
}

run_as_gerrit_runtime() {
  local command_text
  command_text="${1:?command required}"
  if command -v runuser >/dev/null 2>&1; then
    runuser -u "$GERRIT_RUNTIME_ACCOUNT" -- sh -c "$command_text"
    return $?
  fi
  if command -v su >/dev/null 2>&1; then
    su -s /bin/sh "$GERRIT_RUNTIME_ACCOUNT" -c "$command_text"
    return $?
  fi
  die "BLOCKED: Gerrit runtime-account startup requires runuser or su"
}

prepare_gerrit_runtime_ownership() {
  require_command chown
  chown -R "$GERRIT_RUNTIME_ACCOUNT:$GERRIT_RUNTIME_GROUP" "$GERRIT_SITE_PATH"
}

gerrit_daemon_owner() {
  local pid
  pid="$(gerrit_daemon_pid)"
  ps -o user= -p "$pid" | awk '{print $1}'
}

gerrit_daemon_pid() {
  local pidfile pid
  pidfile="$(gerrit_pid_file)"
  if [ -s "$pidfile" ]; then
    pid="$(cat "$pidfile")"
    if [ -n "$pid" ] &&
      [ "$(ps -p "$pid" -o comm= 2>/dev/null | awk '{print $1}')" = "java" ] &&
      ps -p "$pid" -o args= 2>/dev/null | grep -F "$GERRIT_SITE_PATH" >/dev/null; then
      printf '%s\n' "$pid"
      return 0
    fi
  fi
  ps -eo pid=,comm=,args= |
    awk -v site="$GERRIT_SITE_PATH" '
      $2 == "java" && index($0, site) {
        print $1
        found = 1
        exit
      }
      END { exit !found }
    '
}

clear_stale_gerrit_runtime_state() {
  local pidfile stale_pid
  pidfile="$(gerrit_pid_file)"
  if [ -s "$pidfile" ]; then
    stale_pid="$(cat "$pidfile")"
    if [ -n "$stale_pid" ] &&
      ! { [ "$(ps -p "$stale_pid" -o comm= 2>/dev/null | awk '{print $1}')" = "java" ] &&
        ps -p "$stale_pid" -o args= 2>/dev/null | grep -F "$GERRIT_SITE_PATH" >/dev/null; }; then
      rm -f "$pidfile"
    fi
  fi
}

is_gerrit_site_initialized() {
  [ -x "$GERRIT_SITE_PATH/bin/gerrit.sh" ] &&
    [ -f "$GERRIT_SITE_PATH/etc/gerrit.config" ] &&
    [ -f "$GERRIT_SITE_PATH/etc/secure.config" ] &&
    [ -d "$GERRIT_SITE_PATH/git/All-Projects.git" ] &&
    [ -d "$GERRIT_SITE_PATH/git/All-Users.git" ]
}

remove_step7_deferred_integration_grants() {
  local repo_dir work_dir project_config
  repo_dir="$GERRIT_SITE_PATH/git/All-Projects.git"
  work_dir="$GERRIT_SITE_PATH/tmp/step7-all-projects-work"
  [ -d "$repo_dir" ] || return 0
  require_command git
  mkdir -p "$GERRIT_SITE_PATH/tmp"
  ensure_site_repo_worktree "$repo_dir" "$work_dir"
  run_as_gerrit_runtime "cd $(shell_quote "$work_dir") && git fetch origin refs/meta/config:refs/remotes/origin/meta-config >/dev/null 2>&1 && git checkout -B step7-meta-config refs/remotes/origin/meta-config >/dev/null"
  project_config="$work_dir/project.config"
  if [ -f "$project_config" ]; then
    git config -f "$project_config" --unset-all capability.streamEvents >/dev/null 2>&1 || true
    if grep -Eq 'label-Verified|\\[label "Verified"\\]|jenkins-gerrit|jenkins-gerrit-integration' "$project_config"; then
      die "Step 7 Gerrit-only site contains Jenkins integration project config before integration step"
    fi
    run_as_gerrit_runtime "cd $(shell_quote "$work_dir") && git add project.config && if ! git diff --cached --quiet; then git commit -m $(shell_quote "Remove deferred integration grants for Step 7") >/dev/null; fi && git push origin HEAD:refs/meta/config >/dev/null"
  fi
  write_text_file "$GERRIT_SITE_PATH/state/integration-prerequisites-deferred.status" \
    "jenkins_integration_prerequisites=deferred streamEvents_grants=absent"
}

ensure_gerrit_site_initialized_for_site_git() {
  local log java_opts
  verify_war_artifact "$GERRIT_SITE_PATH/bin/gerrit.war"
  require_command java
  check_runtime_account_readiness
  mkdir -p "$GERRIT_SITE_PATH/logs" "$GERRIT_SITE_PATH/run"
  if is_gerrit_site_initialized; then
    return 0
  fi
  prepare_gerrit_runtime_ownership
  log="$(gerrit_runtime_log)"
  java_opts="-Xms128m -Xmx512m"
  if [ ! -s "$log" ]; then
    printf 'timestamp=%s\n' "$(iso_timestamp_utc)" >"$log"
  fi
  printf 'command=java -jar gerrit.war init --batch runtime_account=%s lifecycle=configure-integration-site-git-bootstrap\n' "$GERRIT_RUNTIME_ACCOUNT" >>"$log"
  chown "$GERRIT_RUNTIME_ACCOUNT:$GERRIT_RUNTIME_GROUP" "$log"
  if ! run_as_gerrit_runtime "java $java_opts -jar $(shell_quote "$GERRIT_SITE_PATH/bin/gerrit.war") init --batch --no-auto-start -d $(shell_quote "$GERRIT_SITE_PATH")" >>"$log" 2>&1; then
    printf 'BLOCKED: Gerrit site bootstrap init failed before site-git integration mutation; log=%s\n' "$log" >&2
    return 1
  fi
  is_gerrit_site_initialized ||
    die "BLOCKED: Gerrit site bootstrap init did not produce the required initialized site layout for site-git integration"
}

assert_gerrit_daemon_owner() {
  local pid owner
  pid="$(gerrit_daemon_pid)" ||
    die "BLOCKED: Gerrit daemon PID could not be resolved for owner proof"
  printf '%s\n' "$pid" >"$(gerrit_pid_file)"
  owner="$(gerrit_daemon_owner)"
  [ "$owner" = "$GERRIT_RUNTIME_ACCOUNT" ] ||
    die "BLOCKED: Gerrit daemon process owner is '$owner', expected '$GERRIT_RUNTIME_ACCOUNT'"
}

start_real_gerrit() {
  local log java_opts rc startup_deadline installed_plugin_digest stored_plugin_digest marker
  verify_war_artifact "$GERRIT_SITE_PATH/bin/gerrit.war"
  require_command java
  require_command ps
  check_runtime_account_readiness
  mkdir -p "$GERRIT_SITE_PATH/logs" "$GERRIT_SITE_PATH/run"
  prepare_gerrit_runtime_ownership
  log="$(gerrit_runtime_log)"
  mkdir -p "$GERRIT_SITE_PATH/state"
  installed_plugin_digest="$(plugin_set_digest "$GERRIT_SITE_PATH/plugins")"
  stored_plugin_digest="$(cat "$GERRIT_SITE_PATH/state/runtime-plugin.digest" 2>/dev/null || true)"
  clear_stale_gerrit_runtime_state
  if is_gerrit_running; then
    if [ "$installed_plugin_digest" != "$stored_plugin_digest" ]; then
      die "BLOCKED: Installed Gerrit plugin digest changed while daemon is already running; restart Gerrit before validating plugin runtime evidence"
    fi
    assert_gerrit_daemon_owner
    return 0
  fi
  java_opts="-Xms128m -Xmx512m"
  if [ ! -x "$GERRIT_SITE_PATH/bin/gerrit.sh" ]; then
    printf 'timestamp=%s\n' "$(iso_timestamp_utc)" >"$log"
    printf 'command=java -jar gerrit.war init --batch runtime_account=%s\n' "$GERRIT_RUNTIME_ACCOUNT" >>"$log"
    chown "$GERRIT_RUNTIME_ACCOUNT:$GERRIT_RUNTIME_GROUP" "$log"
    if ! run_as_gerrit_runtime "java $java_opts -jar $(shell_quote "$GERRIT_SITE_PATH/bin/gerrit.war") init --batch --no-auto-start -d $(shell_quote "$GERRIT_SITE_PATH")" >>"$log" 2>&1; then
      printf 'BLOCKED: Gerrit init failed; artifact or config cannot support real startup; log=%s\n' "$log" >&2
      return 1
    fi
    remove_step7_deferred_integration_grants
    if is_gerrit_running; then
      assert_gerrit_daemon_owner
    fi
  fi
  if is_gerrit_running; then
    assert_gerrit_daemon_owner
    return 0
  fi
  clear_stale_gerrit_runtime_state
  prepare_gerrit_runtime_ownership
  marker="plugin-runtime-start-$(timestamp_utc)-$installed_plugin_digest"
  printf 'marker=%s\n' "$marker" >>"$log"
  printf '%s\n' "$marker" >"$GERRIT_SITE_PATH/state/plugin-runtime-start.marker"
  printf '%s\n' "$installed_plugin_digest" >"$GERRIT_SITE_PATH/state/runtime-plugin.digest"
  printf 'command=%s/bin/gerrit.sh run runtime_account=%s\n' "$GERRIT_SITE_PATH" "$GERRIT_RUNTIME_ACCOUNT" >>"$log"
  chown "$GERRIT_RUNTIME_ACCOUNT:$GERRIT_RUNTIME_GROUP" "$log"
  run_as_gerrit_runtime "$(shell_quote "$GERRIT_SITE_PATH/bin/gerrit.sh") run" >>"$log" 2>&1 &
  rc=1
  startup_deadline=$((SECONDS + 180))
  while [ "$SECONDS" -lt "$startup_deadline" ]; do
    clear_stale_gerrit_runtime_state
    if is_gerrit_running; then
      assert_gerrit_daemon_owner
      if check_tcp_connect "$GERRIT_HOST" "$GERRIT_HTTP_PORT" >/dev/null 2>&1 &&
        check_tcp_connect "$GERRIT_HOST" "$GERRIT_SSH_PORT" >/dev/null 2>&1; then
        rc=0
        break
      fi
    fi
    sleep 3
  done
  if [ "$rc" -ne 0 ] && grep -q 'Already Running!!' "$log" && is_gerrit_running; then
    assert_gerrit_daemon_owner
    if check_tcp_connect "$GERRIT_HOST" "$GERRIT_HTTP_PORT" >/dev/null 2>&1 &&
      check_tcp_connect "$GERRIT_HOST" "$GERRIT_SSH_PORT" >/dev/null 2>&1; then
      rc=0
    fi
  fi
  if [ "$rc" -ne 0 ]; then
    printf 'BLOCKED: Gerrit daemon did not remain running; log=%s\n' "$log" >&2
    return 1
  fi
}

check_integration_readiness() {
  grep -q '\[label "Verified"\]' "$GERRIT_SITE_PATH/etc/verified-label.config" || die "Verified label config is missing"
  grep -q "label-Verified = -1..+1 group $JENKINS_GERRIT_INTEGRATION_GROUP" "$GERRIT_SITE_PATH/etc/jenkins-integration-access.config" || die "Verified vote permission template is missing"
  grep -q "streamEvents = group $JENKINS_GERRIT_INTEGRATION_GROUP" "$GERRIT_SITE_PATH/etc/jenkins-integration-access.config" || die "stream-events permission template is missing"
  assert_no_unresolved_placeholders "$GERRIT_SITE_PATH/etc/jenkins-integration-access.config"
}

check_installed_artifact_freshness() {
  local rendered_dir staged_plugin_digest installed_plugin_digest
  cmp -s "$GERRIT_STAGED_ARTIFACT_DIR/gerrit-3.13.6.war" "$GERRIT_SITE_PATH/bin/gerrit.war" ||
    die "Installed Gerrit WAR does not match the staged Gerrit WAR input"
  cmp -s "$GERRIT_STAGED_ARTIFACT_DIR/manifest.txt" "$GERRIT_SITE_PATH/etc/artifact-manifest.txt" ||
    die "Installed artifact manifest copy does not match the staged manifest input"
  cmp -s "$GERRIT_STAGED_ARTIFACT_DIR/checksums.sha256" "$GERRIT_SITE_PATH/etc/artifact-checksums.sha256" ||
    die "Installed artifact checksum copy does not match the staged checksum input"

  rendered_dir="$(mktemp -d)"
  render_template "$GERRIT_STAGED_ARTIFACT_DIR/gerrit.config.template" "$rendered_dir/gerrit.config"
  assert_config_key_matches "$rendered_dir/gerrit.config" "$GERRIT_SITE_PATH/etc/gerrit.config" gerrit.canonicalWebUrl
  assert_config_key_matches "$rendered_dir/gerrit.config" "$GERRIT_SITE_PATH/etc/gerrit.config" gerrit.basePath
  assert_config_key_matches "$rendered_dir/gerrit.config" "$GERRIT_SITE_PATH/etc/gerrit.config" httpd.listenUrl
  assert_config_key_matches "$rendered_dir/gerrit.config" "$GERRIT_SITE_PATH/etc/gerrit.config" sshd.listenAddress
  assert_config_key_matches "$rendered_dir/gerrit.config" "$GERRIT_SITE_PATH/etc/gerrit.config" container.javaHome
  assert_config_key_matches "$rendered_dir/gerrit.config" "$GERRIT_SITE_PATH/etc/gerrit.config" auth.type
  assert_config_key_matches "$rendered_dir/gerrit.config" "$GERRIT_SITE_PATH/etc/gerrit.config" ldap.server
  assert_config_key_matches "$rendered_dir/gerrit.config" "$GERRIT_SITE_PATH/etc/gerrit.config" ldap.username
  assert_config_key_matches "$rendered_dir/gerrit.config" "$GERRIT_SITE_PATH/etc/gerrit.config" ldap.accountBase
  assert_config_key_matches "$rendered_dir/gerrit.config" "$GERRIT_SITE_PATH/etc/gerrit.config" ldap.groupBase
  assert_config_key_matches "$rendered_dir/gerrit.config" "$GERRIT_SITE_PATH/etc/gerrit.config" ldap.adminGroup
  rm -rf "$rendered_dir"

  staged_plugin_digest="$(plugin_set_digest "$GERRIT_STAGED_ARTIFACT_DIR/plugins")"
  installed_plugin_digest="$(plugin_set_digest "$GERRIT_SITE_PATH/plugins")"
  [ "$staged_plugin_digest" = "$installed_plugin_digest" ] ||
    die "Installed Gerrit plugin set does not match the staged plugin input"
}

verify_readiness_facts() {
  verify_staged_artifacts
  [ -f "$GERRIT_SITE_PATH/state/install.status" ] || die "Install readiness marker missing"
  [ -f "$GERRIT_SITE_PATH/etc/gerrit.config" ] || die "Gerrit config is missing"
  [ -f "$GERRIT_SITE_PATH/bin/gerrit.war" ] || die "Gerrit WAR is not installed"
  [ -s "$GERRIT_SITE_PATH/etc/gerrit.config" ] || die "Gerrit config is empty"
  [ -s "$GERRIT_SITE_PATH/etc/secure.config" ] || die "Gerrit secure config is empty"
  check_installed_artifact_freshness
  start_real_gerrit
  check_http_endpoint
  check_ssh_endpoint
  check_secure_config_secret_handling
  check_ldap_access
  check_plugin_readiness
}

cmd_validate() {
  load_env normal
  require_env_values
  confirm_mutation validate || return 0
  require_command ssh-keygen
  verify_readiness_facts
  cmd_collect_evidence >/dev/null
  printf 'status=pass command=validate startup=pass endpoint=pass ldap=pass ssh=pass plugins=pass integration=deferred evidence_dir=%s\n' "$GERRIT_EVIDENCE_DIR"
}

cmd_collect_evidence() {
  load_env normal
  apply_env_defaults
  require_env_values
  confirm_mutation collect-evidence || return 0
  require_command ssh-keygen
  verify_readiness_facts
  ensure_dirs
  local evidence input_fingerprint manifest checksum bounded_log service_log helper_version
  local q_mode q_time q_package_version q_helper_version q_role q_checkpoint q_command q_status
  local q_hosts q_endpoints q_input q_manifest q_checksum q_startup q_endpoint q_ldap q_ssh q_plugin
  local q_runtime_account q_checks q_log q_redaction
  evidence="$GERRIT_EVIDENCE_DIR/gerrit-readiness-$(timestamp_utc).json"
  bounded_log="$GERRIT_LOG_DIR/gerrit-collect-evidence-$(timestamp_utc).log"
  service_log="$(gerrit_runtime_log)"
  helper_version="gerrit-setup.sh $(git -C "$repo_root" rev-parse --short=12 HEAD 2>/dev/null || printf 'unknown')"
  input_fingerprint="$(printf '%s\n%s\n%s\n%s\n' "$GERRIT_HOST" "$GERRIT_HTTP_PORT" "$GERRIT_SSH_PORT" "$LDAP_URL" | sha256sum | awk '{print $1}')"
  manifest="$GERRIT_STAGED_ARTIFACT_DIR/manifest.txt"
  checksum="$GERRIT_STAGED_ARTIFACT_DIR/checksums.sha256"
  {
    printf 'timestamp=%s\n' "$(iso_timestamp_utc)"
    printf 'command=collect-evidence\n'
    printf 'verification_mode=%s\n' "$GERRIT_VERIFICATION_MODE"
    printf 'artifact_manifest=%s\n' "$manifest"
    printf 'checksum_reference=%s\n' "$checksum"
    printf 'observed=real-gerrit-daemon,http-runtime,ssh-banner,ldap-bind-search,plugins\n'
    printf 'integration_prerequisites=deferred-to-later-integration-step\n'
    printf 'redaction=secrets-not-recorded\n'
  } >"$bounded_log"
  [ -s "$bounded_log" ] || die "Bounded evidence log was not written: $bounded_log"
  [ -s "$service_log" ] || die "Gerrit daemon bounded log is missing: $service_log"
  q_mode="$(json_quote "$GERRIT_VERIFICATION_MODE")"
  q_time="$(json_quote "$(iso_timestamp_utc)")"
  q_package_version="$(json_quote "gerrit-jenkins-setup")"
  q_helper_version="$(json_quote "$helper_version")"
  q_role="$(json_quote "gerrit")"
  q_checkpoint="$(json_quote "gerrit-readiness")"
  q_command="$(json_quote "gerrit-setup.sh collect-evidence")"
  q_status="$(json_quote "pass")"
  q_hosts="$(json_quote "gerrit_host=$GERRIT_HOST")"
  q_endpoints="$(json_quote "http=http://$GERRIT_HOST:$GERRIT_HTTP_PORT/;ssh=$GERRIT_HOST:$GERRIT_SSH_PORT;ldap=$LDAP_URL")"
  q_input="$(json_quote "$input_fingerprint")"
  q_manifest="$(json_quote "$manifest")"
  q_checksum="$(json_quote "$checksum")"
  q_startup="$(json_quote "pass: real Gerrit daemon started under runtime account $GERRIT_RUNTIME_ACCOUNT")"
  q_endpoint="$(json_quote "pass: Gerrit HTTP runtime endpoint responded on $GERRIT_HOST:$GERRIT_HTTP_PORT")"
  q_ldap="$(json_quote "pass: LDAP bind/search succeeded for configured user/group bases")"
  q_ssh="$(json_quote "pass: Gerrit SSH banner responded on $GERRIT_HOST:$GERRIT_SSH_PORT")"
  q_plugin="$(json_quote "pass: plugin files present and runtime plugin listing succeeded for $GERRIT_PLUGIN_LIST")"
  q_runtime_account="$(json_quote "pass: Gerrit daemon owner verified as $GERRIT_RUNTIME_ACCOUNT")"
  q_checks="$(json_quote "real Gerrit daemon process, HTTP runtime endpoint, Gerrit SSH banner, LDAP bind/search access, installed plugin set; Jenkins ACL/label/capability prerequisites deferred to later integration step; reviewed LDAP secret handling")"
  q_log="$(json_quote "$bounded_log;$service_log")"
  q_redaction="$(json_quote "secrets-redacted; private keys, passwords, tokens, and LDAP bind secrets not recorded")"
  cat >"$evidence" <<EOF
{
  "verification_mode": $q_mode,
  "timestamp": $q_time,
  "package_version": $q_package_version,
  "helper_command_version": $q_helper_version,
  "role_or_environment": $q_role,
  "checkpoint_name": $q_checkpoint,
  "command_name": $q_command,
  "status": $q_status,
  "hostnames_and_service_endpoints": $q_hosts,
  "service_endpoints": $q_endpoints,
  "reviewed_input_fingerprint": $q_input,
  "artifact_manifest_references": $q_manifest,
  "checksum_references": $q_checksum,
  "checksum_verification_result": "pass",
  "service_startup_checks": $q_startup,
  "endpoint_checks": $q_endpoint,
  "ldap_checks": $q_ldap,
  "ssh_checks": $q_ssh,
  "plugin_checks": $q_plugin,
  "runtime_account_checks": $q_runtime_account,
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
      print-env-template|preflight|prepare-artifacts|install|configure|configure-integration|validate|collect-evidence)
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
    configure) cmd_configure ;;
    configure-integration) cmd_configure_integration ;;
    validate) cmd_validate ;;
    collect-evidence) cmd_collect_evidence ;;
    *) die_usage "Unknown command: $command_name" ;;
  esac
}

main "$@"
