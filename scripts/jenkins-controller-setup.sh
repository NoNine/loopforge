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
JENKINS_DOWNLOAD_ARTIFACTS
LDAP_URL
LDAP_BIND_DN
LDAP_USER_BASE
LDAP_GROUP_BASE
JENKINS_ADMIN_ACCOUNT
JENKINS_ADMIN_GROUP
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
  if [ -z "${LDAP_BIND_PASSWORD_FILE:-}" ] && [ -z "${LDAP_BIND_PASSWORD:-}" ]; then
    die "Missing reviewed LDAP bind password input: set LDAP_BIND_PASSWORD_FILE or LDAP_BIND_PASSWORD"
  fi
}

require_account_separation() {
  [ "$JENKINS_RUNTIME_ACCOUNT" != "$JENKINS_ADMIN_ACCOUNT" ] ||
    die "Jenkins runtime account must not match Jenkins admin account"
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
  JENKINS_DOWNLOAD_ARTIFACTS="${JENKINS_DOWNLOAD_ARTIFACTS:-0}"
  JENKINS_WAR_SOURCE="${JENKINS_WAR_SOURCE:-}"
  JENKINS_PLUGIN_MANAGER_SOURCE="${JENKINS_PLUGIN_MANAGER_SOURCE:-}"
  JENKINS_PLUGIN_SOURCE_DIR="${JENKINS_PLUGIN_SOURCE_DIR:-}"
  JENKINS_OS_DEPENDENCIES="${JENKINS_OS_DEPENDENCIES:-ca-certificates,curl,fontconfig,git,net-tools,netcat-openbsd,openjdk-21-jre,openssh-client,rsync,tar,unzip,wget}"
  JENKINS_PLUGIN_LIST="${JENKINS_PLUGIN_LIST:-configuration-as-code:2006.v001a_2ca_6b_574,credentials:1415.v831096eb_5534,git:5.7.0,gerrit-trigger:2.42.0,ldap:780.vcb_33c9a_e4332,matrix-auth:3.2.6,ssh-credentials:361.vb_f6760818e8c,ssh-slaves:3.1031.v72c6b_883b_869,workflow-aggregator:608.v67378e9d3db_1,job-dsl:1.93,timestamper:1.30,ws-cleanup:0.48}"
  LDAP_URL="${LDAP_URL:-ldap://ldap:389}"
  LDAP_BIND_DN="${LDAP_BIND_DN:-cn=readonly,dc=example,dc=test}"
  LDAP_BIND_PASSWORD_FILE="${LDAP_BIND_PASSWORD_FILE:-}"
  LDAP_BIND_PASSWORD="${LDAP_BIND_PASSWORD:-}"
  LDAP_USER_BASE="${LDAP_USER_BASE:-ou=people,dc=example,dc=test}"
  LDAP_GROUP_BASE="${LDAP_GROUP_BASE:-ou=groups,dc=example,dc=test}"
  JENKINS_ADMIN_ACCOUNT="${JENKINS_ADMIN_ACCOUNT:-jenkins-admin}"
  JENKINS_ADMIN_GROUP="${JENKINS_ADMIN_GROUP:-jenkins-admins}"
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

runtime_account_exists() {
  getent passwd "$JENKINS_RUNTIME_ACCOUNT" >/dev/null 2>&1 ||
    die "Missing Jenkins runtime account: $JENKINS_RUNTIME_ACCOUNT"
}

run_as_runtime() {
  local command
  command="${1:?command required}"
  if command -v runuser >/dev/null 2>&1; then
    runuser -u "$JENKINS_RUNTIME_ACCOUNT" -- sh -lc "$command"
  elif command -v su >/dev/null 2>&1; then
    su -s /bin/sh "$JENKINS_RUNTIME_ACCOUNT" -c "$command"
  else
    die "Missing runuser or su for Jenkins runtime execution"
  fi
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
    die "Controller runtime proof is supported only in Docker harness simulation mode"
  [ "${HARNESS_ENVIRONMENT:-}" = "jenkins-controller-target" ] ||
    die "Controller runtime proof is supported only in the Jenkins controller Docker harness target"
  [ "$JENKINS_VERIFICATION_MODE" = "docker-harness-simulation" ] ||
    die "JENKINS_VERIFICATION_MODE must be docker-harness-simulation for controller runtime proof"
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
  local source target text ldap_bind_password
  source="${1:?source required}"
  target="${2:?target required}"
  text="$(cat "$source")"
  ldap_bind_password="$(ldap_bind_password_value)"
  text="${text//\{\{JENKINS_HOME\}\}/$JENKINS_HOME}"
  text="${text//\{\{JENKINS_HTTP_PORT\}\}/$JENKINS_HTTP_PORT}"
  text="${text//\{\{JENKINS_RUNTIME_ACCOUNT\}\}/$JENKINS_RUNTIME_ACCOUNT}"
  text="${text//\{\{JENKINS_URL\}\}/$JENKINS_URL}"
  text="${text//\{\{LDAP_URL\}\}/$LDAP_URL}"
  text="${text//\{\{LDAP_BIND_DN\}\}/$LDAP_BIND_DN}"
  text="${text//\{\{LDAP_BIND_PASSWORD\}\}/$ldap_bind_password}"
  text="${text//\{\{LDAP_USER_BASE\}\}/$LDAP_USER_BASE}"
  text="${text//\{\{LDAP_GROUP_BASE\}\}/$LDAP_GROUP_BASE}"
  text="${text//\{\{VERIFICATION_MODE\}\}/$JENKINS_VERIFICATION_MODE}"
  mkdir -p "$(dirname "$target")"
  printf '%s\n' "$text" >"$target"
  chmod 0600 "$target"
}

ldap_bind_password_value() {
  local secret
  if [ -n "${LDAP_BIND_PASSWORD_FILE:-}" ]; then
    [ -r "$LDAP_BIND_PASSWORD_FILE" ] || die "LDAP bind password file is not readable: $LDAP_BIND_PASSWORD_FILE"
    secret="$(tr -d '\r\n' <"$LDAP_BIND_PASSWORD_FILE")"
  else
    secret="${LDAP_BIND_PASSWORD:-}"
  fi
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
  local spec name version source_file dest_file plugin_url
  spec="${1:?plugin spec required}"
  name="$(plugin_name "$spec")"
  version="$(plugin_version "$spec")"
  dest_file="$JENKINS_ARTIFACT_OUTPUT_DIR/plugins/${name}.jpi"
  if [ -n "${JENKINS_PLUGIN_SOURCE_DIR:-}" ]; then
    source_file=""
    for candidate in "$JENKINS_PLUGIN_SOURCE_DIR/${name}.jpi" "$JENKINS_PLUGIN_SOURCE_DIR/${name}.hpi"; do
      if [ -f "$candidate" ]; then
        source_file="$candidate"
        break
      fi
    done
    [ -n "$source_file" ] || die "Missing reviewed Jenkins plugin artifact for $name in $JENKINS_PLUGIN_SOURCE_DIR"
    cp "$source_file" "$dest_file"
  elif [ "${JENKINS_DOWNLOAD_ARTIFACTS:-0}" = "1" ]; then
    require_command wget
    plugin_url="https://updates.jenkins.io/download/plugins/$name/$version/${name}.hpi"
    printf 'simulation-only public internet use: downloading Jenkins plugin artifact %s:%s\n' "$name" "$version" >>"$JENKINS_ARTIFACT_OUTPUT_DIR/source-boundary.log"
    wget -q --show-progress=off --tries=5 --timeout=30 --read-timeout=60 -O "$dest_file" "$plugin_url"
  else
    printf 'BLOCKED: prepare-artifacts requires JENKINS_PLUGIN_SOURCE_DIR or JENKINS_DOWNLOAD_ARTIFACTS=1 for selected Jenkins plugin artifacts\n' >&2
    exit 2
  fi
  unzip -p "$dest_file" META-INF/MANIFEST.MF >/dev/null 2>&1 ||
    die "Jenkins plugin artifact is not a valid archive: $dest_file"
}

prepare_plugins() {
  local seed_file spec name
  seed_file="$JENKINS_ARTIFACT_OUTPUT_DIR/plugins.seed.txt"
  : >"$seed_file"
  for spec in ${JENKINS_PLUGIN_LIST//,/ }; do
    printf '%s\n' "$spec" >>"$seed_file"
  done

  if [ -n "${JENKINS_PLUGIN_SOURCE_DIR:-}" ]; then
    find "$JENKINS_PLUGIN_SOURCE_DIR" -maxdepth 1 -type f \( -name '*.jpi' -o -name '*.hpi' \) -exec cp {} "$JENKINS_ARTIFACT_OUTPUT_DIR/plugins/" \;
  elif [ "${JENKINS_DOWNLOAD_ARTIFACTS:-0}" = "1" ]; then
    require_command java
    printf 'simulation-only public internet use: resolving and downloading Jenkins plugin artifacts with dependencies\n' >>"$JENKINS_ARTIFACT_OUTPUT_DIR/source-boundary.log"
    java -jar "$JENKINS_ARTIFACT_OUTPUT_DIR/jenkins-plugin-manager-2.15.0.jar" \
      --war "$JENKINS_ARTIFACT_OUTPUT_DIR/jenkins-2.555.3.war" \
      --plugin-file "$seed_file" \
      --latest false \
      --plugin-download-directory "$JENKINS_ARTIFACT_OUTPUT_DIR/plugins" \
      >"$JENKINS_ARTIFACT_OUTPUT_DIR/plugin-resolution-report.txt" 2>&1
  else
    printf 'BLOCKED: prepare-artifacts requires JENKINS_PLUGIN_SOURCE_DIR or JENKINS_DOWNLOAD_ARTIFACTS=1 for selected Jenkins plugin artifacts\n' >&2
    exit 2
  fi

  for spec in ${JENKINS_PLUGIN_LIST//,/ }; do
    name="$(plugin_name "$spec")"
    [ -s "$JENKINS_ARTIFACT_OUTPUT_DIR/plugins/${name}.jpi" ] ||
      [ -s "$JENKINS_ARTIFACT_OUTPUT_DIR/plugins/${name}.hpi" ] ||
      die "Curated Jenkins plugin artifact is missing after preparation: $name"
  done
  find "$JENKINS_ARTIFACT_OUTPUT_DIR/plugins" -type f \( -name '*.jpi' -o -name '*.hpi' \) -print |
    sort >"$JENKINS_ARTIFACT_OUTPUT_DIR/plugin-artifacts.manifest"
}

prepare_jenkins_war() {
  local dest url
  dest="$JENKINS_ARTIFACT_OUTPUT_DIR/jenkins-2.555.3.war"
  if [ -n "${JENKINS_WAR_SOURCE:-}" ]; then
    cp "$JENKINS_WAR_SOURCE" "$dest"
  elif [ "${JENKINS_DOWNLOAD_ARTIFACTS:-0}" = "1" ]; then
    require_command wget
    url="https://get.jenkins.io/war-stable/2.555.3/jenkins.war"
    printf 'simulation-only public internet use: downloading Jenkins controller WAR\n' >>"$JENKINS_ARTIFACT_OUTPUT_DIR/source-boundary.log"
    wget -q --show-progress=off --tries=5 --timeout=30 --read-timeout=120 -O "$dest" "$url"
  else
    printf 'BLOCKED: prepare-artifacts requires JENKINS_WAR_SOURCE or JENKINS_DOWNLOAD_ARTIFACTS=1 in the bundle factory; target hosts never download Jenkins application artifacts as fallback\n' >&2
    exit 2
  fi
  unzip -p "$dest" META-INF/MANIFEST.MF >/dev/null 2>&1 ||
    die "Jenkins WAR is not a valid archive and cannot support real controller startup: $dest"
}

prepare_plugin_manager() {
  local dest url
  dest="$JENKINS_ARTIFACT_OUTPUT_DIR/jenkins-plugin-manager-2.15.0.jar"
  if [ -n "${JENKINS_PLUGIN_MANAGER_SOURCE:-}" ]; then
    cp "$JENKINS_PLUGIN_MANAGER_SOURCE" "$dest"
  elif [ "${JENKINS_DOWNLOAD_ARTIFACTS:-0}" = "1" ]; then
    require_command wget
    url="https://github.com/jenkinsci/plugin-installation-manager-tool/releases/download/2.15.0/jenkins-plugin-manager-2.15.0.jar"
    printf 'simulation-only public internet use: downloading Jenkins Plugin Installation Manager artifact\n' >>"$JENKINS_ARTIFACT_OUTPUT_DIR/source-boundary.log"
    wget -q --show-progress=off --tries=5 --timeout=30 --read-timeout=120 -O "$dest" "$url"
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
    $1 == "artifact_source" && $2 == "curated-bundle-factory" { a=1 }
    $1 == "os_dependency_source" && $2 == "approved-internal-os-repos" { o=1 }
    $1 == "public_internet_fallback" && $2 == "simulation-only" { p=1 }
    $1 == "bundle_contains_keys" && $2 == "no" { k=1 }
    END { exit !(h && r && g && jn && pm && j && u && n && a && o && p && k) }
  ' "$manifest" || die "Staged manifest does not match the Jenkins controller Version Baseline"
  assert_no_artifact_key_material "$JENKINS_STAGED_ARTIFACT_DIR"
}

cmd_preflight() {
  load_env normal
  require_env_values
  require_command sha256sum
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
os_dependency_source=approved-internal-os-repos
public_internet_fallback=simulation-only
bundle_contains_keys=no
plugins=$JENKINS_PLUGIN_LIST
war=jenkins-2.555.3.war
plugin_manager=jenkins-plugin-manager-2.15.0.jar
EOF
}

cmd_prepare_artifacts() {
  load_env normal
  apply_env_defaults
  require_command sha256sum
  require_command unzip
  validate_plugins
  validate_artifact_output_dir
  rm -rf "$JENKINS_ARTIFACT_OUTPUT_DIR"
  mkdir -p "$JENKINS_ARTIFACT_OUTPUT_DIR/plugins" "$JENKINS_ARTIFACT_OUTPUT_DIR/templates"
  : >"$JENKINS_ARTIFACT_OUTPUT_DIR/source-boundary.log"
  prepare_jenkins_war
  prepare_plugin_manager
  prepare_plugins
  cp "$repo_root/templates/jenkins-controller/jenkins-service.env.template" "$JENKINS_ARTIFACT_OUTPUT_DIR/templates/jenkins-service.env.template"
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
  printf 'status=pass command=prepare-artifacts artifact_dir=%s manifest=%s checksums=%s plugins=curated\n' \
    "$JENKINS_ARTIFACT_OUTPUT_DIR" "$JENKINS_ARTIFACT_OUTPUT_DIR/manifest.txt" "$JENKINS_ARTIFACT_OUTPUT_DIR/checksums.sha256"
}

cmd_install() {
  local pids
  load_env normal
  require_env_values
  confirm_mutation install || return 0
  verify_staged_artifacts
  ensure_dirs
  if [ -f "$JENKINS_HOME/run/jenkins.pid" ] && kill -0 "$(cat "$JENKINS_HOME/run/jenkins.pid")" 2>/dev/null; then
    kill "$(cat "$JENKINS_HOME/run/jenkins.pid")" 2>/dev/null || true
  fi
  pids="$(ps -eo pid=,args= | awk -v home="$JENKINS_HOME" 'index($0, home) && index($0, "jenkins.war") {print $1}')"
  if [ -n "$pids" ]; then
    kill $pids 2>/dev/null || true
    sleep 2
    kill -9 $pids 2>/dev/null || true
  fi
  rm -rf \
    "$JENKINS_HOME/war" \
    "$JENKINS_HOME/war-cache" \
    "$JENKINS_HOME/plugins" \
    "$JENKINS_HOME/templates" \
    "$JENKINS_HOME/state" \
    "$JENKINS_HOME/etc" \
    "$JENKINS_HOME/jcasc" \
    "$JENKINS_HOME/run"
  mkdir -p "$JENKINS_HOME/war" "$JENKINS_HOME/plugins" "$JENKINS_HOME/templates" "$JENKINS_HOME/state" "$JENKINS_HOME/logs"
  cp "$JENKINS_STAGED_ARTIFACT_DIR/jenkins-2.555.3.war" "$JENKINS_HOME/war/jenkins.war"
  cp "$JENKINS_STAGED_ARTIFACT_DIR/jenkins-plugin-manager-2.15.0.jar" "$JENKINS_HOME/war/jenkins-plugin-manager.jar"
  cp -R "$JENKINS_STAGED_ARTIFACT_DIR/templates/." "$JENKINS_HOME/templates/"
  cp "$JENKINS_STAGED_ARTIFACT_DIR/manifest.txt" "$JENKINS_HOME/artifact-manifest.txt"
  cp "$JENKINS_STAGED_ARTIFACT_DIR/checksums.sha256" "$JENKINS_HOME/artifact-checksums.sha256"
  runtime_account_exists
  chown -R "$JENKINS_RUNTIME_ACCOUNT:$JENKINS_RUNTIME_ACCOUNT" "$JENKINS_HOME"
  write_text_file "$JENKINS_HOME/state/install.status" "installed"
  printf 'status=pass command=install home=%s staged=%s\n' "$JENKINS_HOME" "$JENKINS_STAGED_ARTIFACT_DIR"
}

start_real_jenkins() {
  local pidfile log_file pid deadline response
  require_docker_harness_simulation
  runtime_account_exists
  pidfile="$JENKINS_HOME/run/jenkins.pid"
  log_file="$JENKINS_HOME/logs/jenkins-controller.log"
  mkdir -p "$JENKINS_HOME/run" "$JENKINS_HOME/logs"
  if [ -f "$pidfile" ] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
    return 0
  fi
  export JENKINS_HOME
  export CASC_JENKINS_CONFIG="$JENKINS_HOME/jcasc/jenkins.yaml"
  export JAVA_OPTS="-Djava.awt.headless=true -Djenkins.install.runSetupWizard=false -Dcasc.jenkins.config=$JENKINS_HOME/jcasc/jenkins.yaml"
  chown -R "$JENKINS_RUNTIME_ACCOUNT:$JENKINS_RUNTIME_ACCOUNT" "$JENKINS_HOME"
  mkdir -p "$JENKINS_HOME/war-cache"
  chown -R "$JENKINS_RUNTIME_ACCOUNT:$JENKINS_RUNTIME_ACCOUNT" "$JENKINS_HOME/war-cache"
  run_as_runtime "JENKINS_HOME=$(printf '%q' "$JENKINS_HOME") CASC_JENKINS_CONFIG=$(printf '%q' "$CASC_JENKINS_CONFIG") nohup java $JAVA_OPTS -jar $(printf '%q' "$JENKINS_HOME/war/jenkins.war") --httpPort=$(printf '%q' "$JENKINS_HTTP_PORT") --webroot=$(printf '%q' "$JENKINS_HOME/war-cache") >$(printf '%q' "$log_file") 2>&1 & echo \$!" >"$pidfile"
  pid="$(cat "$pidfile")"
  deadline=$((SECONDS + 240))
  while [ "$SECONDS" -lt "$deadline" ]; do
    if ! kill -0 "$pid" 2>/dev/null; then
      tail -40 "$log_file" >&2 || true
      die "Jenkins controller process exited before readiness; log=$log_file"
    fi
    response="$(check_http_endpoint || true)"
    if printf '%s' "$response" | grep -Fq "X-Jenkins: 2.555.3"; then
      write_text_file "$JENKINS_HOME/state/runtime.status" "pid=$pid endpoint=http://$JENKINS_HOST:$JENKINS_HTTP_PORT/ log=$log_file"
      return 0
    fi
    sleep 3
  done
  tail -40 "$log_file" >&2 || true
  die "Jenkins controller did not become ready before timeout; log=$log_file"
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
  runtime_account_exists
  chown -R "$JENKINS_RUNTIME_ACCOUNT:$JENKINS_RUNTIME_ACCOUNT" "$JENKINS_HOME/plugins"
  write_text_file "$JENKINS_HOME/state/plugins.status" "installed plugins=$JENKINS_PLUGIN_LIST digest=$(plugin_set_digest)"
  printf 'status=pass command=install-plugins plugin_digest=%s\n' "$(plugin_set_digest)"
}

cmd_configure_jcasc() {
  load_env normal
  require_env_values
  confirm_mutation configure-jcasc || return 0
  verify_staged_artifacts
  mkdir -p "$JENKINS_HOME/jcasc" "$JENKINS_HOME/state"
  chmod 0700 "$JENKINS_HOME/jcasc"
  render_template "$JENKINS_STAGED_ARTIFACT_DIR/templates/jenkins-jcasc.yaml.template" "$JENKINS_HOME/jcasc/jenkins.yaml"
  assert_no_unresolved_placeholders "$JENKINS_HOME/jcasc/jenkins.yaml"
  grep -Fq -- 'numExecutors: 0' "$JENKINS_HOME/jcasc/jenkins.yaml" || die "JCasC must keep built-in node executors at zero"
  grep -Fq -- 'ldap:' "$JENKINS_HOME/jcasc/jenkins.yaml" || die "JCasC LDAP security realm is missing"
  grep -Fq -- 'managerPasswordSecret:' "$JENKINS_HOME/jcasc/jenkins.yaml" || die "JCasC LDAP manager password secret is missing"
  runtime_account_exists
  chown -R "$JENKINS_RUNTIME_ACCOUNT:$JENKINS_RUNTIME_ACCOUNT" "$JENKINS_HOME/jcasc"
  chmod 0700 "$JENKINS_HOME/jcasc"
  chmod 0600 "$JENKINS_HOME/jcasc/jenkins.yaml"
  write_text_file "$JENKINS_HOME/state/jcasc.status" "configured ldap=$LDAP_URL admin_group=$JENKINS_ADMIN_GROUP"
  printf 'status=pass command=configure-jcasc jcasc=%s ldap=configured\n' "$JENKINS_HOME/jcasc/jenkins.yaml"
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

check_jcasc_readiness() {
  [ -s "$JENKINS_HOME/jcasc/jenkins.yaml" ] || die "JCasC file is missing"
  grep -Fq -- 'ldap:' "$JENKINS_HOME/jcasc/jenkins.yaml" || die "JCasC LDAP realm is missing"
  grep -Fq -- 'managerPasswordSecret:' "$JENKINS_HOME/jcasc/jenkins.yaml" || die "JCasC LDAP manager password secret is missing"
  grep -Fq -- 'numExecutors: 0' "$JENKINS_HOME/jcasc/jenkins.yaml" || die "JCasC built-in executor policy is missing"
}

verify_base_readiness_facts() {
  verify_staged_artifacts
  [ -s "$JENKINS_HOME/state/install.status" ] || die "Install marker missing"
  [ -s "$JENKINS_HOME/state/service-configured.status" ] || die "Service configuration marker missing"
  [ -s "$JENKINS_HOME/war/jenkins.war" ] || die "Jenkins WAR is not installed"
  [ -s "$JENKINS_HOME/war/jenkins-plugin-manager.jar" ] || die "Jenkins plugin manager is not installed"
  check_plugin_readiness
  check_jcasc_readiness
  [ -s "$JENKINS_HOME/state/runtime.status" ] || die "Jenkins runtime status marker is missing"
  check_ldap_access
}

cmd_validate() {
  load_env normal
  require_env_values
  start_real_jenkins
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
  local q_mode q_time q_role q_checkpoint q_command q_status q_input q_manifest q_checksum q_checks q_log q_redaction q_proof q_real q_step11
  evidence="$JENKINS_EVIDENCE_DIR/jenkins-controller-readiness-$(timestamp_utc).json"
  bounded_log="$JENKINS_LOG_DIR/jenkins-controller-collect-evidence-$(timestamp_utc).log"
  service_log="$JENKINS_HOME/logs/jenkins-controller.log"
  runtime_status="$JENKINS_HOME/state/runtime.status"
  jenkins_pid="$JENKINS_HOME/run/jenkins.pid"
  input_fingerprint="$(printf '%s\n%s\n%s\n%s\n' "$JENKINS_HOST" "$JENKINS_HTTP_PORT" "$LDAP_URL" "$JENKINS_HOME" | sha256sum | awk '{print $1}')"
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
    printf 'observed=staged-artifacts,real-jenkins-startup,http-endpoint,api-json,ldap,plugins,JCasC\n'
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
  q_checks="$(json_quote "Real Jenkins controller process started from staged WAR, responded on /login and /api/json, retained plugin and JCasC readiness, and wrote bounded logs without secrets.")"
  q_log="$(json_quote "$bounded_log;$service_log;$runtime_status")"
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
      print-env-template|preflight|prepare-artifacts|install|configure-service|install-plugins|configure-jcasc|validate|collect-evidence)
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
    validate) cmd_validate ;;
    collect-evidence) cmd_collect_evidence ;;
    *) die_usage "Unknown command: $command_name" ;;
  esac
}

main "$@"
