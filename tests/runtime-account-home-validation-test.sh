#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
fake_bin="$tmp_dir/bin"
mutation_dir="$tmp_dir/mutation"
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$fake_bin"
cat >"$fake_bin/getent" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
db="${1:?db required}"
key="${2:?key required}"
case ",${FAKE_GETENT_MISSING:-}," in
  *",$db:$key,"*) exit 2 ;;
esac
case "$db:$key" in
  hosts:gerrit-target) printf '127.0.0.1 gerrit-target\n' ;;
  hosts:jenkins-controller-target) printf '127.0.0.1 jenkins-controller-target\n' ;;
  hosts:jenkins-agent-target) printf '127.0.0.1 jenkins-agent-target\n' ;;
  passwd:gerrit|passwd:custom-gerrit) printf '%s:x:61010:%s:Gerrit:%s:/bin/bash\n' "$key" "${FAKE_GERRIT_PRIMARY_GID:-61010}" "${FAKE_GERRIT_HOME:-/wrong/gerrit}" ;;
  group:gerrit|group:custom-gerrit) printf '%s:x:%s:\n' "$key" "${FAKE_GERRIT_GROUP_GID:-61010}" ;;
  passwd:jenkins|passwd:custom-jenkins) printf '%s:x:61020:%s:Jenkins:%s:/bin/bash\n' "$key" "${FAKE_JENKINS_PRIMARY_GID:-61020}" "${FAKE_JENKINS_HOME:-/wrong/jenkins}" ;;
  group:jenkins|group:custom-jenkins) printf '%s:x:%s:\n' "$key" "${FAKE_JENKINS_GROUP_GID:-61020}" ;;
  passwd:jenkins-agent|passwd:custom-agent) printf '%s:x:61030:%s:Jenkins Agent:%s:/bin/bash\n' "$key" "${FAKE_AGENT_PRIMARY_GID:-61030}" "${FAKE_AGENT_HOME:-/wrong/agent}" ;;
  group:jenkins-agent|group:custom-agent) printf '%s:x:%s:\n' "$key" "${FAKE_AGENT_GROUP_GID:-61030}" ;;
  *) exit 2 ;;
esac
SH
chmod +x "$fake_bin/getent"
mkdir -p "$mutation_dir"
cat >"$fake_bin/mkdir" <<'SH'
#!/usr/bin/env bash
printf 'mkdir %s\n' "$*" >>"$FAKE_MUTATION_LOG"
exec /usr/bin/mkdir "$@"
SH
chmod +x "$fake_bin/mkdir"

cat >"$fake_bin/install" <<'SH'
#!/usr/bin/env bash
[ -n "${FAKE_MUTATION_LOG:-}" ] || exec /usr/bin/install "$@"
printf 'install %s\n' "$*" >>"$FAKE_MUTATION_LOG"
exit 0
SH
chmod +x "$fake_bin/install"

cat >"$fake_bin/stat" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[ "${1:-}" = "-c" ] || exec /usr/bin/stat "$@"
format="${2:?format required}"
path="${3:?path required}"
case "$path" in
  /srv/gerrit)
    [ "${FAKE_GERRIT_HOME_MISSING:-0}" != "1" ] || exit 1
    owner="${FAKE_GERRIT_OWNER:-gerrit}"
    group="${FAKE_GERRIT_GROUP:-gerrit}"
    ;;
  /var/lib/jenkins)
    [ "${FAKE_JENKINS_HOME_MISSING:-0}" != "1" ] || exit 1
    owner="${FAKE_JENKINS_OWNER:-jenkins}"
    group="${FAKE_JENKINS_GROUP:-jenkins}"
    ;;
  /var/lib/jenkins-agent)
    [ "${FAKE_AGENT_HOME_MISSING:-0}" != "1" ] || exit 1
    owner="${FAKE_AGENT_OWNER:-jenkins-agent}"
    group="${FAKE_AGENT_GROUP:-jenkins-agent}"
    ;;
  *)
    exec /usr/bin/stat "$@"
    ;;
esac
case "$format" in
  %F) printf 'directory\n' ;;
  %U) printf '%s\n' "$owner" ;;
  %G) printf '%s\n' "$group" ;;
  *) exec /usr/bin/stat "$@" ;;
esac
SH
chmod +x "$fake_bin/stat"

for command_name in ldapsearch ssh java rsync unzip wget update-ca-certificates curl git ssh-keygen; do
  cat >"$fake_bin/$command_name" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  chmod +x "$fake_bin/$command_name"
done

cat >"$tmp_dir/gerrit.env" <<'EOF'
GERRIT_HOST="gerrit-target"
GERRIT_HTTP_PORT="8080"
GERRIT_SSH_PORT="29418"
GERRIT_RUNTIME_ACCOUNT="gerrit"
GERRIT_RUNTIME_GROUP="gerrit"
GERRIT_RUNTIME_UID="61010"
GERRIT_RUNTIME_GID="61010"
GERRIT_SITE_PATH="/srv/gerrit"
GERRIT_STAGED_ARTIFACT_DIR="/unused/staged"
GERRIT_ARTIFACT_OUTPUT_DIR="/unused/artifacts"
LDAP_URL="ldap://ldap:389"
LDAP_BIND_DN="cn=readonly,dc=example,dc=test"
LDAP_BIND_PASSWORD="readonly-password"
LDAP_USER_BASE="ou=people,dc=example,dc=test"
LDAP_GROUP_BASE="ou=groups,dc=example,dc=test"
GERRIT_ADMIN_ACCOUNT="gerrit-admin"
GERRIT_ADMIN_GROUP="gerrit-admins"
GERRIT_VERIFICATION_PROJECT="verification-disposable-gerrit"
GERRIT_VERIFICATION_REF_PATTERN="refs/heads/*"
GERRIT_VERIFICATION_MODE="docker-simulation"
GERRIT_EVIDENCE_DIR="/unused/evidence"
EOF

cat >"$tmp_dir/jenkins-controller.env" <<'EOF'
JENKINS_HOST="jenkins-controller-target"
JENKINS_URL="http://jenkins-controller-target:8080/"
JENKINS_HTTP_PORT="8080"
JENKINS_RUNTIME_ACCOUNT="jenkins"
JENKINS_RUNTIME_GROUP="jenkins"
JENKINS_RUNTIME_UID="61020"
JENKINS_RUNTIME_GID="61020"
JENKINS_HOME="/var/lib/jenkins"
JENKINS_STAGED_ARTIFACT_DIR="/unused/staged"
JENKINS_ARTIFACT_OUTPUT_DIR="/unused/artifacts"
JENKINS_DIRECT_PLUGIN_NAMES="configuration-as-code"
JENKINS_PLUGIN_LIST="configuration-as-code:2088.ve3b_42c663c80"
JENKINS_DOWNLOAD_ARTIFACTS="1"
LDAP_URL="ldap://ldap:389"
LDAP_BIND_DN="cn=readonly,dc=example,dc=test"
LDAP_BIND_PASSWORD="readonly-password"
LDAP_USER_BASE="ou=people,dc=example,dc=test"
LDAP_GROUP_BASE="ou=groups,dc=example,dc=test"
JENKINS_ADMIN_ACCOUNT="jenkins-admin"
JENKINS_ADMIN_GROUP="jenkins-admins"
JENKINS_VERIFICATION_MODE="docker-simulation"
JENKINS_EVIDENCE_DIR="/unused/evidence"
EOF

cat >"$tmp_dir/jenkins-agent.env" <<'EOF'
JENKINS_AGENT_UBUNTU_RELEASE="24.04"
JENKINS_AGENT_UBUNTU_CODENAME="noble"
JENKINS_AGENT_JAVA_VERSION="21"
JENKINS_AGENT_HOST="jenkins-agent-target"
JENKINS_AGENT_SSH_PORT="22"
JENKINS_AGENT_ACCOUNT="jenkins-agent"
JENKINS_AGENT_GROUP="jenkins-agent"
JENKINS_AGENT_UID="61030"
JENKINS_AGENT_GID="61030"
JENKINS_AGENT_REMOTE_FS="/var/lib/jenkins-agent"
JENKINS_AGENT_NODE_NAME="build-linux-x86-01"
JENKINS_AGENT_LABELS="linux x86_64 general-build gerrit-ci"
JENKINS_AGENT_EXECUTORS="5"
JENKINS_AGENT_CREDENTIAL_ID="jenkins-agent-ssh"
JENKINS_AGENT_STATE_DIR="/var/lib/jenkins-agent"
JENKINS_AGENT_STAGED_ARTIFACT_DIR="/unused/staged"
JENKINS_AGENT_ARTIFACT_OUTPUT_DIR="/unused/artifacts"
JENKINS_AGENT_EVIDENCE_DIR="/unused/evidence"
JENKINS_AGENT_LOG_DIR="/unused/logs"
JENKINS_AGENT_VERIFICATION_MODE="docker-simulation"
JENKINS_AGENT_OS_DEPENDENCIES="ca-certificates,curl,git,openssh-server,openjdk-21-jre,rsync,tar,unzip,wget"
JENKINS_AGENT_CONTROLLER_PLUGIN="ssh-slaves"
JENKINS_AGENT_CONTROLLER_PLUGIN_SOURCE="jenkins-controller-plugin-bundle"
JENKINS_AGENT_EXECUTOR_CONTEXT="controller-owned"
EOF
mkdir -p "$tmp_dir/agent-staged/templates"
cat >"$tmp_dir/agent-staged/jenkins-agent-bootstrap.txt" <<'EOF'
bootstrap
EOF
cat >"$tmp_dir/agent-staged/manifest.txt" <<'EOF'
harness_manifest_version=1
role=jenkins-agent
bundle_name=jenkins-agent-artifacts-bundle
ubuntu_release=24.04
ubuntu_codename=noble
java_version=21
gerrit_version=not-applicable
jenkins_version=not-applicable
jenkins_plugin_manager_version=not-applicable
bootstrap=jenkins-agent-bootstrap.txt
template_count=2
EOF
sha256sum "$tmp_dir/agent-staged/jenkins-agent-bootstrap.txt" >"$tmp_dir/agent-staged/checksums.sha256"
cat >"$tmp_dir/jenkins-agent-install.env" <<EOF
JENKINS_AGENT_UBUNTU_RELEASE="24.04"
JENKINS_AGENT_UBUNTU_CODENAME="noble"
JENKINS_AGENT_JAVA_VERSION="21"
JENKINS_AGENT_HOST="jenkins-agent-target"
JENKINS_AGENT_SSH_PORT="22"
JENKINS_AGENT_ACCOUNT="jenkins-agent"
JENKINS_AGENT_GROUP="jenkins-agent"
JENKINS_AGENT_UID="61030"
JENKINS_AGENT_GID="61030"
JENKINS_AGENT_REMOTE_FS="/var/lib/jenkins-agent"
JENKINS_AGENT_NODE_NAME="build-linux-x86-01"
JENKINS_AGENT_LABELS="linux x86_64 general-build gerrit-ci"
JENKINS_AGENT_EXECUTORS="5"
JENKINS_AGENT_CREDENTIAL_ID="jenkins-agent-ssh"
JENKINS_AGENT_STATE_DIR="/var/lib/jenkins-agent/install-validation"
JENKINS_AGENT_STAGED_ARTIFACT_DIR="$tmp_dir/agent-staged"
JENKINS_AGENT_ARTIFACT_OUTPUT_DIR="/unused/artifacts"
JENKINS_AGENT_EVIDENCE_DIR="$mutation_dir/evidence"
JENKINS_AGENT_LOG_DIR="$mutation_dir/logs"
JENKINS_AGENT_VERIFICATION_MODE="docker-simulation"
JENKINS_AGENT_OS_DEPENDENCIES="ca-certificates,curl,git,openssh-server,openjdk-21-jre,rsync,tar,unzip,wget"
JENKINS_AGENT_CONTROLLER_PLUGIN="ssh-slaves"
JENKINS_AGENT_CONTROLLER_PLUGIN_SOURCE="jenkins-controller-plugin-bundle"
JENKINS_AGENT_EXECUTOR_CONTEXT="controller-owned"
EOF

expect_home_failure() {
  local role script env_file expected output rc
  role="${1:?role required}"
  script="${2:?script required}"
  env_file="${3:?env required}"
  expected="${4:?expected required}"
  set +e
  output="$(PATH="$fake_bin:$PATH" "$repo_root/$script" --env "$env_file" preflight 2>&1)"
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || {
    printf '%s preflight unexpectedly passed with wrong runtime HOME\n' "$role" >&2
    exit 1
  }
  grep -Fq "$expected" <<<"$output" || {
    printf '%s preflight did not report expected HOME failure\nOutput:\n%s\n' "$role" "$output" >&2
    exit 1
  }
}

expect_agent_home_failure_for_command() {
  local command expected output rc
  command="${1:?command required}"
  expected="${2:?expected required}"
  set +e
  output="$(
    PATH="$fake_bin:$PATH" \
    HARNESS_MODE=docker-simulation \
    HARNESS_ENVIRONMENT=jenkins-agent-target \
    "$repo_root/scripts/jenkins-agent-setup.sh" --env "$tmp_dir/jenkins-agent.env" --yes "$command" 2>&1
  )"
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || {
    printf 'Agent %s unexpectedly passed with wrong runtime HOME\n' "$command" >&2
    exit 1
  }
  grep -Fq "$expected" <<<"$output" || {
    printf 'Agent %s did not report expected HOME failure\nOutput:\n%s\n' "$command" "$output" >&2
    exit 1
  }
}

expect_home_failure Gerrit scripts/gerrit-setup.sh "$tmp_dir/gerrit.env" \
  'Gerrit runtime account gerrit passwd HOME must be /srv/gerrit, got /wrong/gerrit'
expect_home_failure Jenkins scripts/jenkins-controller-setup.sh "$tmp_dir/jenkins-controller.env" \
  'Jenkins runtime account jenkins passwd HOME must be /var/lib/jenkins, got /wrong/jenkins'
expect_agent_home_failure_for_command preflight \
  'Jenkins agent runtime account jenkins-agent passwd HOME must be /var/lib/jenkins-agent, got /wrong/agent'
expect_agent_home_failure_for_command configure-runtime \
  'Jenkins agent runtime account jenkins-agent passwd HOME must be /var/lib/jenkins-agent, got /wrong/agent'

expect_configured_path_failure() {
  local role script env_file env_var configured_path expected output rc
  role="${1:?role required}"
  script="${2:?script required}"
  env_file="${3:?env required}"
  env_var="${4:?env var required}"
  configured_path="${5:?configured path required}"
  expected="${6:?expected required}"
  cp "$env_file" "$tmp_dir/$role-custom.env"
  printf '%s="%s"\n' "$env_var" "$configured_path" >>"$tmp_dir/$role-custom.env"
  set +e
  case "$role" in
    Gerrit)
      output="$(PATH="$fake_bin:$PATH" FAKE_GERRIT_HOME="$configured_path" "$repo_root/$script" --env "$tmp_dir/$role-custom.env" preflight 2>&1)"
      ;;
    Jenkins)
      output="$(PATH="$fake_bin:$PATH" FAKE_JENKINS_HOME="$configured_path" "$repo_root/$script" --env "$tmp_dir/$role-custom.env" preflight 2>&1)"
      ;;
    Agent)
      output="$(
        PATH="$fake_bin:$PATH" \
        FAKE_AGENT_HOME="$configured_path" \
        HARNESS_MODE=docker-simulation \
        HARNESS_ENVIRONMENT=jenkins-agent-target \
        "$repo_root/$script" --env "$tmp_dir/$role-custom.env" --yes configure-runtime 2>&1
      )"
      ;;
    *)
      printf 'Unknown role: %s\n' "$role" >&2
      exit 1
      ;;
  esac
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || {
    printf '%s unexpectedly passed with non-native configured product path\n' "$role" >&2
    exit 1
  }
  grep -Fq "$expected" <<<"$output" || {
    printf '%s did not report expected configured path failure\nOutput:\n%s\n' "$role" "$output" >&2
    exit 1
  }
}

expect_configured_path_failure Gerrit scripts/gerrit-setup.sh "$tmp_dir/gerrit.env" \
  GERRIT_SITE_PATH /custom/gerrit \
  'GERRIT_SITE_PATH must be /srv/gerrit, got /custom/gerrit'
expect_configured_path_failure Jenkins scripts/jenkins-controller-setup.sh "$tmp_dir/jenkins-controller.env" \
  JENKINS_HOME /custom/jenkins \
  'JENKINS_HOME must be /var/lib/jenkins, got /custom/jenkins'
expect_configured_path_failure Agent scripts/jenkins-agent-setup.sh "$tmp_dir/jenkins-agent.env" \
  JENKINS_AGENT_REMOTE_FS /custom/agent \
  'JENKINS_AGENT_REMOTE_FS must be /var/lib/jenkins-agent, got /custom/agent'

expect_dry_run_preflight_failure() {
  local role script env_file expected output rc
  role="${1:?role required}"
  script="${2:?script required}"
  env_file="${3:?env required}"
  expected="${4:?expected required}"
  shift 4
  set +e
  output="$(env "$@" PATH="$fake_bin:$PATH" "$repo_root/$script" --env "$env_file" --dry-run preflight 2>&1)"
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || {
    printf '%s dry-run preflight unexpectedly passed\n' "$role" >&2
    exit 1
  }
  grep -Fq "$expected" <<<"$output" || {
    printf '%s dry-run preflight did not report expected failure\nOutput:\n%s\n' "$role" "$output" >&2
    exit 1
  }
}

cp "$tmp_dir/gerrit.env" "$tmp_dir/gerrit-dry-custom-path.env"
printf 'GERRIT_SITE_PATH="/custom/gerrit"\n' >>"$tmp_dir/gerrit-dry-custom-path.env"
cp "$tmp_dir/jenkins-controller.env" "$tmp_dir/jenkins-dry-custom-path.env"
printf 'JENKINS_HOME="/custom/jenkins"\n' >>"$tmp_dir/jenkins-dry-custom-path.env"
cp "$tmp_dir/jenkins-agent.env" "$tmp_dir/agent-dry-custom-path.env"
printf 'JENKINS_AGENT_REMOTE_FS="/custom/agent"\n' >>"$tmp_dir/agent-dry-custom-path.env"
cp "$tmp_dir/gerrit.env" "$tmp_dir/gerrit-dry-custom-account.env"
printf 'GERRIT_RUNTIME_ACCOUNT="custom-gerrit"\n' >>"$tmp_dir/gerrit-dry-custom-account.env"
printf 'GERRIT_RUNTIME_GROUP="custom-gerrit"\n' >>"$tmp_dir/gerrit-dry-custom-account.env"
cp "$tmp_dir/jenkins-controller.env" "$tmp_dir/jenkins-dry-custom-account.env"
printf 'JENKINS_RUNTIME_ACCOUNT="custom-jenkins"\n' >>"$tmp_dir/jenkins-dry-custom-account.env"
printf 'JENKINS_RUNTIME_GROUP="custom-jenkins"\n' >>"$tmp_dir/jenkins-dry-custom-account.env"
cp "$tmp_dir/jenkins-agent.env" "$tmp_dir/agent-dry-custom-account.env"
printf 'JENKINS_AGENT_ACCOUNT="custom-agent"\n' >>"$tmp_dir/agent-dry-custom-account.env"
printf 'JENKINS_AGENT_GROUP="custom-agent"\n' >>"$tmp_dir/agent-dry-custom-account.env"

expect_dry_run_preflight_failure Gerrit scripts/gerrit-setup.sh "$tmp_dir/gerrit.env" \
  'Gerrit runtime account gerrit passwd HOME must be /srv/gerrit, got /wrong/gerrit'
expect_dry_run_preflight_failure Jenkins scripts/jenkins-controller-setup.sh "$tmp_dir/jenkins-controller.env" \
  'Jenkins runtime account jenkins passwd HOME must be /var/lib/jenkins, got /wrong/jenkins'
expect_dry_run_preflight_failure Agent scripts/jenkins-agent-setup.sh "$tmp_dir/jenkins-agent.env" \
  'Jenkins agent runtime account jenkins-agent passwd HOME must be /var/lib/jenkins-agent, got /wrong/agent' \
  HARNESS_MODE=docker-simulation HARNESS_ENVIRONMENT=jenkins-agent-target

expect_dry_run_preflight_failure Gerrit scripts/gerrit-setup.sh "$tmp_dir/gerrit.env" \
  'Gerrit runtime identity state is partial' \
  FAKE_GETENT_MISSING=passwd:gerrit
expect_dry_run_preflight_failure Jenkins scripts/jenkins-controller-setup.sh "$tmp_dir/jenkins-controller.env" \
  'Jenkins runtime identity state is partial' \
  FAKE_GETENT_MISSING=passwd:jenkins
expect_dry_run_preflight_failure Agent scripts/jenkins-agent-setup.sh "$tmp_dir/jenkins-agent.env" \
  'Jenkins agent runtime identity state is partial' \
  FAKE_GETENT_MISSING=passwd:jenkins-agent HARNESS_MODE=docker-simulation HARNESS_ENVIRONMENT=jenkins-agent-target

expect_dry_run_preflight_failure Gerrit scripts/gerrit-setup.sh "$tmp_dir/gerrit-dry-custom-path.env" \
  'GERRIT_SITE_PATH must be /srv/gerrit, got /custom/gerrit' \
  FAKE_GERRIT_HOME=/srv/gerrit
expect_dry_run_preflight_failure Jenkins scripts/jenkins-controller-setup.sh "$tmp_dir/jenkins-dry-custom-path.env" \
  'JENKINS_HOME must be /var/lib/jenkins, got /custom/jenkins' \
  FAKE_JENKINS_HOME=/var/lib/jenkins
expect_dry_run_preflight_failure Agent scripts/jenkins-agent-setup.sh "$tmp_dir/agent-dry-custom-path.env" \
  'JENKINS_AGENT_REMOTE_FS must be /var/lib/jenkins-agent, got /custom/agent' \
  FAKE_AGENT_HOME=/var/lib/jenkins-agent HARNESS_MODE=docker-simulation HARNESS_ENVIRONMENT=jenkins-agent-target

expect_dry_run_preflight_pass() {
  local role script env_file mutation_log output rc
  role="${1:?role required}"
  script="${2:?script required}"
  env_file="${3:?env required}"
  shift 3
  mutation_log="$mutation_dir/${role,,}-dry-run.log"
  rm -f "$mutation_log"
  set +e
  output="$(env "$@" FAKE_MUTATION_LOG="$mutation_log" PATH="$fake_bin:$PATH" "$repo_root/$script" --env "$env_file" --dry-run preflight 2>&1)"
  rc=$?
  set -e
  [ "$rc" -eq 0 ] || {
    printf '%s dry-run preflight should accept configured runtime identity\nOutput:\n%s\n' "$role" "$output" >&2
    exit 1
  }
  if [ -s "$mutation_log" ]; then
    printf '%s dry-run preflight mutated state:\n' "$role" >&2
    cat "$mutation_log" >&2
    exit 1
  fi
}

expect_dry_run_preflight_pass Gerrit scripts/gerrit-setup.sh "$tmp_dir/gerrit-dry-custom-account.env" \
  FAKE_GERRIT_HOME=/srv/gerrit FAKE_GERRIT_OWNER=custom-gerrit FAKE_GERRIT_GROUP=custom-gerrit
expect_dry_run_preflight_pass Jenkins scripts/jenkins-controller-setup.sh "$tmp_dir/jenkins-dry-custom-account.env" \
  FAKE_JENKINS_HOME=/var/lib/jenkins FAKE_JENKINS_OWNER=custom-jenkins FAKE_JENKINS_GROUP=custom-jenkins
expect_dry_run_preflight_pass Agent scripts/jenkins-agent-setup.sh "$tmp_dir/agent-dry-custom-account.env" \
  FAKE_AGENT_HOME=/var/lib/jenkins-agent FAKE_AGENT_OWNER=custom-agent FAKE_AGENT_GROUP=custom-agent HARNESS_MODE=docker-simulation HARNESS_ENVIRONMENT=jenkins-agent-target

expect_dry_run_preflight_pass Gerrit scripts/gerrit-setup.sh "$tmp_dir/gerrit.env" \
  FAKE_GETENT_MISSING=passwd:gerrit,group:gerrit FAKE_GERRIT_HOME_MISSING=1
expect_dry_run_preflight_pass Jenkins scripts/jenkins-controller-setup.sh "$tmp_dir/jenkins-controller.env" \
  FAKE_GETENT_MISSING=passwd:jenkins,group:jenkins FAKE_JENKINS_HOME_MISSING=1
expect_dry_run_preflight_pass Agent scripts/jenkins-agent-setup.sh "$tmp_dir/jenkins-agent.env" \
  FAKE_GETENT_MISSING=passwd:jenkins-agent,group:jenkins-agent FAKE_AGENT_HOME_MISSING=1 \
  HARNESS_MODE=docker-simulation HARNESS_ENVIRONMENT=jenkins-agent-target

expect_dry_run_preflight_failure Gerrit scripts/gerrit-setup.sh "$tmp_dir/gerrit-dry-custom-account.env" \
  'Gerrit runtime identity state is partial' \
  FAKE_GERRIT_HOME=/srv/gerrit FAKE_GERRIT_OWNER=custom-gerrit FAKE_GERRIT_GROUP=custom-gerrit FAKE_GETENT_MISSING=passwd:custom-gerrit
expect_dry_run_preflight_failure Jenkins scripts/jenkins-controller-setup.sh "$tmp_dir/jenkins-dry-custom-account.env" \
  'Jenkins runtime identity state is partial' \
  FAKE_JENKINS_HOME=/var/lib/jenkins FAKE_JENKINS_OWNER=custom-jenkins FAKE_JENKINS_GROUP=custom-jenkins FAKE_GETENT_MISSING=group:custom-jenkins
expect_dry_run_preflight_failure Agent scripts/jenkins-agent-setup.sh "$tmp_dir/agent-dry-custom-account.env" \
  'Jenkins agent runtime account custom-agent primary group must be custom-agent' \
  FAKE_AGENT_HOME=/var/lib/jenkins-agent FAKE_AGENT_OWNER=custom-agent FAKE_AGENT_GROUP=custom-agent FAKE_AGENT_PRIMARY_GID=9999 HARNESS_MODE=docker-simulation HARNESS_ENVIRONMENT=jenkins-agent-target

expect_dry_run_preflight_failure Gerrit scripts/gerrit-setup.sh "$tmp_dir/gerrit.env" \
  'Gerrit product home /srv/gerrit owner/group must be gerrit:gerrit, got root:gerrit' \
  FAKE_GERRIT_HOME=/srv/gerrit FAKE_GERRIT_OWNER=root
expect_dry_run_preflight_failure Jenkins scripts/jenkins-controller-setup.sh "$tmp_dir/jenkins-controller.env" \
  'Jenkins product home /var/lib/jenkins owner/group must be jenkins:jenkins, got jenkins:root' \
  FAKE_JENKINS_HOME=/var/lib/jenkins FAKE_JENKINS_GROUP=root
expect_dry_run_preflight_failure Agent scripts/jenkins-agent-setup.sh "$tmp_dir/jenkins-agent.env" \
  'Jenkins agent product home /var/lib/jenkins-agent owner/group must be jenkins-agent:jenkins-agent, got root:root' \
  FAKE_AGENT_HOME=/var/lib/jenkins-agent FAKE_AGENT_OWNER=root FAKE_AGENT_GROUP=root HARNESS_MODE=docker-simulation HARNESS_ENVIRONMENT=jenkins-agent-target

expect_dry_run_command_failure() {
  local role script env_file command expected output rc
  role="${1:?role required}"
  script="${2:?script required}"
  env_file="${3:?env required}"
  command="${4:?command required}"
  expected="${5:?expected required}"
  shift 5
  set +e
  output="$(env "$@" PATH="$fake_bin:$PATH" "$repo_root/$script" --env "$env_file" --dry-run "$command" 2>&1)"
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || {
    printf '%s dry-run %s unexpectedly passed\n' "$role" "$command" >&2
    exit 1
  }
  grep -Fq "$expected" <<<"$output" || {
    printf '%s dry-run %s did not report expected failure\nOutput:\n%s\n' "$role" "$command" "$output" >&2
    exit 1
  }
}

for command in install configure validate collect-evidence; do
  expect_dry_run_command_failure Gerrit scripts/gerrit-setup.sh "$tmp_dir/gerrit.env" "$command" \
    'Gerrit runtime account gerrit passwd HOME must be /srv/gerrit, got /wrong/gerrit'
  expect_dry_run_command_failure Gerrit scripts/gerrit-setup.sh "$tmp_dir/gerrit-dry-custom-path.env" "$command" \
    'GERRIT_SITE_PATH must be /srv/gerrit, got /custom/gerrit' \
    FAKE_GERRIT_HOME=/srv/gerrit
done

for command in install configure-service install-plugins configure-jcasc; do
  expect_dry_run_command_failure Jenkins scripts/jenkins-controller-setup.sh "$tmp_dir/jenkins-controller.env" "$command" \
    'Jenkins runtime account jenkins passwd HOME must be /var/lib/jenkins, got /wrong/jenkins'
  expect_dry_run_command_failure Jenkins scripts/jenkins-controller-setup.sh "$tmp_dir/jenkins-dry-custom-path.env" "$command" \
    'JENKINS_HOME must be /var/lib/jenkins, got /custom/jenkins' \
    FAKE_JENKINS_HOME=/var/lib/jenkins
done

for command in install configure-runtime; do
  expect_dry_run_command_failure Agent scripts/jenkins-agent-setup.sh "$tmp_dir/jenkins-agent.env" "$command" \
    'Jenkins agent runtime account jenkins-agent passwd HOME must be /var/lib/jenkins-agent, got /wrong/agent' \
    HARNESS_MODE=docker-simulation HARNESS_ENVIRONMENT=jenkins-agent-target
  expect_dry_run_command_failure Agent scripts/jenkins-agent-setup.sh "$tmp_dir/agent-dry-custom-path.env" "$command" \
    'JENKINS_AGENT_REMOTE_FS must be /var/lib/jenkins-agent, got /custom/agent' \
    FAKE_AGENT_HOME=/var/lib/jenkins-agent HARNESS_MODE=docker-simulation HARNESS_ENVIRONMENT=jenkins-agent-target
done

set +e
missing_agent_output="$(
  PATH="$fake_bin:$PATH" \
  FAKE_GETENT_MISSING="passwd:jenkins-agent" \
  HARNESS_MODE=docker-simulation \
  HARNESS_ENVIRONMENT=jenkins-agent-target \
  "$repo_root/scripts/jenkins-agent-setup.sh" --env "$tmp_dir/jenkins-agent.env" preflight 2>&1
)"
missing_agent_rc=$?
set -e
[ "$missing_agent_rc" -ne 0 ] || {
  printf 'Agent preflight unexpectedly passed with missing runtime account\n' >&2
  exit 1
}
grep -Fq 'Jenkins agent runtime identity state is partial' <<<"$missing_agent_output" || {
  printf 'Agent preflight did not report missing runtime account\nOutput:\n%s\n' "$missing_agent_output" >&2
  exit 1
}

rm -f "$mutation_dir/mutations.log"
set +e
install_output="$(
  PATH="$fake_bin:$PATH" \
  FAKE_AGENT_HOME="/wrong/agent" \
  FAKE_MUTATION_LOG="$mutation_dir/mutations.log" \
  "$repo_root/scripts/jenkins-agent-setup.sh" --env "$tmp_dir/jenkins-agent-install.env" --yes install 2>&1
)"
install_rc=$?
set -e
[ "$install_rc" -ne 0 ] || {
  printf 'Agent install unexpectedly passed with wrong runtime HOME\n' >&2
  exit 1
}
grep -Fq 'Jenkins agent runtime account jenkins-agent passwd HOME must be /var/lib/jenkins-agent, got /wrong/agent' <<<"$install_output" || {
  printf 'Agent install did not report expected HOME failure\nOutput:\n%s\n' "$install_output" >&2
  exit 1
}
if [ -s "$mutation_dir/mutations.log" ]; then
  printf 'Agent install mutated state before runtime identity validation:\n' >&2
  cat "$mutation_dir/mutations.log" >&2
  exit 1
fi
