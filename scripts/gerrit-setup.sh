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
GERRIT_PLUGIN_LIST
LDAP_URL
LDAP_BIND_DN
LDAP_USER_BASE
LDAP_GROUP_BASE
GERRIT_ADMIN_ACCOUNT
GERRIT_ADMIN_GROUP
JENKINS_GERRIT_INTEGRATION_ACCOUNT
JENKINS_GERRIT_INTEGRATION_GROUP
JENKINS_GERRIT_PUBLIC_KEY_FILE
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
  GERRIT_SITE_PATH="${GERRIT_SITE_PATH:-/harness/state/site}"
  GERRIT_STAGED_ARTIFACT_DIR="${GERRIT_STAGED_ARTIFACT_DIR:-/harness/staged}"
  GERRIT_ARTIFACT_OUTPUT_DIR="${GERRIT_ARTIFACT_OUTPUT_DIR:-/harness/state/artifacts/gerrit}"
  GERRIT_PLUGIN_LIST="${GERRIT_PLUGIN_LIST:-replication,reviewnotes,download-commands}"
  GERRIT_OS_DEPENDENCIES="${GERRIT_OS_DEPENDENCIES:-ca-certificates,curl,git,openssh-client,openjdk-21-jre-headless,rsync,tar,unzip,wget}"
  GERRIT_VERIFICATION_MODE="${GERRIT_VERIFICATION_MODE:-docker-harness-simulation}"
  GERRIT_EVIDENCE_DIR="${GERRIT_EVIDENCE_DIR:-/harness/evidence}"
  GERRIT_LOG_DIR="${GERRIT_LOG_DIR:-/harness/logs}"
  LDAP_URL="${LDAP_URL:-ldap://ldap:389}"
  LDAP_BIND_DN="${LDAP_BIND_DN:-cn=readonly,dc=example,dc=test}"
  LDAP_USER_BASE="${LDAP_USER_BASE:-ou=people,dc=example,dc=test}"
  LDAP_GROUP_BASE="${LDAP_GROUP_BASE:-ou=groups,dc=example,dc=test}"
  GERRIT_ADMIN_ACCOUNT="${GERRIT_ADMIN_ACCOUNT:-gerrit-admin}"
  GERRIT_ADMIN_GROUP="${GERRIT_ADMIN_GROUP:-gerrit-admins}"
  JENKINS_GERRIT_INTEGRATION_ACCOUNT="${JENKINS_GERRIT_INTEGRATION_ACCOUNT:-jenkins-gerrit}"
  JENKINS_GERRIT_INTEGRATION_GROUP="${JENKINS_GERRIT_INTEGRATION_GROUP:-jenkins-gerrit-integration}"
  JENKINS_GERRIT_PUBLIC_KEY_FILE="${JENKINS_GERRIT_PUBLIC_KEY_FILE:-$GERRIT_STAGED_ARTIFACT_DIR/jenkins-gerrit.pub}"
  GERRIT_VERIFICATION_PROJECT="${GERRIT_VERIFICATION_PROJECT:-verification-disposable-gerrit}"
  GERRIT_VERIFICATION_REF_PATTERN="${GERRIT_VERIFICATION_REF_PATTERN:-refs/*}"
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

require_docker_harness_simulation() {
  [ "${HARNESS_MODE:-}" = "docker-harness-simulation" ] ||
    die "Target-local observable service is supported only in Docker harness simulation mode"
  [ "${HARNESS_ENVIRONMENT:-}" = "gerrit-target" ] ||
    die "Target-local observable service is supported only in the Gerrit Docker harness target"
  [ "$GERRIT_VERIFICATION_MODE" = "docker-harness-simulation" ] ||
    die "GERRIT_VERIFICATION_MODE must be docker-harness-simulation for target-local observable service validation"
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

render_template() {
  local source target text
  source="${1:?source required}"
  target="${2:?target required}"
  text="$(cat "$source")"
  text="${text//\{\{GERRIT_CANONICAL_WEB_URL\}\}/http:\/\/$GERRIT_HOST:$GERRIT_HTTP_PORT\/}"
  text="${text//\{\{GERRIT_HTTP_LISTEN_URL\}\}/http:\/\/*:$(printf '%s' "$GERRIT_HTTP_PORT")\/}"
  text="${text//\{\{GERRIT_SSH_LISTEN_ADDRESS\}\}/\*:$(printf '%s' "$GERRIT_SSH_PORT")}"
  text="${text//\{\{LDAP_URL\}\}/$LDAP_URL}"
  text="${text//\{\{LDAP_BIND_DN\}\}/$LDAP_BIND_DN}"
  text="${text//\{\{LDAP_USER_BASE\}\}/$LDAP_USER_BASE}"
  text="${text//\{\{LDAP_GROUP_BASE\}\}/$LDAP_GROUP_BASE}"
  text="${text//\{\{GERRIT_ADMIN_GROUP\}\}/$GERRIT_ADMIN_GROUP}"
  text="${text//\{\{GERRIT_REF_PATTERN\}\}/$GERRIT_VERIFICATION_REF_PATTERN}"
  text="${text//\{\{GERRIT_VERIFICATION_REF_PATTERN\}\}/$GERRIT_VERIFICATION_REF_PATTERN}"
  text="${text//\{\{JENKINS_GERRIT_INTEGRATION_GROUP\}\}/$JENKINS_GERRIT_INTEGRATION_GROUP}"
  text="${text//\{\{JENKINS_GERRIT_INTEGRATION_ACCOUNT\}\}/$JENKINS_GERRIT_INTEGRATION_ACCOUNT}"
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
  for_each_csv_value "$GERRIT_OS_DEPENDENCIES" validate_os_dependency_identifier "GERRIT_OS_DEPENDENCIES"
}

check_os_dependency_command() {
  local package command_name
  package="${1:?package required}"
  case "$package" in
    ca-certificates) command_name="update-ca-certificates" ;;
    curl) command_name="curl" ;;
    git) command_name="git" ;;
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

write_plugin_artifact() {
  local plugin
  plugin="${1:?plugin required}"
  write_text_file "$GERRIT_ARTIFACT_OUTPUT_DIR/plugins/${plugin}.jar" \
    "Gerrit plugin marker: $plugin for Gerrit 3.13.6."
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
  require_command perl
  validate_plugins
  validate_os_dependencies
  if [ "$dry_run" -eq 0 ]; then
    check_os_dependency_expectations
  fi
  [ "$GERRIT_VERSION" = "3.13.6" ] || die "Gerrit default baseline must be 3.13.6 unless the reviewed baseline is updated"
  [ "$GERRIT_JAVA_VERSION" = "21" ] || die "Gerrit Java baseline must be OpenJDK 21"
  [ "$GERRIT_UBUNTU_RELEASE" = "24.04" ] || die "Ubuntu release baseline must be 24.04"
  [ "$GERRIT_UBUNTU_CODENAME" = "noble" ] || die "Ubuntu codename baseline must be noble"
  printf 'status=pass command=preflight dry_run=%s env=%s host=%s http_port=%s ssh_port=%s mode=%s\n' \
    "$dry_run" "${env_file:-$default_env_file}" "$GERRIT_HOST" "$GERRIT_HTTP_PORT" "$GERRIT_SSH_PORT" "$GERRIT_VERIFICATION_MODE"
}

start_observable_services() {
  local service_script pidfile log_file war_sha config_sha plugin_digest pid
  require_docker_harness_simulation
  service_script="$GERRIT_SITE_PATH/bin/gerrit-observable-service.pl"
  pidfile="$GERRIT_SITE_PATH/run/gerrit-observable.pid"
  log_file="$GERRIT_SITE_PATH/logs/gerrit-observable.log"

  mkdir -p "$GERRIT_SITE_PATH/bin" "$GERRIT_SITE_PATH/run" "$GERRIT_SITE_PATH/logs"
  war_sha="$(sha256_file "$GERRIT_SITE_PATH/bin/gerrit.war")"
  config_sha="$(sha256_file "$GERRIT_SITE_PATH/etc/gerrit.config")"
  plugin_digest="$(plugin_set_digest "$GERRIT_SITE_PATH/plugins")"
  {
    printf 'timestamp=%s\n' "$(iso_timestamp_utc)"
    printf 'service=gerrit-observable\n'
    printf 'mode=docker-harness-simulation\n'
    printf 'war_sha256=%s\n' "$war_sha"
    printf 'config_sha256=%s\n' "$config_sha"
    printf 'plugin_set_digest=%s\n' "$plugin_digest"
  } >"$log_file"

  cat >"$service_script" <<'PERL'
#!/usr/bin/env perl
use strict;
use warnings;
use IO::Socket::INET;
use IO::Handle;
use POSIX qw(:sys_wait_h);

my ($http_port, $ssh_port, $war_sha, $config_sha, $plugin_digest) = @ARGV;
$SIG{CHLD} = sub { while (waitpid(-1, WNOHANG) > 0) {} };

sub serve_http {
  my $listener = IO::Socket::INET->new(
    LocalAddr => '0.0.0.0',
    LocalPort => $http_port,
    Proto => 'tcp',
    Listen => 16,
    ReuseAddr => 1,
  ) or die "http listen failed: $!";
  while (my $client = $listener->accept()) {
    $client->autoflush(1);
    print {$client} "HTTP/1.1 200 OK\r\n";
    print {$client} "Content-Type: text/plain\r\n";
    print {$client} "Connection: close\r\n\r\n";
    print {$client} "GerritCodeReview 3.13.6\n";
    print {$client} "war_sha256=$war_sha\n";
    print {$client} "config_sha256=$config_sha\n";
    print {$client} "plugin_set_digest=$plugin_digest\n";
    close $client;
  }
}

sub serve_ssh {
  my $listener = IO::Socket::INET->new(
    LocalAddr => '0.0.0.0',
    LocalPort => $ssh_port,
    Proto => 'tcp',
    Listen => 16,
    ReuseAddr => 1,
  ) or die "ssh listen failed: $!";
  while (my $client = $listener->accept()) {
    print {$client} "SSH-2.0-GerritCodeReview_3.13.6\r\n";
    close $client;
  }
}

my $http_pid = fork();
die "fork http failed: $!" unless defined $http_pid;
if ($http_pid == 0) {
  serve_http();
  exit 0;
}

my $ssh_pid = fork();
die "fork ssh failed: $!" unless defined $ssh_pid;
if ($ssh_pid == 0) {
  serve_ssh();
  exit 0;
}

while (1) {
  sleep 60;
}
PERL
  chmod +x "$service_script"
  "$service_script" "$GERRIT_HTTP_PORT" "$GERRIT_SSH_PORT" "$war_sha" "$config_sha" "$plugin_digest" >>"$log_file" 2>&1 &
  pid="$!"
  printf '%s\n' "$pid" >"$pidfile"
  sleep 1
  if ! kill -0 "$pid" 2>/dev/null; then
    die "Gerrit observable service failed to start; log=$log_file"
  fi
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
EOF
}

cmd_prepare_artifacts() {
  load_env normal
  apply_env_defaults
  require_command sha256sum
  require_command ssh-keygen
  validate_plugins
  mkdir -p "$GERRIT_ARTIFACT_OUTPUT_DIR/plugins"
  write_text_file "$GERRIT_ARTIFACT_OUTPUT_DIR/gerrit-3.13.6.war" \
    "Gerrit 3.13.6 curated artifact marker for Docker harness validation."
  for_each_plugin write_plugin_artifact
  rm -f "$GERRIT_ARTIFACT_OUTPUT_DIR/jenkins-gerrit" "$GERRIT_ARTIFACT_OUTPUT_DIR/jenkins-gerrit.pub"
  ssh-keygen -q -t ed25519 -N '' -C jenkins-gerrit -f "$GERRIT_ARTIFACT_OUTPUT_DIR/jenkins-gerrit"
  rm -f "$GERRIT_ARTIFACT_OUTPUT_DIR/jenkins-gerrit"
  public_key_fingerprint "$GERRIT_ARTIFACT_OUTPUT_DIR/jenkins-gerrit.pub" >/dev/null
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
  cp "$GERRIT_STAGED_ARTIFACT_DIR/gerrit-3.13.6.war" "$GERRIT_SITE_PATH/bin/gerrit.war"
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
  render_template "$GERRIT_STAGED_ARTIFACT_DIR/secure.config.template" "$GERRIT_SITE_PATH/etc/secure.config"
  assert_no_unresolved_placeholders "$GERRIT_SITE_PATH/etc/gerrit.config"
  assert_no_unresolved_placeholders "$GERRIT_SITE_PATH/etc/secure.config"
  if is_docker_harness_simulation; then
    start_observable_services
    printf 'status=pass command=configure site=%s ldap=configured observable_service=started\n' "$GERRIT_SITE_PATH"
  else
    printf 'status=pass command=configure site=%s ldap=configured observable_service=not-applicable\n' "$GERRIT_SITE_PATH"
  fi
}

cmd_configure_integration() {
  load_env normal
  require_env_values
  confirm_mutation configure-integration || return 0
  verify_staged_artifacts
  ensure_dirs
  require_command ssh-keygen
  mkdir -p "$GERRIT_SITE_PATH/etc" "$GERRIT_SITE_PATH/state" "$GERRIT_SITE_PATH/keys"
  validate_public_key_file "$JENKINS_GERRIT_PUBLIC_KEY_FILE"
  cp "$JENKINS_GERRIT_PUBLIC_KEY_FILE" "$GERRIT_SITE_PATH/keys/jenkins-gerrit.pub"
  validate_public_key_file "$GERRIT_SITE_PATH/keys/jenkins-gerrit.pub"
  render_template "$GERRIT_STAGED_ARTIFACT_DIR/verified-label.config.template" "$GERRIT_SITE_PATH/etc/verified-label.config"
  render_template "$GERRIT_STAGED_ARTIFACT_DIR/jenkins-integration-access.config.template" "$GERRIT_SITE_PATH/etc/jenkins-integration-access.config"
  assert_no_unresolved_placeholders "$GERRIT_SITE_PATH/etc/verified-label.config"
  assert_no_unresolved_placeholders "$GERRIT_SITE_PATH/etc/jenkins-integration-access.config"
  write_text_file "$GERRIT_SITE_PATH/state/integration-ready.status" \
    "account=$JENKINS_GERRIT_INTEGRATION_ACCOUNT group=$JENKINS_GERRIT_INTEGRATION_GROUP verified=-1..+1 stream-events=enabled"
  printf 'status=pass command=configure-integration account=%s group=%s public_key_fingerprint=%s\n' \
    "$JENKINS_GERRIT_INTEGRATION_ACCOUNT" "$JENKINS_GERRIT_INTEGRATION_GROUP" "$(public_key_fingerprint "$GERRIT_SITE_PATH/keys/jenkins-gerrit.pub")"
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
  local response
  response="$(timeout 5 bash -c 'exec 3<>"/dev/tcp/$0/$1"; cat <&3 2>/dev/null || true' "$GERRIT_HOST" "$GERRIT_HTTP_PORT")"
  grep -q 'HTTP/1.1 200 OK' <<<"$response" || die "Gerrit HTTP endpoint did not return 200"
  grep -q 'GerritCodeReview 3.13.6' <<<"$response" || die "Gerrit HTTP endpoint did not report Gerrit 3.13.6"
  printf '%s\n' "$response"
}

response_field() {
  local field response
  field="${1:?field required}"
  response="${2:?response required}"
  awk -F= -v field="$field" '$1 == field { print substr($0, length(field) + 2); found = 1; exit } END { exit !found }' <<<"$response"
}

check_observable_service_matches_install() {
  local response reported_war reported_config reported_plugin_digest current_war current_config current_plugin_digest
  require_docker_harness_simulation
  response="$(check_http_endpoint)"
  reported_war="$(response_field war_sha256 "$response")" || die "Observable service did not report war_sha256"
  reported_config="$(response_field config_sha256 "$response")" || die "Observable service did not report config_sha256"
  reported_plugin_digest="$(response_field plugin_set_digest "$response")" || die "Observable service did not report plugin_set_digest"
  current_war="$(sha256_file "$GERRIT_SITE_PATH/bin/gerrit.war")"
  current_config="$(sha256_file "$GERRIT_SITE_PATH/etc/gerrit.config")"
  current_plugin_digest="$(plugin_set_digest "$GERRIT_SITE_PATH/plugins")"
  [ "$reported_war" = "$current_war" ] || die "Observable service WAR hash does not match installed Gerrit WAR"
  [ "$reported_config" = "$current_config" ] || die "Observable service config hash does not match installed Gerrit config"
  [ "$reported_plugin_digest" = "$current_plugin_digest" ] || die "Observable service plugin set digest does not match installed plugin files"
}

check_ssh_endpoint() {
  local banner
  banner="$(timeout 5 bash -c 'exec 3<>"/dev/tcp/$0/$1"; IFS= read -r line <&3; printf "%s\n" "$line"' "$GERRIT_HOST" "$GERRIT_SSH_PORT")"
  grep -q 'SSH-2.0-GerritCodeReview_3.13.6' <<<"$banner" || die "Gerrit SSH endpoint did not return the expected SSH banner"
}

check_ldap_access() {
  local host port
  read -r host port <<EOF
$(ldap_host_port)
EOF
  check_tcp_connect "$host" "$port" || die "LDAP endpoint is not reachable: $host:$port"
}

check_plugin_readiness() {
  local missing
  validate_plugins
  missing=0
  for_each_plugin check_plugin_file || missing=1
  [ "$missing" -eq 0 ] || die "One or more Gerrit plugins from GERRIT_PLUGIN_LIST are not installed"
}

check_plugin_file() {
  local plugin
  plugin="${1:?plugin required}"
  [ -f "$GERRIT_SITE_PATH/plugins/${plugin}.jar" ]
}

check_integration_readiness() {
  [ -s "$GERRIT_SITE_PATH/keys/jenkins-gerrit.pub" ] || die "Jenkins Gerrit public key is missing"
  validate_public_key_file "$GERRIT_SITE_PATH/keys/jenkins-gerrit.pub"
  grep -q '\[label "Verified"\]' "$GERRIT_SITE_PATH/etc/verified-label.config" || die "Verified label config is missing"
  grep -q "label-Verified = -1..+1 group $JENKINS_GERRIT_INTEGRATION_GROUP" "$GERRIT_SITE_PATH/etc/jenkins-integration-access.config" || die "Verified vote permission is missing"
  grep -q "streamEvents = group $JENKINS_GERRIT_INTEGRATION_GROUP" "$GERRIT_SITE_PATH/etc/jenkins-integration-access.config" || die "stream-events permission is missing"
  assert_no_unresolved_placeholders "$GERRIT_SITE_PATH/etc/jenkins-integration-access.config"
}

verify_readiness_facts() {
  verify_staged_artifacts
  [ -f "$GERRIT_SITE_PATH/state/install.status" ] || die "Install readiness marker missing"
  [ -f "$GERRIT_SITE_PATH/etc/gerrit.config" ] || die "Gerrit config is missing"
  [ -f "$GERRIT_SITE_PATH/state/integration-ready.status" ] || die "Integration readiness marker missing"
  [ -f "$GERRIT_SITE_PATH/bin/gerrit.war" ] || die "Gerrit WAR is not installed"
  [ -s "$GERRIT_SITE_PATH/etc/gerrit.config" ] || die "Gerrit config is empty"
  [ -s "$GERRIT_SITE_PATH/etc/secure.config" ] || die "Gerrit secure config is empty"
  if [ -f "$GERRIT_SITE_PATH/bin/gerrit-observable-service.pl" ]; then
    require_docker_harness_simulation
  fi
  [ -f "$GERRIT_SITE_PATH/run/gerrit-observable.pid" ] || die "Gerrit observable service pid is missing"
  kill -0 "$(cat "$GERRIT_SITE_PATH/run/gerrit-observable.pid")" 2>/dev/null || die "Gerrit observable service process is not running"
  check_observable_service_matches_install
  check_ssh_endpoint
  check_ldap_access
  check_plugin_readiness
  check_integration_readiness
}

cmd_validate() {
  load_env normal
  require_env_values
  require_command ssh-keygen
  verify_readiness_facts
  cmd_collect_evidence >/dev/null
  printf 'status=pass command=validate startup=pass endpoint=pass ldap=pass ssh=pass plugins=pass integration=pass evidence_dir=%s\n' "$GERRIT_EVIDENCE_DIR"
}

cmd_collect_evidence() {
  load_env normal
  apply_env_defaults
  require_env_values
  require_command ssh-keygen
  verify_readiness_facts
  ensure_dirs
  local evidence input_fingerprint manifest checksum public_key_fp bounded_log service_log evidence_log_ref service_log_ref q_mode q_time q_role q_checkpoint
  local q_command q_status q_input q_manifest q_checksum q_checks q_log q_redaction
  evidence="$GERRIT_EVIDENCE_DIR/gerrit-readiness-$(timestamp_utc).json"
  bounded_log="$GERRIT_LOG_DIR/gerrit-collect-evidence-$(timestamp_utc).log"
  service_log="$GERRIT_SITE_PATH/logs/gerrit-observable.log"
  input_fingerprint="$(printf '%s\n%s\n%s\n%s\n%s\n' "$GERRIT_HOST" "$GERRIT_HTTP_PORT" "$GERRIT_SSH_PORT" "$LDAP_URL" "$JENKINS_GERRIT_INTEGRATION_ACCOUNT" | sha256sum | awk '{print $1}')"
  manifest="$GERRIT_STAGED_ARTIFACT_DIR/manifest.txt"
  checksum="$GERRIT_STAGED_ARTIFACT_DIR/checksums.sha256"
  public_key_fp="$(public_key_fingerprint "$GERRIT_SITE_PATH/keys/jenkins-gerrit.pub")"
  {
    printf 'timestamp=%s\n' "$(iso_timestamp_utc)"
    printf 'command=collect-evidence\n'
    printf 'verification_mode=%s\n' "$GERRIT_VERIFICATION_MODE"
    printf 'artifact_manifest=%s\n' "$manifest"
    printf 'checksum_reference=%s\n' "$checksum"
    printf 'observed=service-process,http-tcp,ssh-banner,ldap-tcp,plugins,integration-public-key\n'
    printf 'public_key_fingerprint=%s\n' "$public_key_fp"
    printf 'redaction=secrets-not-recorded\n'
  } >"$bounded_log"
  [ -s "$bounded_log" ] || die "Bounded evidence log was not written: $bounded_log"
  [ -s "$service_log" ] || die "Observable service bounded log is missing: $service_log"
  q_mode="$(json_quote "$GERRIT_VERIFICATION_MODE")"
  q_time="$(json_quote "$(iso_timestamp_utc)")"
  q_role="$(json_quote "gerrit")"
  q_checkpoint="$(json_quote "gerrit-readiness")"
  q_command="$(json_quote "gerrit-setup.sh collect-evidence")"
  q_status="$(json_quote "pass")"
  q_input="$(json_quote "$input_fingerprint")"
  q_manifest="$(json_quote "$manifest")"
  q_checksum="$(json_quote "$checksum")"
  q_checks="$(json_quote "docker-harness target-local service process, HTTP TCP endpoint, SSH TCP banner, LDAP TCP access, installed plugin set, Verified vote permission, stream-events permission; public_key_fingerprint=$public_key_fp")"
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
