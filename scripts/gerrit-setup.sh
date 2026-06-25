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
cleanup_paths=()

readonly GERRIT_INTERNAL_VERSION="3.13.6"
readonly GERRIT_INTERNAL_JAVA_VERSION="21"
readonly GERRIT_INTERNAL_UBUNTU_RELEASE="24.04"
readonly GERRIT_INTERNAL_UBUNTU_CODENAME="noble"
readonly GERRIT_INTERNAL_API_LINE="3.13"
readonly GERRIT_NATIVE_SITE_PATH="/srv/gerrit"
readonly GERRIT_BUNDLE_FACTORY_WORK_DIR="/var/lib/loopforge/artifact-bundle-work/gerrit"
readonly GERRIT_STAGED_BUNDLE_PAYLOAD_DIR="/opt/gerrit-artifacts-bundle/gerrit"

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

cleanup_registered_paths() {
  local path
  for path in "${cleanup_paths[@]}"; do
    [ -n "$path" ] || continue
    rm -rf -- "$path"
  done
}

register_cleanup_path() {
  cleanup_paths+=("${1:?path required}")
}

trap cleanup_registered_paths EXIT

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
    "$dir" >/tmp/gerrit-artifact-key-scan.$$ 2>/dev/null; then
    bad_path="$(sed -n '1p' "/tmp/gerrit-artifact-key-scan.$$")"
    rm -f "/tmp/gerrit-artifact-key-scan.$$"
    die "Artifact bundle must not contain SSH key material: $bad_path"
  fi
  rm -f "/tmp/gerrit-artifact-key-scan.$$"
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
GERRIT_HOST
GERRIT_HTTP_PORT
GERRIT_SSH_PORT
GERRIT_CANONICAL_WEB_URL
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
  assert_internal_baseline_value GERRIT_VERSION "$GERRIT_INTERNAL_VERSION"
  assert_internal_baseline_value GERRIT_JAVA_VERSION "$GERRIT_INTERNAL_JAVA_VERSION"
  assert_internal_baseline_value GERRIT_UBUNTU_RELEASE "$GERRIT_INTERNAL_UBUNTU_RELEASE"
  assert_internal_baseline_value GERRIT_UBUNTU_CODENAME "$GERRIT_INTERNAL_UBUNTU_CODENAME"
  GERRIT_VERSION="$GERRIT_INTERNAL_VERSION"
  GERRIT_JAVA_VERSION="$GERRIT_INTERNAL_JAVA_VERSION"
  GERRIT_UBUNTU_RELEASE="$GERRIT_INTERNAL_UBUNTU_RELEASE"
  GERRIT_UBUNTU_CODENAME="$GERRIT_INTERNAL_UBUNTU_CODENAME"
  GERRIT_HOST="${GERRIT_HOST:-gerrit-target}"
  GERRIT_HTTP_PORT="${GERRIT_HTTP_PORT:-8080}"
  GERRIT_SSH_PORT="${GERRIT_SSH_PORT:-29418}"
  GERRIT_CANONICAL_WEB_URL="${GERRIT_CANONICAL_WEB_URL:-http://$GERRIT_HOST:$GERRIT_HTTP_PORT/}"
  GERRIT_RUNTIME_ACCOUNT="${GERRIT_RUNTIME_ACCOUNT:-gerrit}"
  GERRIT_RUNTIME_GROUP="${GERRIT_RUNTIME_GROUP:-$GERRIT_RUNTIME_ACCOUNT}"
  GERRIT_JAVA_HOME="${GERRIT_JAVA_HOME:-/usr/lib/jvm/java-${GERRIT_JAVA_VERSION}-openjdk-amd64}"
  GERRIT_SITE_PATH="${GERRIT_SITE_PATH:-$GERRIT_NATIVE_SITE_PATH}"
  GERRIT_STAGED_ARTIFACT_DIR="${GERRIT_STAGED_ARTIFACT_DIR:-$GERRIT_STAGED_BUNDLE_PAYLOAD_DIR}"
  GERRIT_LOCAL_ARTIFACT_OUTPUT_DIR="${GERRIT_LOCAL_ARTIFACT_OUTPUT_DIR:-$GERRIT_BUNDLE_FACTORY_WORK_DIR}"
  GERRIT_ARTIFACT_OUTPUT_DIR="${GERRIT_ARTIFACT_OUTPUT_DIR:-$GERRIT_LOCAL_ARTIFACT_OUTPUT_DIR}"
  GERRIT_PLUGIN_LIST="${GERRIT_PLUGIN_LIST:-events-log,metrics-reporter-prometheus,healthcheck}"
  GERRIT_PLUGIN_SOURCE_DIR="${GERRIT_PLUGIN_SOURCE_DIR:-}"
  GERRIT_DOWNLOAD_ARTIFACTS="${GERRIT_DOWNLOAD_ARTIFACTS:-0}"
  GERRIT_OS_DEPENDENCIES="${GERRIT_OS_DEPENDENCIES:-ca-certificates,curl,openssh-client,openjdk-21-jre-headless,rsync,tar}"
  GERRIT_VERIFICATION_MODE="${GERRIT_VERIFICATION_MODE:-docker-simulation}"
  GERRIT_EVIDENCE_DIR="${GERRIT_EVIDENCE_DIR:-/var/lib/loopforge/evidence}"
  GERRIT_LOG_DIR="${GERRIT_LOG_DIR:-/var/log/loopforge}"
  LDAP_URL="${LDAP_URL:-ldap://ldap:389}"
  LDAP_BIND_DN="${LDAP_BIND_DN:-cn=readonly,dc=example,dc=test}"
  LDAP_BIND_PASSWORD_FILE="${LDAP_BIND_PASSWORD_FILE:-}"
  LDAP_BIND_PASSWORD="${LDAP_BIND_PASSWORD:-}"
  LDAP_USER_BASE="${LDAP_USER_BASE:-ou=people,dc=example,dc=test}"
  LDAP_GROUP_BASE="${LDAP_GROUP_BASE:-ou=groups,dc=example,dc=test}"
  GERRIT_ADMIN_ACCOUNT="${GERRIT_ADMIN_ACCOUNT:-gerrit-admin}"
  GERRIT_ADMIN_GROUP="${GERRIT_ADMIN_GROUP:-gerrit-admins}"
  GERRIT_VERIFICATION_PROJECT="${GERRIT_VERIFICATION_PROJECT:-verification-disposable-gerrit}"
  GERRIT_VERIFICATION_REF_PATTERN="${GERRIT_VERIFICATION_REF_PATTERN:-refs/*}"
  case "${HARNESS_ENVIRONMENT:-}" in
    bundle-factory)
      GERRIT_ARTIFACT_OUTPUT_DIR="$GERRIT_BUNDLE_FACTORY_WORK_DIR"
      ;;
    gerrit-target)
      GERRIT_STAGED_ARTIFACT_DIR="$GERRIT_STAGED_BUNDLE_PAYLOAD_DIR"
      GERRIT_ARTIFACT_OUTPUT_DIR="$GERRIT_BUNDLE_FACTORY_WORK_DIR"
      ;;
  esac
}

assert_internal_baseline_value() {
  local name expected actual
  name="${1:?name required}"
  expected="${2:?expected value required}"
  actual="$(value_or_default "$name" "")"
  if [ -n "$actual" ] && [ "$actual" != "$expected" ]; then
    die "$name is an internal Gerrit helper baseline constant and must remain $expected for v1"
  fi
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

is_docker_simulation() {
  [ "${HARNESS_MODE:-}" = "docker-simulation" ] &&
    [ "${HARNESS_ENVIRONMENT:-}" = "gerrit-target" ] &&
    [ "$GERRIT_VERIFICATION_MODE" = "docker-simulation" ]
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
  text="${text//\{\{GERRIT_CANONICAL_WEB_URL\}\}/$GERRIT_CANONICAL_WEB_URL}"
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
  for_each_plugin require_plugin_catalog_entry
}

plugin_catalog_entry() {
  local plugin
  plugin="${1:?plugin required}"
  case "$plugin" in
    events-log)
      printf '%s\t%s\t%s\t%s\n' \
        "events-log.jar" \
        "https://gerrit-ci.gerritforge.com/job/plugin-events-log-bazel-stable-3.13/lastSuccessfulBuild/artifact/bazel-bin/plugins/events-log/events-log.jar" \
        "7c36b24e0885546c0a09502c022386b88b5894b649fba6b4c1cd595d23c7c695" \
        "$GERRIT_INTERNAL_API_LINE"
      ;;
    metrics-reporter-prometheus)
      printf '%s\t%s\t%s\t%s\n' \
        "metrics-reporter-prometheus.jar" \
        "https://gerrit-ci.gerritforge.com/job/plugin-metrics-reporter-prometheus-bazel-stable-3.13/lastSuccessfulBuild/artifact/bazel-bin/plugins/metrics-reporter-prometheus/metrics-reporter-prometheus.jar" \
        "d1edafbd620b1dbab76530788cf8af7b279eb935e6ade788589fb69e3e20f8d3" \
        "$GERRIT_INTERNAL_API_LINE"
      ;;
    healthcheck)
      printf '%s\t%s\t%s\t%s\n' \
        "healthcheck.jar" \
        "https://gerrit-ci.gerritforge.com/job/plugin-healthcheck-bazel-stable-3.13/lastSuccessfulBuild/artifact/bazel-bin/plugins/healthcheck/healthcheck.jar" \
        "289a931fdf0aa251c306c1cf2914635267a818f7e4abbd2862d4406a80885798" \
        "$GERRIT_INTERNAL_API_LINE"
      ;;
    *)
      die "No approved Gerrit plugin source catalog entry for selected plugin: $plugin"
      ;;
  esac
}

plugin_catalog_field() {
  local plugin field jar url sha api
  plugin="${1:?plugin required}"
  field="${2:?field required}"
  IFS=$'\t' read -r jar url sha api <<EOF
$(plugin_catalog_entry "$plugin")
EOF
  case "$field" in
    jar) printf '%s\n' "$jar" ;;
    url) printf '%s\n' "$url" ;;
    sha256) printf '%s\n' "$sha" ;;
    api_line) printf '%s\n' "$api" ;;
    *) die "Unknown Gerrit plugin source catalog field: $field" ;;
  esac
}

require_plugin_catalog_entry() {
  plugin_catalog_entry "${1:?plugin required}" >/dev/null
}

plugin_list_values() {
  validate_plugins
  printf '%s\n' "$GERRIT_PLUGIN_LIST" | tr ',' '\n'
}

expected_plugin_jars() {
  local plugin
  plugin_list_values | while IFS= read -r plugin; do
    plugin_catalog_field "$plugin" jar
  done | sort
}

actual_plugin_jars() {
  local plugin_dir
  plugin_dir="${1:?plugin dir required}"
  [ -d "$plugin_dir" ] || die "Missing Gerrit plugin directory: $plugin_dir"
  find "$plugin_dir" -maxdepth 1 -type f -name '*.jar' -printf '%f\n' | sort
}

assert_no_unexpected_plugin_tree_entries() {
  local plugin_dir unexpected
  plugin_dir="${1:?plugin dir required}"
  unexpected="$(
    find "$plugin_dir" -mindepth 1 ! -type f -print -quit
  )"
  [ -z "$unexpected" ] || die "Gerrit plugin entries must be regular top-level jar files: $unexpected"
  unexpected="$(
    find "$plugin_dir" -mindepth 2 -type f -print -quit
  )"
  [ -z "$unexpected" ] || die "Nested Gerrit plugin files are not allowed: $unexpected"
  unexpected="$(
    find "$plugin_dir" -maxdepth 1 -type f ! -name '*.jar' -print -quit
  )"
  [ -z "$unexpected" ] || die "Unexpected non-jar Gerrit plugin file: $unexpected"
}

assert_plugin_jar_set_exact() {
  local plugin_dir tmpdir expected actual missing unexpected missing_list unexpected_list
  plugin_dir="${1:?plugin dir required}"
  tmpdir="$(mktemp -d)"
  register_cleanup_path "$tmpdir"
  expected="$tmpdir/expected"
  actual="$tmpdir/actual"
  missing="$tmpdir/missing"
  unexpected="$tmpdir/unexpected"
  assert_no_unexpected_plugin_tree_entries "$plugin_dir"
  expected_plugin_jars >"$expected" || die "Could not generate expected Gerrit plugin jar list"
  actual_plugin_jars "$plugin_dir" >"$actual" || die "Could not generate actual Gerrit plugin jar list"
  comm -23 "$expected" "$actual" >"$missing" || die "Could not compare missing Gerrit plugin jars"
  comm -13 "$expected" "$actual" >"$unexpected" || die "Could not compare unexpected Gerrit plugin jars"
  if [ -s "$missing" ]; then
    missing_list="$(paste -sd, "$missing")"
    die "Missing expected Gerrit plugin jars in $plugin_dir: $missing_list"
  fi
  if [ -s "$unexpected" ]; then
    unexpected_list="$(paste -sd, "$unexpected")"
    die "Unexpected Gerrit plugin jars in $plugin_dir: $unexpected_list"
  fi
  rm -rf "$tmpdir"
}

assert_plugin_artifact_manifest_matches() {
  local plugin_dir manifest tmpdir actual
  plugin_dir="${1:?plugin dir required}"
  manifest="${2:?plugin artifact manifest required}"
  [ -f "$manifest" ] || die "Missing Gerrit plugin artifact manifest: $manifest"
  tmpdir="$(mktemp -d)"
  register_cleanup_path "$tmpdir"
  actual="$tmpdir/actual"
  actual_plugin_jars "$plugin_dir" >"$actual" || die "Could not generate actual Gerrit plugin artifact manifest"
  if ! cmp -s "$actual" "$manifest"; then
    die "Gerrit plugin artifact manifest does not match staged plugin jar set: $manifest"
  fi
  rm -rf "$tmpdir"
}

verify_plugin_artifacts_in_dir() {
  local plugin_dir plugin jar
  plugin_dir="${1:?plugin dir required}"
  assert_plugin_jar_set_exact "$plugin_dir"
  plugin_list_values | while IFS= read -r plugin; do
    jar="$plugin_dir/$(plugin_catalog_field "$plugin" jar)"
    verify_plugin_artifact_file "$plugin" "$jar"
  done
}

write_plugin_metadata_report_for_dir() {
  local plugin_dir report plugin file jar sha plugin_name api_version expected_api_line url
  plugin_dir="${1:?plugin dir required}"
  report="${2:?metadata report required}"
  {
    printf 'plugin\tjar\tsha256\tgerrit_plugin_name\tgerrit_api_version\texpected_api_line\tsource_url\n'
    plugin_list_values | while IFS= read -r plugin; do
      file="$(plugin_catalog_field "$plugin" jar)"
      jar="$plugin_dir/$file"
      verify_plugin_artifact_file "$plugin" "$jar"
      sha="$(sha256_file "$jar")"
      plugin_name="$(manifest_attribute "$jar" Gerrit-PluginName)"
      api_version="$(manifest_attribute "$jar" Gerrit-ApiVersion)"
      expected_api_line="$(plugin_catalog_field "$plugin" api_line)"
      url="$(plugin_catalog_field "$plugin" url)"
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$plugin" "$file" "$sha" "$plugin_name" "$api_version" "$expected_api_line" "$url"
    done
  } >"$report"
}

assert_plugin_metadata_report_matches() {
  local plugin_dir report tmpdir actual
  plugin_dir="${1:?plugin dir required}"
  report="${2:?metadata report required}"
  [ -f "$report" ] || die "Missing Gerrit plugin metadata report: $report"
  tmpdir="$(mktemp -d)"
  register_cleanup_path "$tmpdir"
  actual="$tmpdir/actual"
  write_plugin_metadata_report_for_dir "$plugin_dir" "$actual"
  if ! cmp -s "$actual" "$report"; then
    die "Gerrit plugin metadata report does not match plugin jars and source catalog: $report"
  fi
  rm -rf "$tmpdir"
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
  expected="ca-certificates,curl,openssh-client,openjdk-21-jre-headless,rsync,tar"
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
    openssh-client) command_name="ssh" ;;
    openjdk-21-jre-headless) command_name="java" ;;
    rsync) command_name="rsync" ;;
    tar) command_name="tar" ;;
    *) return 0 ;;
  esac
  if ! command -v "$command_name" >/dev/null 2>&1; then
    if is_docker_simulation; then
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
  [ "$GERRIT_SITE_PATH" = "$GERRIT_NATIVE_SITE_PATH" ] ||
    die "GERRIT_SITE_PATH must be $GERRIT_NATIVE_SITE_PATH, got $GERRIT_SITE_PATH"
  require_runtime_account_home "$GERRIT_RUNTIME_ACCOUNT" "$GERRIT_RUNTIME_GROUP" "$GERRIT_NATIVE_SITE_PATH" "Gerrit"
  require_product_home_ownership "$GERRIT_NATIVE_SITE_PATH" "$GERRIT_RUNTIME_ACCOUNT" "$GERRIT_RUNTIME_GROUP" "Gerrit"
}

manifest_attribute() {
  local jar key
  jar="${1:?jar required}"
  key="${2:?manifest key required}"
  unzip -p "$jar" META-INF/MANIFEST.MF 2>/dev/null |
    awk -v key="$key" '
      BEGIN { value = ""; collecting = 0 }
      $0 ~ "\r$" { sub(/\r$/, "") }
      index($0, key ": ") == 1 {
        value = substr($0, length(key) + 3)
        collecting = 1
        next
      }
      collecting && substr($0, 1, 1) == " " {
        value = value substr($0, 2)
        next
      }
      collecting { collecting = 0 }
      END { print value }
    '
}

verify_plugin_artifact_file() {
  local plugin jar expected_jar expected_sha expected_api_line actual_sha plugin_name api_version
  plugin="${1:?plugin required}"
  jar="${2:?plugin jar required}"
  expected_jar="$(plugin_catalog_field "$plugin" jar)"
  expected_sha="$(plugin_catalog_field "$plugin" sha256)"
  expected_api_line="$(plugin_catalog_field "$plugin" api_line)"
  [ "$(basename "$jar")" = "$expected_jar" ] ||
    die "Gerrit plugin jar filename for $plugin must be $expected_jar: $jar"
  [ -s "$jar" ] || die "Gerrit plugin jar is missing or empty: $jar"
  unzip -t "$jar" >/dev/null 2>&1 ||
    die "BLOCKED: Gerrit plugin artifact is not a valid jar archive: $jar"
  plugin_name="$(manifest_attribute "$jar" Gerrit-PluginName)"
  [ "$plugin_name" = "$plugin" ] ||
    die "Gerrit plugin artifact metadata mismatch for $plugin: Gerrit-PluginName=$plugin_name file=$jar"
  api_version="$(manifest_attribute "$jar" Gerrit-ApiVersion)"
  case "$api_version" in
    "$expected_api_line".*|"$expected_api_line".*-SNAPSHOT)
      ;;
    *)
      die "Gerrit plugin artifact API mismatch for $plugin: Gerrit-ApiVersion=$api_version expected=${expected_api_line}.x or ${expected_api_line}.x-SNAPSHOT"
      ;;
  esac
  actual_sha="$(sha256_file "$jar")"
  [ "$actual_sha" = "$expected_sha" ] ||
    die "Gerrit plugin artifact SHA256 mismatch for $plugin: expected=$expected_sha actual=$actual_sha file=$jar"
}

write_plugin_artifact() {
  local plugin source jar url expected_jar
  plugin="${1:?plugin required}"
  expected_jar="$(plugin_catalog_field "$plugin" jar)"
  jar="$GERRIT_ARTIFACT_OUTPUT_DIR/plugins/$expected_jar"
  mkdir -p "$(dirname "$jar")"
  if [ -n "$GERRIT_PLUGIN_SOURCE_DIR" ]; then
    source="$GERRIT_PLUGIN_SOURCE_DIR/$expected_jar"
    [ -f "$source" ] || die "GERRIT_PLUGIN_SOURCE_DIR is missing selected plugin artifact: $source"
    cp "$source" "$jar"
  elif [ "$GERRIT_DOWNLOAD_ARTIFACTS" = "1" ]; then
    require_command wget
    url="$(plugin_catalog_field "$plugin" url)"
    printf 'simulation-only public internet use: downloading Gerrit plugin artifact %s\n' "$plugin" >>"$GERRIT_ARTIFACT_OUTPUT_DIR/source-boundary.log"
    rm -f "$jar"
    wget -nv --show-progress=off --tries=5 --timeout=30 --read-timeout=60 \
      -O "$jar" "$url" >>"$GERRIT_ARTIFACT_OUTPUT_DIR/source-boundary.log" 2>&1
  else
    printf 'BLOCKED: prepare-artifacts requires GERRIT_PLUGIN_SOURCE_DIR or GERRIT_DOWNLOAD_ARTIFACTS=1 for selected Gerrit plugin jars\n' >&2
    return 1
  fi
  verify_plugin_artifact_file "$plugin" "$jar"
}

assert_plugin_source_dir_safe() {
  local source_dir artifact_dir output_plugins source_abs artifact_abs output_abs
  source_dir="${GERRIT_PLUGIN_SOURCE_DIR:-}"
  [ -n "$source_dir" ] || return 0
  artifact_dir="$GERRIT_ARTIFACT_OUTPUT_DIR"
  output_plugins="$GERRIT_ARTIFACT_OUTPUT_DIR/plugins"
  source_abs="$(cd "$source_dir" 2>/dev/null && pwd -P)" ||
    die "GERRIT_PLUGIN_SOURCE_DIR is not readable: $source_dir"
  mkdir -p "$artifact_dir" "$output_plugins"
  artifact_abs="$(cd "$artifact_dir" && pwd -P)" ||
    die "Could not resolve Gerrit artifact output directory: $artifact_dir"
  output_abs="$(cd "$output_plugins" && pwd -P)" ||
    die "Could not resolve Gerrit plugin output directory: $output_plugins"
  case "$source_abs" in
    "$artifact_abs"|"$artifact_abs"/*|"$output_abs"|"$output_abs"/*)
      die "GERRIT_PLUGIN_SOURCE_DIR must not overlap GERRIT_ARTIFACT_OUTPUT_DIR"
      ;;
  esac
  case "$artifact_abs" in
    "$source_abs"/*)
      die "GERRIT_PLUGIN_SOURCE_DIR must not overlap GERRIT_ARTIFACT_OUTPUT_DIR"
      ;;
  esac
  case "$output_abs" in
    "$source_abs"/*)
      die "GERRIT_PLUGIN_SOURCE_DIR must not overlap GERRIT_ARTIFACT_OUTPUT_DIR"
      ;;
  esac
}

verify_staged_artifacts() {
  local manifest checksums plugin_manifest plugin_metadata plugin_checksums
  manifest="$GERRIT_STAGED_ARTIFACT_DIR/manifest.txt"
  checksums="$GERRIT_STAGED_ARTIFACT_DIR/checksums.sha256"
  plugin_manifest="$GERRIT_STAGED_ARTIFACT_DIR/plugin-artifacts.manifest"
  plugin_metadata="$GERRIT_STAGED_ARTIFACT_DIR/plugin-metadata.report"
  plugin_checksums="$GERRIT_STAGED_ARTIFACT_DIR/plugin-checksums.sha256"
  [ -f "$manifest" ] || die "Missing staged Gerrit manifest: $manifest"
  [ -f "$checksums" ] || die "Missing staged Gerrit checksums: $checksums"
  [ -f "$plugin_manifest" ] || die "Missing staged Gerrit plugin artifact manifest: $plugin_manifest"
  [ -f "$plugin_metadata" ] || die "Missing staged Gerrit plugin metadata report: $plugin_metadata"
  [ -f "$plugin_checksums" ] || die "Missing staged Gerrit plugin checksums: $plugin_checksums"
  (cd "$GERRIT_STAGED_ARTIFACT_DIR" && sha256sum -c checksums.sha256) >/dev/null
  (cd "$GERRIT_STAGED_ARTIFACT_DIR" && sha256sum -c plugin-checksums.sha256) >/dev/null
  awk -F= '
    $1 == "harness_manifest_version" && $2 == "1" { h=1 }
    $1 == "role" && $2 == "gerrit" { r=1 }
    $1 == "gerrit_version" && $2 == "3.13.6" { g=1 }
    $1 == "java_version" && $2 == "21" { j=1 }
    $1 == "ubuntu_release" && $2 == "24.04" { u=1 }
    $1 == "ubuntu_codename" && $2 == "noble" { n=1 }
    $1 == "artifact_source" && $2 == "curated-bundle-factory" { a=1 }
    $1 == "os_dependency_source" && $2 == "approved-internal-os-repos" { o=1 }
    $1 == "public_internet_fallback" && $2 == "simulation-only" { p=1 }
    $1 == "bundle_contains_keys" && $2 == "no" { k=1 }
    END { exit !(h && r && g && j && u && n && a && o && p && k) }
  ' "$manifest" || die "Staged manifest does not match the Gerrit Version Baseline"
  verify_plugin_artifacts_in_dir "$GERRIT_STAGED_ARTIFACT_DIR/plugins"
  assert_plugin_artifact_manifest_matches "$GERRIT_STAGED_ARTIFACT_DIR/plugins" "$plugin_manifest"
  assert_plugin_metadata_report_matches "$GERRIT_STAGED_ARTIFACT_DIR/plugins" "$plugin_metadata"
  assert_no_artifact_key_material "$GERRIT_STAGED_ARTIFACT_DIR"
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
  check_runtime_account_readiness
  if [ "$dry_run" -eq 0 ]; then
    check_os_dependency_expectations
    check_disk_space "$GERRIT_ARTIFACT_OUTPUT_DIR" 1048576
    check_disk_space "$GERRIT_SITE_PATH" 1048576
    check_host_resolution
    check_ldap_access
  fi
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
os_dependency_source=approved-internal-os-repos
public_internet_fallback=simulation-only
bundle_contains_keys=no
plugins=$GERRIT_PLUGIN_LIST
war=gerrit-3.13.6.war
plugin_artifacts=plugin-artifacts.manifest
plugin_metadata=plugin-metadata.report
plugin_checksums=plugin-checksums.sha256
EOF
}

write_plugin_manifests() {
  assert_plugin_jar_set_exact "$GERRIT_ARTIFACT_OUTPUT_DIR/plugins"
  (
    cd "$GERRIT_ARTIFACT_OUTPUT_DIR"
    find plugins -type f -name '*.jar' -printf '%f\n' | sort >plugin-artifacts.manifest
    find plugins -type f -name '*.jar' -print0 |
      sort -z |
      xargs -0 sha256sum >plugin-checksums.sha256
  )
  write_plugin_metadata_report_for_dir "$GERRIT_ARTIFACT_OUTPUT_DIR/plugins" "$GERRIT_ARTIFACT_OUTPUT_DIR/plugin-metadata.report"
  assert_plugin_artifact_manifest_matches "$GERRIT_ARTIFACT_OUTPUT_DIR/plugins" "$GERRIT_ARTIFACT_OUTPUT_DIR/plugin-artifacts.manifest"
  assert_plugin_metadata_report_matches "$GERRIT_ARTIFACT_OUTPUT_DIR/plugins" "$GERRIT_ARTIFACT_OUTPUT_DIR/plugin-metadata.report"
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
    wget -nv --show-progress=off --tries=5 --timeout=30 --read-timeout=60 \
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
  if ! printf '%s\n' "$war_entries" | awk '
    $0 == "Main.class" { main = 1 }
    $0 == "WEB-INF/web.xml" { web = 1 }
    $0 == "com/google/gerrit/launcher/GerritLauncher.class" { launcher = 1 }
    END { exit !(main && web && launcher) }
  '; then
    die "BLOCKED: Gerrit WAR does not look like a real Gerrit application artifact: $war"
  fi
}

cmd_prepare_artifacts() {
  load_env normal
  apply_env_defaults
  confirm_mutation prepare-artifacts || return 0
  require_command sha256sum
  require_command unzip
  validate_plugins
  mkdir -p "$GERRIT_ARTIFACT_OUTPUT_DIR/plugins"
  assert_plugin_source_dir_safe
  rm -f "$GERRIT_ARTIFACT_OUTPUT_DIR/plugins/"*.jar
  prepare_real_gerrit_war
  for_each_plugin write_plugin_artifact
  write_plugin_manifests
  rm -f "$GERRIT_ARTIFACT_OUTPUT_DIR/jenkins-gerrit.pub"
  cp "$repo_root/templates/gerrit/gerrit.config.template" "$GERRIT_ARTIFACT_OUTPUT_DIR/gerrit.config.template"
  cp "$repo_root/templates/gerrit/secure.config.template" "$GERRIT_ARTIFACT_OUTPUT_DIR/secure.config.template"
  write_manifest
  assert_no_artifact_key_material "$GERRIT_ARTIFACT_OUTPUT_DIR"
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
  check_runtime_account_readiness
  confirm_mutation install || return 0
  verify_staged_artifacts
  ensure_dirs
  mkdir -p "$GERRIT_SITE_PATH/bin" "$GERRIT_SITE_PATH/plugins" "$GERRIT_SITE_PATH/etc" "$GERRIT_SITE_PATH/logs"
  verify_war_artifact "$GERRIT_STAGED_ARTIFACT_DIR/gerrit-3.13.6.war"
  cp "$GERRIT_STAGED_ARTIFACT_DIR/gerrit-3.13.6.war" "$GERRIT_SITE_PATH/bin/gerrit.war"
  find "$GERRIT_SITE_PATH/plugins" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
  cp -R "$GERRIT_STAGED_ARTIFACT_DIR/plugins/." "$GERRIT_SITE_PATH/plugins/"
  verify_plugin_artifacts_in_dir "$GERRIT_SITE_PATH/plugins"
  cp "$GERRIT_STAGED_ARTIFACT_DIR/manifest.txt" "$GERRIT_SITE_PATH/etc/artifact-manifest.txt"
  cp "$GERRIT_STAGED_ARTIFACT_DIR/checksums.sha256" "$GERRIT_SITE_PATH/etc/artifact-checksums.sha256"
  cp "$GERRIT_STAGED_ARTIFACT_DIR/plugin-artifacts.manifest" "$GERRIT_SITE_PATH/etc/plugin-artifacts.manifest"
  cp "$GERRIT_STAGED_ARTIFACT_DIR/plugin-metadata.report" "$GERRIT_SITE_PATH/etc/plugin-metadata.report"
  cp "$GERRIT_STAGED_ARTIFACT_DIR/plugin-checksums.sha256" "$GERRIT_SITE_PATH/etc/plugin-checksums.sha256"
  chown -R "$GERRIT_RUNTIME_ACCOUNT:$GERRIT_RUNTIME_GROUP" "$GERRIT_SITE_PATH"
  write_text_file "$GERRIT_SITE_PATH/state/install.status" "installed"
  printf 'status=pass command=install site=%s staged=%s\n' "$GERRIT_SITE_PATH" "$GERRIT_STAGED_ARTIFACT_DIR"
}

cmd_configure() {
  load_env normal
  require_env_values
  check_runtime_account_readiness
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
  local host port response attempt
  read -r host port <<EOF
$(ldap_host_port)
EOF
  response=""
  for attempt in $(seq 1 30); do
    if check_tcp_connect "$host" "$port" >/dev/null 2>&1 &&
      check_ldap_bind_search >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  check_tcp_connect "$host" "$port" ||
    die "LDAP endpoint is not reachable: $host:$port"
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
  local plugin jar
  plugin="${1:?plugin required}"
  jar="$(plugin_catalog_field "$plugin" jar)"
  [ -f "$GERRIT_SITE_PATH/plugins/$jar" ]
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

record_step7_deferred_integration_status() {
  write_text_file "$GERRIT_SITE_PATH/state/integration-prerequisites-deferred.status" \
    "jenkins_integration_prerequisites=deferred role_local_config_mutation=none"
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
    record_step7_deferred_integration_status
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

check_installed_artifact_freshness() {
  local rendered_dir staged_plugin_digest installed_plugin_digest
  cmp -s "$GERRIT_STAGED_ARTIFACT_DIR/gerrit-3.13.6.war" "$GERRIT_SITE_PATH/bin/gerrit.war" ||
    die "Installed Gerrit WAR does not match the staged Gerrit WAR input"
  cmp -s "$GERRIT_STAGED_ARTIFACT_DIR/manifest.txt" "$GERRIT_SITE_PATH/etc/artifact-manifest.txt" ||
    die "Installed artifact manifest copy does not match the staged manifest input"
  cmp -s "$GERRIT_STAGED_ARTIFACT_DIR/checksums.sha256" "$GERRIT_SITE_PATH/etc/artifact-checksums.sha256" ||
    die "Installed artifact checksum copy does not match the staged checksum input"
  cmp -s "$GERRIT_STAGED_ARTIFACT_DIR/plugin-artifacts.manifest" "$GERRIT_SITE_PATH/etc/plugin-artifacts.manifest" ||
    die "Installed plugin artifact manifest copy does not match the staged plugin manifest input"
  cmp -s "$GERRIT_STAGED_ARTIFACT_DIR/plugin-metadata.report" "$GERRIT_SITE_PATH/etc/plugin-metadata.report" ||
    die "Installed plugin metadata report copy does not match the staged plugin metadata input"
  cmp -s "$GERRIT_STAGED_ARTIFACT_DIR/plugin-checksums.sha256" "$GERRIT_SITE_PATH/etc/plugin-checksums.sha256" ||
    die "Installed plugin checksum copy does not match the staged plugin checksum input"

  rendered_dir="$(mktemp -d)"
  register_cleanup_path "$rendered_dir"
  render_template "$GERRIT_STAGED_ARTIFACT_DIR/gerrit.config.template" "$rendered_dir/gerrit.config"
  assert_config_key_matches "$rendered_dir/gerrit.config" "$GERRIT_SITE_PATH/etc/gerrit.config" gerrit.canonicalWebUrl
  assert_config_key_matches "$rendered_dir/gerrit.config" "$GERRIT_SITE_PATH/etc/gerrit.config" gerrit.basePath
  assert_config_key_matches "$rendered_dir/gerrit.config" "$GERRIT_SITE_PATH/etc/gerrit.config" httpd.listenUrl
  assert_config_key_matches "$rendered_dir/gerrit.config" "$GERRIT_SITE_PATH/etc/gerrit.config" sshd.listenAddress
  assert_config_key_matches "$rendered_dir/gerrit.config" "$GERRIT_SITE_PATH/etc/gerrit.config" container.javaHome
  assert_config_key_matches "$rendered_dir/gerrit.config" "$GERRIT_SITE_PATH/etc/gerrit.config" auth.type
  assert_config_key_matches "$rendered_dir/gerrit.config" "$GERRIT_SITE_PATH/etc/gerrit.config" auth.gitBasicAuthPolicy
  assert_config_key_matches "$rendered_dir/gerrit.config" "$GERRIT_SITE_PATH/etc/gerrit.config" ldap.server
  assert_config_key_matches "$rendered_dir/gerrit.config" "$GERRIT_SITE_PATH/etc/gerrit.config" ldap.username
  assert_config_key_matches "$rendered_dir/gerrit.config" "$GERRIT_SITE_PATH/etc/gerrit.config" ldap.accountBase
  assert_config_key_matches "$rendered_dir/gerrit.config" "$GERRIT_SITE_PATH/etc/gerrit.config" ldap.groupBase
  assert_config_key_matches "$rendered_dir/gerrit.config" "$GERRIT_SITE_PATH/etc/gerrit.config" ldap.groupMemberPattern
  assert_config_key_matches "$rendered_dir/gerrit.config" "$GERRIT_SITE_PATH/etc/gerrit.config" ldap.groupName
  assert_config_key_matches "$rendered_dir/gerrit.config" "$GERRIT_SITE_PATH/etc/gerrit.config" ldap.adminGroup
  rm -rf "$rendered_dir"

  staged_plugin_digest="$(plugin_set_digest "$GERRIT_STAGED_ARTIFACT_DIR/plugins")"
  installed_plugin_digest="$(plugin_set_digest "$GERRIT_SITE_PATH/plugins")"
  [ "$staged_plugin_digest" = "$installed_plugin_digest" ] ||
    die "Installed Gerrit plugin set does not match the staged plugin input"
  verify_plugin_artifacts_in_dir "$GERRIT_SITE_PATH/plugins"
  assert_plugin_artifact_manifest_matches "$GERRIT_SITE_PATH/plugins" "$GERRIT_SITE_PATH/etc/plugin-artifacts.manifest"
}

verify_readiness_facts() {
  check_runtime_account_readiness
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
  check_runtime_account_readiness
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
  check_runtime_account_readiness
  confirm_mutation collect-evidence || return 0
  require_command ssh-keygen
  verify_readiness_facts
  ensure_dirs
  local evidence input_fingerprint manifest checksum bounded_log service_log helper_version
  local q_mode q_time q_package_version q_helper_version q_role q_checkpoint q_command q_status
  local q_hosts q_endpoints q_input q_manifest q_checksum q_startup q_endpoint q_ldap q_ssh q_plugin
  local q_runtime_account q_checks q_log q_service_log q_redaction
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
  q_log="$(json_quote "$bounded_log")"
  q_service_log="$(json_quote "$service_log")"
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
      print-env-template|preflight|prepare-artifacts|install|configure|validate|collect-evidence)
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
    validate) cmd_validate ;;
    collect-evidence) cmd_collect_evidence ;;
    *) die_usage "Unknown command: $command_name" ;;
  esac
}

main "$@"
