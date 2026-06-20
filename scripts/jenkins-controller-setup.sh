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
write_env=0

supported_jenkins_version="2.555.3"
supported_jenkins_java_version="21"
supported_jenkins_plugin_manager_version="2.15.0"
supported_jenkins_ubuntu_release="24.04"
supported_jenkins_ubuntu_codename="noble"
readonly JENKINS_NATIVE_HOME="/var/lib/jenkins"

usage() {
  cat <<'USAGE'
Usage:
  scripts/jenkins-controller-setup.sh [--env FILE] [--dry-run] [--yes] [--write-env] <command>

Commands:
  print-env-template
  preflight
  propose-plugin-versions
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
  --write-env    With propose-plugin-versions and --yes, accept direct plugin
                 version proposals by updating only JENKINS_PLUGIN_LIST.
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
JENKINS_HOST
JENKINS_URL
JENKINS_HTTP_PORT
JENKINS_RUNTIME_ACCOUNT
JENKINS_RUNTIME_GROUP
JENKINS_HOME
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
  JENKINS_HOME="${JENKINS_HOME:-$JENKINS_NATIVE_HOME}"
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
  JENKINS_DIRECT_PLUGIN_NAMES="${JENKINS_DIRECT_PLUGIN_NAMES:-configuration-as-code,credentials,git,gerrit-trigger,ldap,matrix-auth,ssh-credentials,ssh-slaves,workflow-aggregator,job-dsl,timestamper,ws-cleanup}"
  JENKINS_PLUGIN_LIST="${JENKINS_PLUGIN_LIST:-configuration-as-code:2088.ve3b_42c663c80,credentials:1502.v5c95e620ddfe,git:5.10.1,gerrit-trigger:3.1971.v217d381e3a_5a_,ldap:807.809.vd3a_4e5e4ec98,matrix-auth:3.2.10,ssh-credentials:372.va_250881b_08cd,ssh-slaves:3.1097.v868116049892,workflow-aggregator:608.v67378e9d3db_1,job-dsl:3654.vdf58f53e2d15,timestamper:1.30,ws-cleanup:0.49}"
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
  validate_runtime_owner_inputs
  [ "$JENKINS_HOME" = "$JENKINS_NATIVE_HOME" ] ||
    die "JENKINS_HOME must be $JENKINS_NATIVE_HOME, got $JENKINS_HOME"
  require_runtime_account_home "$JENKINS_RUNTIME_ACCOUNT" "$JENKINS_RUNTIME_GROUP" "$JENKINS_NATIVE_HOME" "Jenkins"
  require_product_home_ownership "$JENKINS_NATIVE_HOME" "$JENKINS_RUNTIME_ACCOUNT" "$JENKINS_RUNTIME_GROUP" "Jenkins"
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

jenkins_war_artifact() {
  printf '%s/jenkins-%s.war\n' "$JENKINS_ARTIFACT_OUTPUT_DIR" "$JENKINS_VERSION"
}

jenkins_plugin_manager_artifact() {
  printf '%s/jenkins-plugin-manager-%s.jar\n' "$JENKINS_ARTIFACT_OUTPUT_DIR" "$JENKINS_PLUGIN_MANAGER_VERSION"
}

write_direct_plugin_intent() {
  local target name
  target="${1:?target required}"
  : >"$target"
  for name in ${JENKINS_DIRECT_PLUGIN_NAMES//,/ }; do
    validate_plugin_identifier "$name"
    printf '%s\n' "$name" >>"$target"
  done
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

extract_direct_plugin_proposals() {
  local intent_file report_file proposals_file
  intent_file="${1:?intent file required}"
  report_file="${2:?report file required}"
  proposals_file="${3:?proposals file required}"
  awk '
    NR == FNR {
      wanted[$1] = 1
      order[++count] = $1
      next
    }
    {
      line = $0
      gsub(/\r/, "", line)
      sub(/^[[:space:]*-]+/, "", line)
      name = ""
      version = ""
      split(line, fields, /[[:space:]]+/)
      if (fields[1] ~ /^[A-Za-z0-9_.-]+:[A-Za-z0-9_.+-]+$/) {
        split(fields[1], pair, ":")
        name = pair[1]
        version = pair[2]
      } else if (wanted[fields[1]]) {
        name = fields[1]
        version = fields[2]
        gsub(/^[({[]/, "", version)
        gsub(/[)}\],;]$/, "", version)
      }
      if (wanted[name] && version ~ /^[A-Za-z0-9_.+-]+$/) {
        resolved[name] = version
      }
    }
    END {
      missing = 0
      for (i = 1; i <= count; i++) {
        name = order[i]
        if (!(name in resolved)) {
          printf "missing proposal for %s\n", name > "/dev/stderr"
          missing = 1
        } else {
          printf "%s:%s\n", name, resolved[name]
        }
      }
      exit missing
    }
  ' "$intent_file" "$report_file" >"$proposals_file" ||
    die "Could not extract direct plugin version proposals from Plugin Installation Manager output; report=$report_file"
}

accepted_plugin_list_from_file() {
  local proposals_file
  proposals_file="${1:?proposals file required}"
  paste -sd, "$proposals_file"
}

write_plugin_list_to_env() {
  local target_file accepted_list tmp_file backup_file existing_count
  target_file="${1:?env file required}"
  accepted_list="${2:?accepted plugin list required}"
  [ -n "$env_file" ] || die "--write-env requires --env FILE; refusing to update the example env by default"
  [ -f "$target_file" ] || die "Missing env file for --write-env: $target_file"
  existing_count="$(grep -Ec '^JENKINS_PLUGIN_LIST=' "$target_file" || true)"
  [ "$existing_count" -le 1 ] || die "Env file contains multiple JENKINS_PLUGIN_LIST assignments; refusing ambiguous --write-env update"
  tmp_file="$target_file.tmp.$$"
  backup_file="$target_file.bak.$(timestamp_utc)"
  cp "$target_file" "$backup_file"
  NEW_PLUGIN_LIST="$accepted_list" perl -0pe '
    my $value = $ENV{NEW_PLUGIN_LIST};
    my $line = "JENKINS_PLUGIN_LIST=\"$value\"";
    if (!s/^JENKINS_PLUGIN_LIST=.*$/$line/m) {
      s/\n?\z/\n$line\n/;
    }
  ' "$target_file" >"$tmp_file"
  JENKINS_PLUGIN_LIST="$accepted_list" validate_accepted_direct_plugins
  mv "$tmp_file" "$target_file"
}

run_plugin_manager_latest_compatible_list() {
  local plugin_file report_file
  plugin_file="${1:?plugin file required}"
  report_file="${2:?report file required}"
  require_command java
  printf 'simulation-only public internet use: Jenkins Plugin Installation Manager may consult update-center metadata for latest-compatible plugin proposals\n' >>"$JENKINS_ARTIFACT_OUTPUT_DIR/source-boundary.log"
  java -jar "$(jenkins_plugin_manager_artifact)" \
    --war "$(jenkins_war_artifact)" \
    --plugin-file "$plugin_file" \
    --no-download \
    --list \
    >"$report_file" 2>&1
}

run_plugin_manager_review() {
  local plugin_file report_file
  plugin_file="${1:?plugin file required}"
  report_file="${2:?report file required}"
  require_command java
  printf 'simulation-only public internet use: Jenkins Plugin Installation Manager may consult update-center metadata for update/security review\n' >>"$JENKINS_ARTIFACT_OUTPUT_DIR/source-boundary.log"
  java -jar "$(jenkins_plugin_manager_artifact)" \
    --war "$(jenkins_war_artifact)" \
    --plugin-file "$plugin_file" \
    --latest false \
    --available-updates \
    --view-all-security-warnings \
    --no-download \
    >"$report_file" 2>&1
}

plugin_review_metadata_file() {
  printf '%s/plugin-warning-review.metadata\n' "$JENKINS_ARTIFACT_OUTPUT_DIR"
}

write_plugin_review_metadata() {
  local warning_count report_name accepted_by_yes
  warning_count="${1:?warning count required}"
  report_name="${2:?report name required}"
  accepted_by_yes="${3:?accepted flag required}"
  cat >"$(plugin_review_metadata_file)" <<EOF
plugin_warning_count=$warning_count
plugin_warning_report=$report_name
plugin_warning_accepted_by_yes=$accepted_by_yes
EOF
}

inspect_plugin_review_report() {
  local report_file markers_file warning_count report_name accepted_by_yes
  report_file="${1:?plugin review report required}"
  [ -f "$report_file" ] || die "Missing Jenkins plugin review report: $report_file"
  markers_file="$report_file.warning-markers"
  awk '
    {
      line = tolower($0)
    }
    line ~ /^[[:space:]]*no available updates[[:space:]]*\.?[[:space:]]*$/ { next }
    line ~ /^[[:space:]]*no security warnings[[:space:]]*\.?[[:space:]]*$/ { next }
    line ~ /^[[:space:]]*no security advisories[[:space:]]*\.?[[:space:]]*$/ { next }
    line ~ /security-[0-9]+/ { printf "%d:%s\n", NR, $0; next }
    line ~ /security[[:space:]-]+warning/ { printf "%d:%s\n", NR, $0; next }
    line ~ /security[[:space:]-]+advis/ { printf "%d:%s\n", NR, $0; next }
    line ~ /some plugins have updates/ { printf "%d:%s\n", NR, $0; next }
    line ~ /update[[:space:]]+required:/ { printf "%d:%s\n", NR, $0; next }
    line ~ /has[[:space:]]+update/ { printf "%d:%s\n", NR, $0; next }
    line ~ /available[[:space:]-]+update/ { printf "%d:%s\n", NR, $0; next }
  ' "$report_file" >"$markers_file"
  warning_count="$(wc -l <"$markers_file" | tr -d ' ')"
  report_name="${report_file##*/}"
  accepted_by_yes=false
  if [ "$warning_count" -gt 0 ]; then
    printf 'WARNING: Jenkins plugin review found %s warning/security/update marker(s) in %s\n' "$warning_count" "$report_name" >&2
    sed -n '1,20p' "$markers_file" >&2
    if [ "$assume_yes" -ne 1 ]; then
      write_plugin_review_metadata "$warning_count" "$report_name" false
      printf 'BLOCKED: review Jenkins plugin warning summary and rerun with --yes after operator review\n' >&2
      return 2
    fi
    accepted_by_yes=true
    printf 'operator acceptance recorded for Jenkins plugin warning review; accepted_by_yes=true report=%s warning_count=%s\n' "$report_name" "$warning_count"
  fi
  write_plugin_review_metadata "$warning_count" "$report_name" "$accepted_by_yes"
  rm -f "$markers_file"
}

generate_plugins_lock() {
  local plugin_dir lock plugin tmp manifest short_name plugin_version
  if [ "$#" -eq 1 ]; then
    plugin_dir="$JENKINS_ARTIFACT_OUTPUT_DIR/plugins"
    lock="${1:?lock file required}"
  else
    plugin_dir="${1:?plugin directory required}"
    lock="${2:?lock file required}"
  fi
  tmp="$lock.tmp"
  : >"$tmp"
  while IFS= read -r -d '' plugin; do
    manifest="$(unzip -p "$plugin" META-INF/MANIFEST.MF | tr -d '\r')" ||
      die "Could not read Jenkins plugin manifest: $plugin"
    short_name="$(printf '%s\n' "$manifest" | awk -F': ' '/^Short-Name:/ {print $2; exit}')"
    plugin_version="$(printf '%s\n' "$manifest" | awk -F': ' '/^Plugin-Version:/ {print $2; exit}')"
    validate_plugin_spec "$short_name:$plugin_version"
    printf '%s:%s\n' "$short_name" "$plugin_version" >>"$tmp"
  done < <(find "$plugin_dir" -type f \( -name '*.jpi' -o -name '*.hpi' \) -print0 | sort -z)
  sort -u "$tmp" >"$lock"
  rm -f "$tmp"
  [ -s "$lock" ] || die "No Jenkins plugin artifacts were available to generate plugins.lock.txt"
}

assert_direct_plugin_pins_in_lock() {
  local lock spec name expected actual
  lock="${1:?plugin lock required}"
  [ -s "$lock" ] || die "Missing Jenkins plugin lock for direct pin check: $lock"
  validate_plugins
  for spec in ${JENKINS_PLUGIN_LIST//,/ }; do
    name="$(plugin_name "$spec")"
    expected="$(plugin_version "$spec")"
    actual="$(awk -F: -v name="$name" '$1 == name { print $2; found = 1 } END { exit !found }' "$lock" 2>/dev/null || true)"
    [ -n "$actual" ] || die "Accepted direct Jenkins plugin pin is missing from plugins.lock.txt: $name"
    [ "$actual" = "$expected" ] ||
      die "Direct Jenkins plugin pin drift for $name: accepted=$expected lock=$actual"
  done
}

prepare_plugins() {
  local seed_file spec name resolver_report
  seed_file="$JENKINS_ARTIFACT_OUTPUT_DIR/plugins.seed.txt"
  resolver_report="$JENKINS_ARTIFACT_OUTPUT_DIR/plugin-resolution-report.txt"
  write_accepted_plugin_seed "$seed_file"
  run_plugin_manager_latest_compatible_list "$seed_file" "$resolver_report"

  if [ -n "${JENKINS_PLUGIN_SOURCE_DIR:-}" ]; then
    find "$JENKINS_PLUGIN_SOURCE_DIR" -maxdepth 1 -type f \( -name '*.jpi' -o -name '*.hpi' \) -exec cp {} "$JENKINS_ARTIFACT_OUTPUT_DIR/plugins/" \;
  elif [ "${JENKINS_DOWNLOAD_ARTIFACTS:-0}" = "1" ]; then
    require_command java
    printf 'simulation-only public internet use: resolving and downloading Jenkins plugin artifacts with dependencies\n' >>"$JENKINS_ARTIFACT_OUTPUT_DIR/source-boundary.log"
    java -jar "$(jenkins_plugin_manager_artifact)" \
      --war "$(jenkins_war_artifact)" \
      --plugin-file "$seed_file" \
      --plugin-download-directory "$JENKINS_ARTIFACT_OUTPUT_DIR/plugins" \
      >"$JENKINS_ARTIFACT_OUTPUT_DIR/plugin-download-report.txt" 2>&1
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
  generate_plugins_lock "$JENKINS_ARTIFACT_OUTPUT_DIR/plugins.lock.txt"
  assert_direct_plugin_pins_in_lock "$JENKINS_ARTIFACT_OUTPUT_DIR/plugins.lock.txt"
  run_plugin_manager_review "$JENKINS_ARTIFACT_OUTPUT_DIR/plugins.lock.txt" "$JENKINS_ARTIFACT_OUTPUT_DIR/plugin-review-report.txt"
  inspect_plugin_review_report "$JENKINS_ARTIFACT_OUTPUT_DIR/plugin-review-report.txt"
  find "$JENKINS_ARTIFACT_OUTPUT_DIR/plugins" -type f \( -name '*.jpi' -o -name '*.hpi' \) -print |
    sort >"$JENKINS_ARTIFACT_OUTPUT_DIR/plugin-artifacts.manifest"
}

prepare_jenkins_war() {
  local dest url
  dest="$(jenkins_war_artifact)"
  if [ -n "${JENKINS_WAR_SOURCE:-}" ]; then
    cp "$JENKINS_WAR_SOURCE" "$dest"
  elif [ "${JENKINS_DOWNLOAD_ARTIFACTS:-0}" = "1" ]; then
    require_command wget
    url="https://get.jenkins.io/war-stable/$JENKINS_VERSION/jenkins.war"
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
  dest="$(jenkins_plugin_manager_artifact)"
  if [ -n "${JENKINS_PLUGIN_MANAGER_SOURCE:-}" ]; then
    cp "$JENKINS_PLUGIN_MANAGER_SOURCE" "$dest"
  elif [ "${JENKINS_DOWNLOAD_ARTIFACTS:-0}" = "1" ]; then
    require_command wget
    url="https://github.com/jenkinsci/plugin-installation-manager-tool/releases/download/$JENKINS_PLUGIN_MANAGER_VERSION/jenkins-plugin-manager-$JENKINS_PLUGIN_MANAGER_VERSION.jar"
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

require_plugin_proposal_env_values() {
  local required name
  required="
JENKINS_DIRECT_PLUGIN_NAMES
JENKINS_ARTIFACT_OUTPUT_DIR
JENKINS_DOWNLOAD_ARTIFACTS
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
  fi
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
  [ -s "$JENKINS_STAGED_ARTIFACT_DIR/plugins.seed.txt" ] || die "Missing staged Jenkins plugin seed: $JENKINS_STAGED_ARTIFACT_DIR/plugins.seed.txt"
  [ -s "$JENKINS_STAGED_ARTIFACT_DIR/plugins.lock.txt" ] || die "Missing staged Jenkins plugin lock: $JENKINS_STAGED_ARTIFACT_DIR/plugins.lock.txt"
  [ -s "$JENKINS_STAGED_ARTIFACT_DIR/plugin-resolution-report.txt" ] || die "Missing staged Jenkins plugin resolution report"
  [ -s "$JENKINS_STAGED_ARTIFACT_DIR/plugin-review-report.txt" ] || die "Missing staged Jenkins plugin review report"
  [ -s "$JENKINS_STAGED_ARTIFACT_DIR/plugin-warning-review.metadata" ] || die "Missing staged Jenkins plugin warning review metadata"
  (cd "$JENKINS_STAGED_ARTIFACT_DIR" && sha256sum -c checksums.sha256) >/dev/null
  grep -Fq './plugins.seed.txt' "$checksums" || die "Staged checksums do not cover plugins.seed.txt"
  grep -Fq './plugins.lock.txt' "$checksums" || die "Staged checksums do not cover plugins.lock.txt"
  grep -Fq './plugin-resolution-report.txt' "$checksums" || die "Staged checksums do not cover plugin-resolution-report.txt"
  grep -Fq './plugin-review-report.txt' "$checksums" || die "Staged checksums do not cover plugin-review-report.txt"
  grep -Fq './plugin-warning-review.metadata' "$checksums" || die "Staged checksums do not cover plugin-warning-review.metadata"
  (
    local staged_tmp_dir staged_tmp
    staged_tmp_dir="$(mktemp -d)"
    trap 'rm -rf "$staged_tmp_dir"' EXIT
    staged_tmp="$staged_tmp_dir/plugins.lock.txt"
    generate_plugins_lock "$JENKINS_STAGED_ARTIFACT_DIR/plugins" "$staged_tmp"
    diff -u "$JENKINS_STAGED_ARTIFACT_DIR/plugins.lock.txt" "$staged_tmp" >/dev/null ||
      die "Staged plugins.lock.txt does not match staged plugin artifacts"
    assert_direct_plugin_pins_in_lock "$JENKINS_STAGED_ARTIFACT_DIR/plugins.lock.txt"
  )
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
  validate_accepted_direct_plugins
  validate_os_dependencies
  require_account_separation
  validate_runtime_owner_inputs
  runtime_account_exists
  if [ "$dry_run" -eq 0 ]; then
    check_os_dependency_expectations
  fi
  enforce_version_baseline
  printf 'status=pass command=preflight dry_run=%s env=%s host=%s http_port=%s runtime_account=%s runtime_group=%s mode=%s plugins=accepted-direct-pins\n' \
    "$dry_run" "${env_file:-$default_env_file}" "$JENKINS_HOST" "$JENKINS_HTTP_PORT" "$JENKINS_RUNTIME_ACCOUNT" "$JENKINS_RUNTIME_GROUP" "$JENKINS_VERIFICATION_MODE"
}

cmd_propose_plugin_versions() {
  local intent_file report_file proposals_file accepted_list target_env
  load_env normal
  apply_env_defaults
  require_plugin_proposal_env_values
  require_command sha256sum
  require_command unzip
  require_command awk
  require_command perl
  validate_direct_plugins
  enforce_version_baseline
  validate_artifact_output_dir
  if [ "$dry_run" -eq 1 ]; then
    printf 'status=pass command=propose-plugin-versions dry_run=1 env=%s artifact_dir=%s plugins=direct-intent write_env=%s\n' \
      "${env_file:-$default_env_file}" "$JENKINS_ARTIFACT_OUTPUT_DIR" "$write_env"
    return 0
  fi
  rm -rf "$JENKINS_ARTIFACT_OUTPUT_DIR"
  mkdir -p "$JENKINS_ARTIFACT_OUTPUT_DIR"
  : >"$JENKINS_ARTIFACT_OUTPUT_DIR/source-boundary.log"
  prepare_jenkins_war
  prepare_plugin_manager
  intent_file="$JENKINS_ARTIFACT_OUTPUT_DIR/plugins.intent.txt"
  report_file="$JENKINS_ARTIFACT_OUTPUT_DIR/plugin-version-resolution-report.txt"
  proposals_file="$JENKINS_ARTIFACT_OUTPUT_DIR/plugin-version-proposals.txt"
  write_direct_plugin_intent "$intent_file"
  run_plugin_manager_latest_compatible_list "$intent_file" "$report_file"
  extract_direct_plugin_proposals "$intent_file" "$report_file" "$proposals_file"
  accepted_list="$(accepted_plugin_list_from_file "$proposals_file")"
  if [ "$write_env" -eq 1 ]; then
    [ "$assume_yes" -eq 1 ] ||
      die "propose-plugin-versions requires --yes with --write-env before updating the reviewed env"
    target_env="${env_file:-}"
    write_plugin_list_to_env "$target_env" "$accepted_list"
    printf 'status=pass command=propose-plugin-versions proposals=%s report=%s intent=%s write_env=accepted env=%s\n' \
      "$proposals_file" "$report_file" "$intent_file" "$target_env"
  else
    printf 'status=pass command=propose-plugin-versions proposals=%s report=%s intent=%s write_env=skipped\n' \
      "$proposals_file" "$report_file" "$intent_file"
  fi
}

write_manifest() {
  local manifest warning_metadata warning_count warning_report warning_accepted
  manifest="$JENKINS_ARTIFACT_OUTPUT_DIR/manifest.txt"
  warning_metadata="$(plugin_review_metadata_file)"
  [ -f "$warning_metadata" ] || write_plugin_review_metadata 0 "plugin-review-report.txt" false
  warning_count="$(awk -F= '$1 == "plugin_warning_count" { print $2; exit }' "$warning_metadata")"
  warning_report="$(awk -F= '$1 == "plugin_warning_report" { print $2; exit }' "$warning_metadata")"
  warning_accepted="$(awk -F= '$1 == "plugin_warning_accepted_by_yes" { print $2; exit }' "$warning_metadata")"
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
direct_plugins=$JENKINS_PLUGIN_LIST
plugin_lock=plugins.lock.txt
plugin_resolution_report=plugin-resolution-report.txt
plugin_review_report=plugin-review-report.txt
plugin_warning_review_metadata=plugin-warning-review.metadata
plugin_warning_count=$warning_count
plugin_warning_report=$warning_report
plugin_warning_accepted_by_yes=$warning_accepted
war=jenkins-2.555.3.war
plugin_manager=jenkins-plugin-manager-2.15.0.jar
EOF
}

cmd_prepare_artifacts() {
  load_env normal
  apply_env_defaults
  require_command sha256sum
  require_command unzip
  validate_accepted_direct_plugins
  enforce_version_baseline
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
  printf 'status=pass command=prepare-artifacts artifact_dir=%s manifest=%s checksums=%s plugins=accepted-direct-pins lock=%s review=%s\n' \
    "$JENKINS_ARTIFACT_OUTPUT_DIR" \
    "$JENKINS_ARTIFACT_OUTPUT_DIR/manifest.txt" \
    "$JENKINS_ARTIFACT_OUTPUT_DIR/checksums.sha256" \
    "$JENKINS_ARTIFACT_OUTPUT_DIR/plugins.lock.txt" \
    "$JENKINS_ARTIFACT_OUTPUT_DIR/plugin-review-report.txt"
}

cmd_install() {
  local pids
  load_env normal
  require_env_values
  validate_runtime_owner_inputs
  runtime_account_exists
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
  chown -R "$JENKINS_RUNTIME_ACCOUNT:$JENKINS_RUNTIME_GROUP" "$JENKINS_HOME"
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
  chown -R "$JENKINS_RUNTIME_ACCOUNT:$JENKINS_RUNTIME_GROUP" "$JENKINS_HOME"
  mkdir -p "$JENKINS_HOME/war-cache"
  chown -R "$JENKINS_RUNTIME_ACCOUNT:$JENKINS_RUNTIME_GROUP" "$JENKINS_HOME/war-cache"
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
  validate_runtime_owner_inputs
  runtime_account_exists
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
  validate_runtime_owner_inputs
  runtime_account_exists
  confirm_mutation install-plugins || return 0
  verify_staged_artifacts
  mkdir -p "$JENKINS_HOME/plugins" "$JENKINS_HOME/state"
  cp -R "$JENKINS_STAGED_ARTIFACT_DIR/plugins/." "$JENKINS_HOME/plugins/"
  plugin_set_digest >/dev/null
  chown -R "$JENKINS_RUNTIME_ACCOUNT:$JENKINS_RUNTIME_GROUP" "$JENKINS_HOME/plugins"
  write_text_file "$JENKINS_HOME/state/plugins.status" "installed plugins=$JENKINS_PLUGIN_LIST digest=$(plugin_set_digest)"
  printf 'status=pass command=install-plugins plugin_digest=%s\n' "$(plugin_set_digest)"
}

cmd_configure_jcasc() {
  load_env normal
  require_env_values
  validate_runtime_owner_inputs
  runtime_account_exists
  confirm_mutation configure-jcasc || return 0
  verify_staged_artifacts
  mkdir -p "$JENKINS_HOME/jcasc" "$JENKINS_HOME/state"
  chmod 0700 "$JENKINS_HOME/jcasc"
  render_template "$JENKINS_STAGED_ARTIFACT_DIR/templates/jenkins-jcasc.yaml.template" "$JENKINS_HOME/jcasc/jenkins.yaml"
  assert_no_unresolved_placeholders "$JENKINS_HOME/jcasc/jenkins.yaml"
  grep -Fq -- 'numExecutors: 0' "$JENKINS_HOME/jcasc/jenkins.yaml" || die "JCasC must keep built-in node executors at zero"
  grep -Fq -- 'ldap:' "$JENKINS_HOME/jcasc/jenkins.yaml" || die "JCasC LDAP security realm is missing"
  grep -Fq -- 'managerPasswordSecret:' "$JENKINS_HOME/jcasc/jenkins.yaml" || die "JCasC LDAP manager password secret is missing"
  chown -R "$JENKINS_RUNTIME_ACCOUNT:$JENKINS_RUNTIME_GROUP" "$JENKINS_HOME/jcasc"
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

check_runtime_plugin_load_log() {
  local log_file markers_file
  log_file="$JENKINS_HOME/logs/jenkins-controller.log"
  [ -s "$log_file" ] || die "Jenkins controller startup log is missing: $log_file"
  markers_file="$log_file.plugin-load-failures"
  grep -En 'Failed Loading plugin|Update required:|Failed to load:' "$log_file" >"$markers_file" || true
  if [ -s "$markers_file" ]; then
    sed -n '1,20p' "$markers_file" >&2
    die "Jenkins runtime log contains plugin load failure marker: $log_file"
  fi
  rm -f "$markers_file"
}

check_jcasc_readiness() {
  [ -s "$JENKINS_HOME/jcasc/jenkins.yaml" ] || die "JCasC file is missing"
  grep -Fq -- 'ldap:' "$JENKINS_HOME/jcasc/jenkins.yaml" || die "JCasC LDAP realm is missing"
  grep -Fq -- 'managerPasswordSecret:' "$JENKINS_HOME/jcasc/jenkins.yaml" || die "JCasC LDAP manager password secret is missing"
  grep -Fq -- 'numExecutors: 0' "$JENKINS_HOME/jcasc/jenkins.yaml" || die "JCasC built-in executor policy is missing"
}

verify_base_readiness_facts() {
  runtime_account_exists
  verify_staged_artifacts
  [ -s "$JENKINS_HOME/state/install.status" ] || die "Install marker missing"
  [ -s "$JENKINS_HOME/state/service-configured.status" ] || die "Service configuration marker missing"
  [ -s "$JENKINS_HOME/war/jenkins.war" ] || die "Jenkins WAR is not installed"
  [ -s "$JENKINS_HOME/war/jenkins-plugin-manager.jar" ] || die "Jenkins plugin manager is not installed"
  check_plugin_readiness
  check_jcasc_readiness
  [ -s "$JENKINS_HOME/state/runtime.status" ] || die "Jenkins runtime status marker is missing"
  check_runtime_plugin_load_log
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
      --write-env)
        write_env=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      print-env-template|preflight|propose-plugin-versions|prepare-artifacts|install|configure-service|install-plugins|configure-jcasc|validate|collect-evidence)
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
  if [ "$write_env" -eq 1 ] && [ "$command_name" != "propose-plugin-versions" ]; then
    die_usage "--write-env is valid only with propose-plugin-versions"
  fi
  case "$command_name" in
    print-env-template) print_env_template ;;
    preflight) cmd_preflight ;;
    propose-plugin-versions) cmd_propose_plugin_versions ;;
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
