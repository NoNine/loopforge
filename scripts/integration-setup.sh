#!/usr/bin/env bash

set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
repo_root="$(CDPATH= cd -- "$script_dir/.." && pwd)"

gerrit_env_file=""
jenkins_controller_env_file=""
jenkins_agent_env_file=""
dry_run=0
assume_yes=0
command_name=""

usage() {
  cat <<'USAGE'
Usage:
  scripts/integration-setup.sh \
    --gerrit-env FILE \
    --jenkins-controller-env FILE \
    --jenkins-agent-env FILE \
    [--dry-run] [--yes] <command>

Commands:
  configure-gerrit-ssh
  configure-agent-ssh
  configure-trigger
  validate-integration
  verify-trigger
  collect-evidence

Options:
  --gerrit-env FILE                Source reviewed Gerrit env values.
  --jenkins-controller-env FILE    Source reviewed Jenkins controller env values.
  --jenkins-agent-env FILE         Source reviewed Jenkins agent env values.
  --dry-run                        Parse inputs and report planned mutation.
  --yes                            Confirm reviewed cross-role mutation.
  -h, --help                       Show this help.

Docker Step 11 mode uses real Gerrit, Jenkins controller, and Jenkins agent
services from the shared Docker harness. Evidence is sanitized and private
keys, passwords, tokens, and LDAP bind secrets are not printed.
USAGE
}

die_usage() {
  printf 'ERROR: %s\n' "$*" >&2
  usage >&2
  exit 1
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

timestamp_utc() {
  date -u +%Y%m%dT%H%M%SZ
}

iso_timestamp_utc() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

json_quote() {
  local value
  value="${1-}"
  require_command python3
  python3 -c 'import json, sys; print(json.dumps(sys.argv[1]))' "$value"
}

url_encode() {
  local value
  value="${1:?value required}"
  require_command python3
  python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$value"
}

groovy_quote() {
  local value
  value="${1-}"
  require_command python3
  python3 - "$value" <<'PY'
import sys

value = sys.argv[1]
escaped = (
    value
    .replace("\\", "\\\\")
    .replace("'", "\\'")
    .replace("\n", "\\n")
    .replace("\r", "\\r")
    .replace("\t", "\\t")
)
print("'" + escaped + "'")
PY
}

load_env_file() {
  local label file
  label="${1:?label required}"
  file="${2:?file required}"
  [ -f "$file" ] || die_usage "Missing $label env file: $file"
  set -a
  # shellcheck disable=SC1090
  . "$file"
  set +a
}

load_inputs() {
  [ -n "$gerrit_env_file" ] || die_usage "Missing --gerrit-env FILE"
  [ -n "$jenkins_controller_env_file" ] ||
    die_usage "Missing --jenkins-controller-env FILE"
  [ -n "$jenkins_agent_env_file" ] ||
    die_usage "Missing --jenkins-agent-env FILE"
  load_env_file "Gerrit" "$gerrit_env_file"
  load_env_file "Jenkins controller" "$jenkins_controller_env_file"
  load_env_file "Jenkins agent" "$jenkins_agent_env_file"
  apply_defaults
}

apply_defaults() {
  GERRIT_HOST="${GERRIT_HOST:-gerrit-target}"
  GERRIT_HTTP_PORT="${GERRIT_HTTP_PORT:-8080}"
  GERRIT_SSH_PORT="${GERRIT_SSH_PORT:-29418}"
  GERRIT_VERIFICATION_PROJECT="${GERRIT_VERIFICATION_PROJECT:-verification-disposable-gerrit}"
  GERRIT_VERIFICATION_REF_PATTERN="${GERRIT_VERIFICATION_REF_PATTERN:-refs/*}"
  JENKINS_HOST="${JENKINS_HOST:-jenkins-controller-target}"
  JENKINS_URL="${JENKINS_URL:-http://jenkins-controller-target:8080/}"
  JENKINS_HTTP_PORT="${JENKINS_HTTP_PORT:-8080}"
  JENKINS_HOME="${JENKINS_HOME:-/harness/state/jenkins-home}"
  JENKINS_AGENT_HOST="${JENKINS_AGENT_HOST:-jenkins-agent-target}"
  JENKINS_AGENT_SSH_PORT="${JENKINS_AGENT_SSH_PORT:-2222}"
  JENKINS_AGENT_ACCOUNT="${JENKINS_AGENT_ACCOUNT:-jenkins-agent}"
  JENKINS_AGENT_REMOTE_FS="${JENKINS_AGENT_REMOTE_FS:-/home/jenkins-agent/workspace}"
  JENKINS_AGENT_LABEL="${JENKINS_AGENT_LABEL:-review-agent}"

  INTEGRATION_GERRIT_ADMIN_ACCOUNT="${INTEGRATION_GERRIT_ADMIN_ACCOUNT:-gerrit-admin}"
  INTEGRATION_GERRIT_ADMIN_PASSWORD="${INTEGRATION_GERRIT_ADMIN_PASSWORD:-admin-password}"
  INTEGRATION_JENKINS_ADMIN_ACCOUNT="${INTEGRATION_JENKINS_ADMIN_ACCOUNT:-jenkins-admin}"
  INTEGRATION_JENKINS_ADMIN_PASSWORD="${INTEGRATION_JENKINS_ADMIN_PASSWORD:-admin-password}"
  INTEGRATION_TEST_ACCOUNT="${INTEGRATION_TEST_ACCOUNT:-test-user}"
  INTEGRATION_TEST_PASSWORD="${INTEGRATION_TEST_PASSWORD:-test-password}"
  JENKINS_GERRIT_INTEGRATION_ACCOUNT="${JENKINS_GERRIT_INTEGRATION_ACCOUNT:-jenkins-gerrit}"
  JENKINS_GERRIT_INTEGRATION_PASSWORD="${JENKINS_GERRIT_INTEGRATION_PASSWORD:-integration-password}"
  JENKINS_GERRIT_INTEGRATION_GROUP="${JENKINS_GERRIT_INTEGRATION_GROUP:-gerrit-integration}"
  JENKINS_GERRIT_CREDENTIAL_ID="${JENKINS_GERRIT_CREDENTIAL_ID:-jenkins-gerrit-ssh}"
  JENKINS_AGENT_CREDENTIAL_ID="${JENKINS_AGENT_CREDENTIAL_ID:-jenkins-agent-ssh}"
  GERRIT_TRIGGER_SERVER_NAME="${GERRIT_TRIGGER_SERVER_NAME:-docker-gerrit}"
  JENKINS_VERIFICATION_JOB="${JENKINS_VERIFICATION_JOB:-docker-gerrit-verification}"
}

require_docker_mode() {
  [ "${HARNESS_MODE:-}" = "docker-harness-simulation" ] ||
    die "Docker Step 11 integration requires HARNESS_MODE=docker-harness-simulation"
  [ -n "${HARNESS_PROJECT_NAME:-}" ] || die "HARNESS_PROJECT_NAME is required"
  [ -n "${HARNESS_STATE_DIR:-}" ] || die "HARNESS_STATE_DIR is required"
  [ -n "${HARNESS_EVIDENCE_DIR:-}" ] || die "HARNESS_EVIDENCE_DIR is required"
  [ -n "${HARNESS_LOG_DIR:-}" ] || die "HARNESS_LOG_DIR is required"
  umask 077
}

confirm_mutation() {
  local name
  name="${1:?command required}"
  if [ "$dry_run" -eq 1 ]; then
    printf 'dry_run=1 command=%s mutation=skipped\n' "$name"
    return 1
  fi
  [ "$assume_yes" -eq 1 ] || die "$name mutates Docker integration state; rerun with --yes after review"
}

gerrit_container() {
  printf '%s-gerrit-target\n' "$HARNESS_PROJECT_NAME"
}

jenkins_container() {
  printf '%s-jenkins-controller-target\n' "$HARNESS_PROJECT_NAME"
}

agent_container() {
  printf '%s-jenkins-agent-target\n' "$HARNESS_PROJECT_NAME"
}

integration_state_dir() {
  printf '%s/integration\n' "$HARNESS_STATE_DIR"
}

integration_host_state_dir() {
  printf '%s/integration\n' "$HARNESS_STATE_DIR"
}

integration_container_state_dir() {
  printf '%s\n' /harness/state/integration
}

integration_log_dir() {
  printf '%s/integration\n' "$HARNESS_LOG_DIR"
}

integration_evidence_dir() {
  printf '%s/integration\n' "$HARNESS_EVIDENCE_DIR"
}

ensure_dirs() {
  mkdir -p "$(integration_host_state_dir)/keys" "$(integration_host_state_dir)/scripts" \
    "$(integration_host_state_dir)/status" "$(integration_log_dir)" "$(integration_evidence_dir)"
  chmod 0700 "$(integration_host_state_dir)" "$(integration_host_state_dir)/keys" \
    "$(integration_host_state_dir)/scripts" "$(integration_host_state_dir)/status"
}

ensure_container_integration_dirs() {
  docker_exec_sh "$(jenkins_container)" "install -d -m 700 -o jenkins -g jenkins /harness/state/integration /harness/state/integration/keys /harness/state/integration/scripts /harness/state/integration/status" >/dev/null
  docker_exec_sh "$(gerrit_container)" "install -d -m 700 /harness/state/integration/keys /harness/state/integration/scripts /harness/state/integration/status" >/dev/null
  docker_exec_sh "$(agent_container)" "install -d -m 700 /harness/state/integration/keys /harness/state/integration/scripts /harness/state/integration/status" >/dev/null
}

bounded_log_path() {
  local name
  name="${1:?name required}"
  ensure_dirs
  printf '%s/%s-%s.log\n' "$(integration_log_dir)" "$name" "$(timestamp_utc)"
}

status_file() {
  local name
  name="${1:?name required}"
  ensure_dirs
  printf '%s/status/%s.status\n' "$(integration_host_state_dir)" "$name"
}

write_evidence() {
  local checkpoint status observed log_ref extra file q_mode q_time q_checkpoint q_status q_observed q_log q_redaction q_extra
  checkpoint="${1:?checkpoint required}"
  status="${2:?status required}"
  observed="${3:?observed required}"
  log_ref="${4:-not-applicable}"
  extra="${5:-not-applicable}"
  ensure_dirs
  file="$(integration_evidence_dir)/integration-${checkpoint}-$(timestamp_utc).json"
  q_mode="$(json_quote "docker-simulation")"
  q_time="$(json_quote "$(iso_timestamp_utc)")"
  q_checkpoint="$(json_quote "$checkpoint")"
  q_status="$(json_quote "$status")"
  q_observed="$(json_quote "$observed")"
  q_log="$(json_quote "$log_ref")"
  q_redaction="$(json_quote "secrets-not-recorded; private keys, passwords, tokens, and LDAP bind secrets omitted")"
  q_extra="$(json_quote "$extra")"
  cat >"$file" <<EOF
{
  "verification_mode": $q_mode,
  "timestamp": $q_time,
  "role_or_environment": "integration",
  "checkpoint_name": $q_checkpoint,
  "command_name": "integration-setup.sh $command_name",
  "status": $q_status,
  "reviewed_input_fingerprint": "docker-seeded-ldap-and-generated-integration-state",
  "artifact_manifest_references": "not-applicable",
  "checksum_references": "not-applicable",
  "checksum_verification_result": "not-applicable",
  "observed_checks": $q_observed,
  "bounded_log_references": $q_log,
  "redaction_status": $q_redaction,
  "integration_context": $q_extra,
  "mode_labels": ["docker-simulation", "simulation-only"]
}
EOF
  printf '%s\n' "$file"
}

docker_exec() {
  local container
  container="${1:?container required}"
  shift
  docker exec "$container" "$@"
}

docker_exec_sh() {
  local container command_text
  container="${1:?container required}"
  command_text="${2:?command required}"
  docker exec "$container" sh -lc "$command_text"
}

gerrit_curl() {
  local user password method path data_file
  user="${1:?user required}"
  password="${2:?password required}"
  method="${3:?method required}"
  path="${4:?path required}"
  data_file="${5:-}"
  if [ -n "$data_file" ]; then
    docker_exec "$(gerrit_container)" curl -fsS -u "$user:$password" -X "$method" \
      -H "Content-Type: application/json" --data-binary "@$data_file" \
      "http://$GERRIT_HOST:$GERRIT_HTTP_PORT/a$path"
  else
    docker_exec "$(gerrit_container)" curl -fsS -u "$user:$password" -X "$method" \
      "http://$GERRIT_HOST:$GERRIT_HTTP_PORT/a$path"
  fi
}

gerrit_curl_text() {
  local user password path data_file
  user="${1:?user required}"
  password="${2:?password required}"
  path="${3:?path required}"
  data_file="${4:?data file required}"
  docker_exec "$(gerrit_container)" curl -fsS -u "$user:$password" -X POST \
    -H "Content-Type: text/plain" --data-binary "@$data_file" \
    "http://$GERRIT_HOST:$GERRIT_HTTP_PORT/a$path"
}

gerrit_account_has_capability() {
  local user password capability response
  user="${1:?user required}"
  password="${2:?password required}"
  capability="${3:?capability required}"
  response="$(gerrit_curl "$user" "$password" GET "/accounts/self/capabilities")"
  python3 - "$capability" "$response" <<'PY'
import json
import sys

text = sys.argv[2]
if text.startswith(")]}'"):
    text = text.split("\n", 1)[1]
data = json.loads(text)
raise SystemExit(0 if data.get(sys.argv[1]) is True else 1)
PY
}

gerrit_project_has_verified_label() {
  local project
  project="${1:?project required}"
  gerrit_curl "$INTEGRATION_GERRIT_ADMIN_ACCOUNT" "$INTEGRATION_GERRIT_ADMIN_PASSWORD" GET "/projects/$project/labels/Verified" >/dev/null 2>&1
}

gerrit_account_can_vote_verified() {
  local project response
  project="${1:?project required}"
  response="$(gerrit_curl "$JENKINS_GERRIT_INTEGRATION_ACCOUNT" "$JENKINS_GERRIT_INTEGRATION_PASSWORD" GET "/projects/$project/labels/?voteable-on-ref=refs/heads/master")"
  python3 - "$response" <<'PY'
import json
import sys

text = sys.argv[1]
if text.startswith(")]}'"):
    text = text.split("\n", 1)[1]
data = json.loads(text)
raise SystemExit(0 if "Verified" in data else 1)
PY
}

ensure_gerrit_rest_admin() {
  local log admin_member
  log="${1:?log required}"
  admin_member="${INTEGRATION_GERRIT_ADMIN_ACCOUNT// /%20}"
  if gerrit_account_has_capability "$INTEGRATION_GERRIT_ADMIN_ACCOUNT" "$INTEGRATION_GERRIT_ADMIN_PASSWORD" administrateServer >>"$log" 2>&1; then
    printf 'gerrit_rest_admin=ready account=%s\n' "$INTEGRATION_GERRIT_ADMIN_ACCOUNT" >>"$log"
    return 0
  fi
  printf 'gerrit_rest_admin=missing account=%s repair=rest-internal-administrators\n' "$INTEGRATION_GERRIT_ADMIN_ACCOUNT" >>"$log"
  if ! gerrit_account_has_capability "$JENKINS_GERRIT_INTEGRATION_ACCOUNT" "$JENKINS_GERRIT_INTEGRATION_PASSWORD" administrateServer >>"$log" 2>&1; then
    die "Configured Gerrit admin lacks administrateServer and no REST admin account is available for reviewed ACL setup"
  fi
  gerrit_curl "$JENKINS_GERRIT_INTEGRATION_ACCOUNT" "$JENKINS_GERRIT_INTEGRATION_PASSWORD" PUT "/groups/Administrators/members/$admin_member" >>"$log" 2>&1
  gerrit_account_has_capability "$INTEGRATION_GERRIT_ADMIN_ACCOUNT" "$INTEGRATION_GERRIT_ADMIN_PASSWORD" administrateServer >>"$log" 2>&1 ||
    die "REST Administrators group repair did not grant administrateServer to configured Gerrit admin"
  printf 'gerrit_rest_admin=ready account=%s repair=rest-internal-administrators\n' "$INTEGRATION_GERRIT_ADMIN_ACCOUNT" >>"$log"
}

ensure_gerrit_integration_group() {
  local log group account
  log="${1:?log required}"
  group="$(url_encode "$JENKINS_GERRIT_INTEGRATION_GROUP")"
  account="$(url_encode "$JENKINS_GERRIT_INTEGRATION_ACCOUNT")"
  if ! gerrit_curl "$INTEGRATION_GERRIT_ADMIN_ACCOUNT" "$INTEGRATION_GERRIT_ADMIN_PASSWORD" GET "/groups/$group" >>"$log" 2>&1; then
    gerrit_curl "$INTEGRATION_GERRIT_ADMIN_ACCOUNT" "$INTEGRATION_GERRIT_ADMIN_PASSWORD" PUT "/groups/$group" >>"$log" 2>&1
    printf 'integration_group=created group=%s\n' "$JENKINS_GERRIT_INTEGRATION_GROUP" >>"$log"
  else
    printf 'integration_group=exists group=%s\n' "$JENKINS_GERRIT_INTEGRATION_GROUP" >>"$log"
  fi
  gerrit_curl "$INTEGRATION_GERRIT_ADMIN_ACCOUNT" "$INTEGRATION_GERRIT_ADMIN_PASSWORD" PUT "/groups/$group/members/$account" >>"$log" 2>&1
  printf 'integration_group_member=present group=%s account=%s\n' "$JENKINS_GERRIT_INTEGRATION_GROUP" "$JENKINS_GERRIT_INTEGRATION_ACCOUNT" >>"$log"
}

ensure_gerrit_verification_project() {
  local log project_json container_json project
  log="${1:?log required}"
  project="$(url_encode "$GERRIT_VERIFICATION_PROJECT")"
  project_json="$(integration_host_state_dir)/status/verification-project.json"
  container_json="/tmp/step11-verification-project.json"
  cat >"$project_json" <<EOF
{
  "description": "Docker Step 11 disposable verification project",
  "submit_type": "MERGE_IF_NECESSARY",
  "create_empty_commit": true
}
EOF
  docker cp "$project_json" "$(gerrit_container):$container_json" >>"$log" 2>&1
  if ! gerrit_curl "$INTEGRATION_GERRIT_ADMIN_ACCOUNT" "$INTEGRATION_GERRIT_ADMIN_PASSWORD" GET "/projects/$project" >>"$log" 2>&1; then
    gerrit_curl "$INTEGRATION_GERRIT_ADMIN_ACCOUNT" "$INTEGRATION_GERRIT_ADMIN_PASSWORD" PUT "/projects/$project" "$container_json" >>"$log" 2>&1
    printf 'verification_project=created project=%s\n' "$GERRIT_VERIFICATION_PROJECT" >>"$log"
  else
    printf 'verification_project=exists project=%s\n' "$GERRIT_VERIFICATION_PROJECT" >>"$log"
  fi
}

ensure_verified_label_and_access() {
  local log label_json project_access_json global_access_json project_id all_projects_id
  log="${1:?log required}"
  project_id="$(url_encode "$GERRIT_VERIFICATION_PROJECT")"
  all_projects_id="$(url_encode All-Projects)"
  ensure_gerrit_verification_project "$log"
  ensure_gerrit_integration_group "$log"
  label_json="$(integration_host_state_dir)/status/verified-label.json"
  project_access_json="$(integration_host_state_dir)/status/integration-project-access.json"
  global_access_json="$(integration_host_state_dir)/status/integration-global-access.json"

  cat >"$label_json" <<EOF
{
  "commit_message": "Docker Step 11 simulation-only direct REST Verified label",
  "function": "NoBlock",
  "default_value": 0,
  "values": {
    "-1": "Fails",
    " 0": "No score",
    "+1": "Verified"
  }
}
EOF
  docker cp "$label_json" "$(gerrit_container):/tmp/step11-verified-label.json" >>"$log" 2>&1
  gerrit_curl "$INTEGRATION_GERRIT_ADMIN_ACCOUNT" "$INTEGRATION_GERRIT_ADMIN_PASSWORD" \
    PUT "/projects/$project_id/labels/Verified" "/tmp/step11-verified-label.json" >>"$log" 2>&1
  printf 'verified_label_apply=simulation-only-direct-rest project=%s endpoint=projects.labels\n' "$GERRIT_VERIFICATION_PROJECT" >>"$log"

  cat >"$global_access_json" <<EOF
{
  "commit_message": "Docker Step 11 simulation-only direct REST stream-events access",
  "add": {
    "GLOBAL_CAPABILITIES": {
      "permissions": {
        "streamEvents": {
          "rules": {
            "$JENKINS_GERRIT_INTEGRATION_GROUP": {
              "action": "ALLOW"
            }
          }
        }
      }
    }
  }
}
EOF
  docker cp "$global_access_json" "$(gerrit_container):/tmp/step11-integration-global-access.json" >>"$log" 2>&1
  gerrit_curl "$INTEGRATION_GERRIT_ADMIN_ACCOUNT" "$INTEGRATION_GERRIT_ADMIN_PASSWORD" \
    POST "/projects/$all_projects_id/access" "/tmp/step11-integration-global-access.json" >>"$log" 2>&1
  printf 'access_apply=simulation-only-direct-rest project=All-Projects endpoint=projects.access capability=streamEvents\n' >>"$log"

  cat >"$project_access_json" <<EOF
{
  "commit_message": "Docker Step 11 simulation-only direct REST verification project access",
  "add": {
    "refs/heads/*": {
      "permissions": {
        "read": {
          "rules": {
            "$JENKINS_GERRIT_INTEGRATION_GROUP": {
              "action": "ALLOW"
            }
          }
        },
        "label-Verified": {
          "rules": {
            "$JENKINS_GERRIT_INTEGRATION_GROUP": {
              "action": "ALLOW",
              "min": -1,
              "max": 1
            }
          }
        }
      }
    }
  }
}
EOF
  docker cp "$project_access_json" "$(gerrit_container):/tmp/step11-integration-project-access.json" >>"$log" 2>&1
  gerrit_curl "$INTEGRATION_GERRIT_ADMIN_ACCOUNT" "$INTEGRATION_GERRIT_ADMIN_PASSWORD" \
    POST "/projects/$project_id/access" "/tmp/step11-integration-project-access.json" >>"$log" 2>&1
  printf 'access_apply=simulation-only-direct-rest project=%s endpoint=projects.access permissions=read,label-Verified\n' "$GERRIT_VERIFICATION_PROJECT" >>"$log"
  gerrit_curl "$INTEGRATION_GERRIT_ADMIN_ACCOUNT" "$INTEGRATION_GERRIT_ADMIN_PASSWORD" GET "/projects/$project_id/labels/Verified" >>"$log" 2>&1
  gerrit_account_can_vote_verified "$project_id" >>"$log" 2>&1 ||
    die "Verified label is not voteable by Jenkins integration account on $GERRIT_VERIFICATION_PROJECT"
  printf 'verified_label=ready project=%s voteable_by=%s\n' "$GERRIT_VERIFICATION_PROJECT" "$JENKINS_GERRIT_INTEGRATION_ACCOUNT" >>"$log"
}

gerrit_json_change_number() {
  local file
  file="${1:?json file required}"
  python3 - "$file" <<'PY'
import json
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text()
if text.startswith(")]}'"):
    text = text.split("\n", 1)[1]
data = json.loads(text)
print(data["_number"])
PY
}

submit_review_change() {
  local change_file log change submit_json container_json
  change_file="${1:?change file required}"
  log="${2:?log required}"
  change="$(gerrit_json_change_number "$change_file")"
  submit_review_change_number "$change" "$log"
}

submit_review_change_number() {
  local change log submit_json container_json
  change="${1:?change required}"
  log="${2:?log required}"
  submit_json="$(integration_host_state_dir)/status/submit-$change.json"
  container_json="/tmp/step11-submit-$change.json"
  cat >"$submit_json" <<EOF
{
  "wait_for_merge": true
}
EOF
  docker cp "$submit_json" "$(gerrit_container):$container_json" >>"$log" 2>&1
  gerrit_curl "$INTEGRATION_GERRIT_ADMIN_ACCOUNT" "$INTEGRATION_GERRIT_ADMIN_PASSWORD" POST "/changes/$change/submit" "$container_json" >>"$log" 2>&1
  printf 'submitted_reviewed_config_change=%s\n' "$change" >>"$log"
}

jenkins_crumb_header() {
  docker_exec "$(jenkins_container)" curl -fsS -u "$INTEGRATION_JENKINS_ADMIN_ACCOUNT:$INTEGRATION_JENKINS_ADMIN_PASSWORD" \
    "http://$JENKINS_HOST:$JENKINS_HTTP_PORT/crumbIssuer/api/json" |
    python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["crumbRequestField"] + ":" + d["crumb"])'
}

jenkins_script() {
  local script_file container_script log
  script_file="${1:?script file required}"
  log="${2:?log required}"
  chmod 0600 "$script_file"
  container_script="$(integration_container_state_dir)/scripts/$(basename "$script_file")"
  docker cp "$script_file" "$(jenkins_container):$container_script" >>"$log" 2>&1
  docker_exec_sh "$(jenkins_container)" "chown jenkins:jenkins '$container_script' && chmod 600 '$container_script'" >>"$log" 2>&1
  docker_exec_sh "$(jenkins_container)" "
    set -e
    crumb_json=/tmp/jenkins-step11-crumb.json
    cookie_jar=/tmp/jenkins-step11-cookies.txt
    curl -fsS -u '$INTEGRATION_JENKINS_ADMIN_ACCOUNT:$INTEGRATION_JENKINS_ADMIN_PASSWORD' \
      -c \"\$cookie_jar\" \
      \"http://$JENKINS_HOST:$JENKINS_HTTP_PORT/crumbIssuer/api/json\" >\"\$crumb_json\"
    crumb=\$(sed -n 's/.*\"crumb\":\"\\([^\"]*\\)\".*/\\1/p' \"\$crumb_json\")
    crumb_field=\$(sed -n 's/.*\"crumbRequestField\":\"\\([^\"]*\\)\".*/\\1/p' \"\$crumb_json\")
    test -n \"\$crumb\"
    test -n \"\$crumb_field\"
    crumb_header=\"\$crumb_field:\$crumb\"
    script_out=/tmp/jenkins-step11-script.out
    curl -fsS -u '$INTEGRATION_JENKINS_ADMIN_ACCOUNT:$INTEGRATION_JENKINS_ADMIN_PASSWORD' \
      -b \"\$cookie_jar\" -H \"\$crumb_header\" \
      --data-urlencode \"script@$container_script\" \
      \"http://$JENKINS_HOST:$JENKINS_HTTP_PORT/scriptText\" >\"\$script_out\"
    cat \"\$script_out\"
    if grep -Eq '(^|[[:space:]])(java|groovy|hudson|org)[.].*Exception|Exception:|MissingMethodException|FileNotFoundException|RejectedAccessException' \"\$script_out\"; then
      exit 1
    fi
  " >>"$log" 2>&1
}

key_fingerprint() {
  local file
  file="${1:?public key required}"
  ssh-keygen -lf "$file" | awk '{print $2}'
}

ensure_controller_keypair() {
  local name public_base public log container_private
  name="${1:?name required}"
  log="${2:?log required}"
  public_base="$(integration_host_state_dir)/keys/$name"
  public="$public_base.pub"
  container_private="$(integration_container_state_dir)/keys/$name"
  docker_exec_sh "$(jenkins_container)" "
    set -e
    install -d -m 700 -o jenkins -g jenkins '$(integration_container_state_dir)/keys'
    if [ ! -s '$container_private' ]; then
      su -s /bin/sh jenkins -c \"ssh-keygen -q -t ed25519 -N '' -C '$name-docker-step11' -f '$container_private'\"
    fi
  " >>"$log" 2>&1
  docker_exec_sh "$(jenkins_container)" "
    set -e
    chown jenkins:jenkins '$container_private'
    chmod 600 '$container_private'
    su -s /bin/sh jenkins -c \"ssh-keygen -y -f '$container_private' >'$container_private.pub'\"
    chmod 644 '$container_private.pub'
  " >>"$log" 2>&1
  docker cp "$(jenkins_container):$container_private.pub" "$public" >>"$log" 2>&1
  chmod 0644 "$public"
  printf '%s\n' "$public_base"
}

ensure_controller_private_key_permissions() {
  local key_base name container_private
  key_base="${1:?key base required}"
  name="${2:?key name required}"
  ensure_container_integration_dirs
  container_private="$(integration_container_state_dir)/keys/$name"
  docker_exec_sh "$(jenkins_container)" "test -s '$container_private' && chown jenkins:jenkins '$container_private' && chmod 600 '$container_private'" >/dev/null
}

register_gerrit_public_key() {
  local account public log
  account="${1:?account required}"
  public="${2:?public key required}"
  log="${3:?log required}"
  docker cp "$public" "$(gerrit_container):/tmp/jenkins-gerrit.pub" >>"$log" 2>&1
  if gerrit_curl_text "$JENKINS_GERRIT_INTEGRATION_ACCOUNT" "$JENKINS_GERRIT_INTEGRATION_PASSWORD" "/accounts/self/sshkeys" "/tmp/jenkins-gerrit.pub" >>"$log" 2>&1; then
    printf 'key_registration=rest-self\n' >>"$log"
    return 0
  fi
  printf 'key_registration=rest-self-rejected status=failed-closed\n' >>"$log"
  return 1
}

cmd_configure_gerrit_ssh() {
  local log private public fp acl_status account_status key_status
  load_inputs
  require_docker_mode
  confirm_mutation configure-gerrit-ssh || return 0
  require_command docker
  require_command ssh-keygen
  ensure_dirs
  ensure_container_integration_dirs
  log="$(bounded_log_path configure-gerrit-ssh)"
  private="$(ensure_controller_keypair jenkins-gerrit "$log")"
  public="$private.pub"
  fp="$(key_fingerprint "$public")"
  ensure_controller_private_key_permissions "$private" jenkins-gerrit
  gerrit_curl "$JENKINS_GERRIT_INTEGRATION_ACCOUNT" "$JENKINS_GERRIT_INTEGRATION_PASSWORD" GET "/accounts/self" >>"$log" 2>&1
  register_gerrit_public_key "$JENKINS_GERRIT_INTEGRATION_ACCOUNT" "$public" "$log"
  gerrit_curl "$INTEGRATION_GERRIT_ADMIN_ACCOUNT" "$INTEGRATION_GERRIT_ADMIN_PASSWORD" GET "/accounts/self" >>"$log" 2>&1
  ensure_gerrit_rest_admin "$log"

  ensure_verified_label_and_access "$log"
  account_status="$(status_file jenkins-gerrit-account)"
  key_status="$(status_file jenkins-gerrit-key)"
  acl_status="$(status_file gerrit-acl)"
  printf 'account=%s public_key_fingerprint=%s\n' "$JENKINS_GERRIT_INTEGRATION_ACCOUNT" "$fp" >"$account_status"
  printf 'private_key_custody=jenkins-controller-state public_key_fingerprint=%s\n' "$fp" >"$key_status"
  printf 'apply_mode=simulation-only-direct-rest acl_scope=docker-verification-project group=%s\n' "$JENKINS_GERRIT_INTEGRATION_GROUP" >"$acl_status"
  write_evidence jenkins-to-gerrit-ssh configured "Jenkins-owned key generated, public key registered through Gerrit REST, and Docker simulation integration ACLs applied through labeled direct Gerrit REST test automation" "$log" "public_key_fingerprint=$fp apply_mode=simulation-only-direct-rest" >/dev/null
  printf 'status=pass command=configure-gerrit-ssh public_key_fingerprint=%s acl_apply=simulation-only-direct-rest log=%s\n' "$fp" "$log"
}

cmd_configure_agent_ssh() {
  local log private public fp groovy known_hosts
  load_inputs
  require_docker_mode
  confirm_mutation configure-agent-ssh || return 0
  require_command docker
  require_command ssh-keygen
  ensure_dirs
  ensure_container_integration_dirs
  log="$(bounded_log_path configure-agent-ssh)"
  private="$(ensure_controller_keypair jenkins-agent "$log")"
  public="$private.pub"
  fp="$(key_fingerprint "$public")"
  ensure_controller_private_key_permissions "$private" jenkins-agent
  docker cp "$public" "$(agent_container):/tmp/jenkins-agent.pub" >>"$log" 2>&1
  docker_exec_sh "$(agent_container)" "
    set -e
    home=\$(getent passwd '$JENKINS_AGENT_ACCOUNT' | awk -F: '{print \$6}')
    test -n \"\$home\"
    install -d -m 700 -o '$JENKINS_AGENT_ACCOUNT' -g '$JENKINS_AGENT_ACCOUNT' \"\$home/.ssh\"
    touch \"\$home/.ssh/authorized_keys\"
    grep -F -x -f /tmp/jenkins-agent.pub \"\$home/.ssh/authorized_keys\" >/dev/null 2>&1 || cat /tmp/jenkins-agent.pub >>\"\$home/.ssh/authorized_keys\"
    chown '$JENKINS_AGENT_ACCOUNT:$JENKINS_AGENT_ACCOUNT' \"\$home/.ssh/authorized_keys\"
    chmod 600 \"\$home/.ssh/authorized_keys\"
    rm -rf '$JENKINS_AGENT_REMOTE_FS/remoting.jar' '$JENKINS_AGENT_REMOTE_FS/remoting'
    install -d -m 755 -o '$JENKINS_AGENT_ACCOUNT' -g '$JENKINS_AGENT_ACCOUNT' '$JENKINS_AGENT_REMOTE_FS'
  " >>"$log" 2>&1
  known_hosts="$(integration_host_state_dir)/keys/agent-known-hosts"
  docker_exec_sh "$(jenkins_container)" "ssh-keyscan -p '$JENKINS_AGENT_SSH_PORT' '$JENKINS_AGENT_HOST' 2>/dev/null" >"$known_hosts"
  docker cp "$known_hosts" "$(jenkins_container):$(integration_container_state_dir)/keys/agent-known-hosts" >>"$log" 2>&1
  docker cp "$known_hosts" "$(jenkins_container):/tmp/step11-agent-known-hosts" >>"$log" 2>&1
  docker_exec_sh "$(jenkins_container)" "
    set -e
    install -d -m 700 -o jenkins -g jenkins '$JENKINS_HOME/.ssh'
    install -m 600 -o jenkins -g jenkins /tmp/step11-agent-known-hosts '$JENKINS_HOME/.ssh/known_hosts'
  " >>"$log" 2>&1
  groovy="$(integration_host_state_dir)/scripts/configure-agent.groovy"
  cat >"$groovy" <<EOF
import jenkins.model.Jenkins
import com.cloudbees.plugins.credentials.CredentialsScope
import com.cloudbees.plugins.credentials.SystemCredentialsProvider
import com.cloudbees.jenkins.plugins.sshcredentials.impl.BasicSSHUserPrivateKey
import hudson.slaves.DumbSlave
import hudson.slaves.RetentionStrategy
import hudson.plugins.sshslaves.SSHLauncher
import hudson.plugins.sshslaves.verifiers.KnownHostsFileKeyVerificationStrategy

def j = Jenkins.instance
def store = SystemCredentialsProvider.instance.store
def existing = SystemCredentialsProvider.instance.credentials.find { it.id == '$JENKINS_AGENT_CREDENTIAL_ID' }
if (existing != null) {
  store.removeCredentials(com.cloudbees.plugins.credentials.domains.Domain.global(), existing)
}
def key = new File('$(integration_container_state_dir)/keys/jenkins-agent').text
def credential = new BasicSSHUserPrivateKey(
  CredentialsScope.GLOBAL,
  '$JENKINS_AGENT_CREDENTIAL_ID',
  '$JENKINS_AGENT_ACCOUNT',
  new BasicSSHUserPrivateKey.DirectEntryPrivateKeySource(key),
  '',
  'Docker Step 11 Jenkins agent SSH key')
store.addCredentials(com.cloudbees.plugins.credentials.domains.Domain.global(), credential)
def old = j.getNode('$JENKINS_AGENT_LABEL')
if (old != null) {
  j.removeNode(old)
}
def launcher = new SSHLauncher('$JENKINS_AGENT_HOST', $JENKINS_AGENT_SSH_PORT, '$JENKINS_AGENT_CREDENTIAL_ID', null, null, null, null, null, null, null, new KnownHostsFileKeyVerificationStrategy())
def node = new DumbSlave('$JENKINS_AGENT_LABEL', '$JENKINS_AGENT_REMOTE_FS', launcher)
node.numExecutors = 1
node.labelString = '$JENKINS_AGENT_LABEL'
node.retentionStrategy = RetentionStrategy.INSTANCE
j.addNode(node)
j.save()
println('configured_agent_node=$JENKINS_AGENT_LABEL credential=$JENKINS_AGENT_CREDENTIAL_ID')
EOF
  jenkins_script "$groovy" "$log"
  write_evidence agent-connection configured "Agent public key authorized, Jenkins SSH credential and node configured through Jenkins runtime script API" "$log" "agent_public_key_fingerprint=$fp" >/dev/null
  printf 'status=pass command=configure-agent-ssh public_key_fingerprint=%s node=%s log=%s\n' "$fp" "$JENKINS_AGENT_LABEL" "$log"
}

cmd_configure_trigger() {
  local log groovy q_gerrit_trigger_server q_gerrit_host q_gerrit_user q_gerrit_url q_gerrit_key q_gerrit_http_user q_gerrit_http_password q_job q_label q_project
  load_inputs
  require_docker_mode
  confirm_mutation configure-trigger || return 0
  ensure_dirs
  ensure_container_integration_dirs
  log="$(bounded_log_path configure-trigger)"
  groovy="$(integration_host_state_dir)/scripts/configure-trigger.groovy"
  q_gerrit_trigger_server="$(groovy_quote "$GERRIT_TRIGGER_SERVER_NAME")"
  q_gerrit_host="$(groovy_quote "$GERRIT_HOST")"
  q_gerrit_user="$(groovy_quote "$JENKINS_GERRIT_INTEGRATION_ACCOUNT")"
  q_gerrit_url="$(groovy_quote "http://$GERRIT_HOST:$GERRIT_HTTP_PORT/")"
  q_gerrit_key="$(groovy_quote "$(integration_container_state_dir)/keys/jenkins-gerrit")"
  q_gerrit_http_user="$(groovy_quote "$JENKINS_GERRIT_INTEGRATION_ACCOUNT")"
  q_gerrit_http_password="$(groovy_quote "$JENKINS_GERRIT_INTEGRATION_PASSWORD")"
  q_job="$(groovy_quote "$JENKINS_VERIFICATION_JOB")"
  q_label="$(groovy_quote "$JENKINS_AGENT_LABEL")"
  q_project="$(groovy_quote "$GERRIT_VERIFICATION_PROJECT")"
  cat >"$groovy" <<EOF
import jenkins.model.Jenkins
import hudson.model.FreeStyleProject
import hudson.model.ParametersDefinitionProperty
import hudson.model.StringParameterDefinition
import hudson.tasks.Shell
import com.sonyericsson.hudson.plugins.gerrit.trigger.PluginImpl
import com.sonyericsson.hudson.plugins.gerrit.trigger.GerritServer
import com.sonyericsson.hudson.plugins.gerrit.trigger.config.Config
import com.sonyericsson.hudson.plugins.gerrit.trigger.hudsontrigger.GerritTrigger
import com.sonyericsson.hudson.plugins.gerrit.trigger.hudsontrigger.data.Branch
import com.sonyericsson.hudson.plugins.gerrit.trigger.hudsontrigger.data.CompareType
import com.sonyericsson.hudson.plugins.gerrit.trigger.hudsontrigger.data.GerritProject
import com.sonyericsson.hudson.plugins.gerrit.trigger.hudsontrigger.events.PluginPatchsetCreatedEvent
import com.sonymobile.tools.gerrit.gerritevents.dto.rest.Notify
import java.io.File

def j = Jenkins.instance
def plugin = PluginImpl.instance
if (plugin == null) { throw new RuntimeException('Gerrit Trigger plugin is not loaded') }
def existingServer = plugin.getServer($q_gerrit_trigger_server)
if (existingServer != null) {
  try { existingServer.stop() } catch (Throwable ignored) {}
  plugin.removeServer(existingServer)
}
def config = new Config()
config.setGerritHostName($q_gerrit_host)
config.setGerritSshPort($GERRIT_SSH_PORT)
config.setGerritUserName($q_gerrit_user)
config.setGerritFrontEndUrl($q_gerrit_url)
config.setGerritAuthKeyFile(new File($q_gerrit_key))
config.setGerritAuthKeyFilePassword('')
config.setBuildScheduleDelay(0)
config.setUseRestApi(true)
config.setRestVerified(true)
config.setRestCodeReview(true)
config.setGerritHttpUserName($q_gerrit_http_user)
config.setGerritHttpPassword($q_gerrit_http_password)
config.setGerritBuildStartedVerifiedValue(0)
config.setGerritBuildSuccessfulVerifiedValue(1)
config.setGerritBuildFailedVerifiedValue(-1)
config.setGerritBuildUnstableVerifiedValue(-1)
config.setNotificationLevel(Notify.NONE)
def server = new GerritServer($q_gerrit_trigger_server)
server.setNoConnectionOnStartup(false)
server.setConfig(config)
plugin.addServer(server)
plugin.save()
server.start()
server.startConnection()

def old = j.getItem($q_job)
if (old != null) {
  old.delete()
}
def job = j.createProject(FreeStyleProject, $q_job)
job.assignedLabel = j.getLabel($q_label)
job.addProperty(new ParametersDefinitionProperty(
  new StringParameterDefinition('GERRIT_CHANGE_NUMBER', ''),
  new StringParameterDefinition('GERRIT_PATCHSET_NUMBER', '1')))
job.buildersList.add(new Shell('set -eu\\nprintf \"node=%s\\\\n\" \"\$(hostname)\" > step11-agent-proof.txt\\nprintf \"change=%s patchset=%s event=%s\\\\n\" \"\${GERRIT_CHANGE_NUMBER:-}\" \"\${GERRIT_PATCHSET_NUMBER:-}\" \"\${GERRIT_EVENT_TYPE:-}\" >> step11-agent-proof.txt\\ntest -n \"\${GERRIT_CHANGE_NUMBER:-}\"\\ntest -n \"\${GERRIT_PATCHSET_NUMBER:-}\"\\njava -version >/dev/null 2>&1\\n'))
def branch = new Branch(CompareType.PLAIN, 'master')
def project = new GerritProject(CompareType.PLAIN, $q_project, [branch], [], [], [], false)
def trigger = new GerritTrigger([project])
trigger.setServerName($q_gerrit_trigger_server)
trigger.setTriggerOnEvents([new PluginPatchsetCreatedEvent()])
trigger.setSilentMode(false)
trigger.setSilentStartMode(false)
trigger.setGerritBuildStartedVerifiedValue(0)
trigger.setGerritBuildSuccessfulVerifiedValue(1)
trigger.setGerritBuildFailedVerifiedValue(-1)
trigger.setGerritBuildUnstableVerifiedValue(-1)
job.addTrigger(trigger)
job.save()
trigger.start(job, true)
println('configured_verification_job=' + $q_job + ' label=' + $q_label + ' trigger_server=' + $q_gerrit_trigger_server + ' gerrit_trigger=enabled review_apply=simulation-only-direct-rest')
EOF
  jenkins_script "$groovy" "$log"
  printf 'job=%s label=%s trigger_server=%s mode=real-gerrit-trigger-plugin review_apply=simulation-only-direct-rest\n' "$JENKINS_VERIFICATION_JOB" "$JENKINS_AGENT_LABEL" "$GERRIT_TRIGGER_SERVER_NAME" >"$(status_file trigger)"
  write_evidence trigger configured "Jenkins Gerrit Trigger server and disposable verification job configured through the Jenkins runtime plugin API; Docker simulation posts review results through Gerrit REST" "$log" "job=$JENKINS_VERIFICATION_JOB label=$JENKINS_AGENT_LABEL review_apply=simulation-only-direct-rest" >/dev/null
  printf 'status=pass command=configure-trigger job=%s label=%s log=%s\n' "$JENKINS_VERIFICATION_JOB" "$JENKINS_AGENT_LABEL" "$log"
}

ssh_from_controller_to_gerrit() {
  local command_text
  command_text="${1:?command required}"
  docker_exec_sh "$(jenkins_container)" "ssh -i $(integration_container_state_dir)/keys/jenkins-gerrit -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p '$GERRIT_SSH_PORT' '$JENKINS_GERRIT_INTEGRATION_ACCOUNT@$GERRIT_HOST' $command_text"
}

validate_agent_online() {
  local log groovy
  log="${1:?log required}"
  groovy="$(integration_host_state_dir)/scripts/validate-agent-online.groovy"
  cat >"$groovy" <<EOF
import jenkins.model.Jenkins
def node = Jenkins.instance.getNode('$JENKINS_AGENT_LABEL')
assert node != null
def comp = node.toComputer()
if (comp == null) { throw new RuntimeException('agent computer missing') }
comp.connect(false).get()
if (!comp.isOnline()) { throw new RuntimeException('agent is not online') }
println('agent_online=true node=$JENKINS_AGENT_LABEL')
EOF
  jenkins_script "$groovy" "$log"
}

schedule_smoke_build() {
  local log groovy
  log="${1:?log required}"
  groovy="$(integration_host_state_dir)/scripts/schedule-smoke.groovy"
  cat >"$groovy" <<EOF
import jenkins.model.Jenkins
import hudson.model.Cause
import hudson.model.ParametersAction
import hudson.model.StringParameterValue
def job = Jenkins.instance.getItem('$JENKINS_VERIFICATION_JOB')
assert job != null
def params = new ParametersAction(
  new StringParameterValue('GERRIT_CHANGE_NUMBER', '0'),
  new StringParameterValue('GERRIT_PATCHSET_NUMBER', '1'))
def q = job.scheduleBuild2(0, new Cause.UserIdCause(), params)
def build = q.get()
while (build.isBuilding()) { Thread.sleep(1000) }
if (build.result.toString() != 'SUCCESS') { throw new RuntimeException('smoke build result=' + build.result) }
if (build.builtOnStr != '$JENKINS_AGENT_LABEL') { throw new RuntimeException('smoke build did not run on expected agent: ' + build.builtOnStr) }
println('scheduling=pass build=' + build.number + ' node=' + build.builtOnStr)
EOF
  jenkins_script "$groovy" "$log"
}

prove_stream_events() {
  local log event_project event_json project_json container_json container_project_json listener_log listener_pid change_file
  log="${1:?log required}"
  event_project="${GERRIT_VERIFICATION_PROJECT}-stream-events"
  event_json="$(integration_host_state_dir)/status/stream-event-change.json"
  project_json="$(integration_host_state_dir)/status/stream-event-project.json"
  container_json="/tmp/step11-stream-event-change.json"
  container_project_json="/tmp/step11-stream-event-project.json"
  listener_log="$(integration_log_dir)/stream-events-observe-$(timestamp_utc).log"
  change_file="$(integration_host_state_dir)/status/stream-event-create-result.json"
  cat >"$project_json" <<EOF
{
  "description": "Docker Step 11 stream-events validation project",
  "submit_type": "MERGE_IF_NECESSARY",
  "create_empty_commit": true
}
EOF
  cat >"$event_json" <<EOF
{
  "project": "$event_project",
  "branch": "master",
  "subject": "Docker Step 11 stream-events validation"
}
EOF
  docker cp "$project_json" "$(gerrit_container):$container_project_json" >>"$log" 2>&1
  docker cp "$event_json" "$(gerrit_container):$container_json" >>"$log" 2>&1
  if ! gerrit_curl "$INTEGRATION_GERRIT_ADMIN_ACCOUNT" "$INTEGRATION_GERRIT_ADMIN_PASSWORD" PUT "/projects/$event_project" "$container_project_json" >>"$log" 2>&1; then
    gerrit_curl "$INTEGRATION_GERRIT_ADMIN_ACCOUNT" "$INTEGRATION_GERRIT_ADMIN_PASSWORD" GET "/projects/$event_project" >>"$log" 2>&1 ||
      die "Gerrit REST could not create or find stream-events project $event_project"
  fi
  (
    docker exec "$(jenkins_container)" ssh \
      -i "$(integration_container_state_dir)/keys/jenkins-gerrit" \
      -o BatchMode=yes \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      -p "$GERRIT_SSH_PORT" \
      "$JENKINS_GERRIT_INTEGRATION_ACCOUNT@$GERRIT_HOST" \
      gerrit stream-events >"$listener_log" 2>&1
  ) &
  listener_pid="$!"
  sleep 2
  gerrit_curl "$INTEGRATION_TEST_ACCOUNT" "$INTEGRATION_TEST_PASSWORD" POST "/changes/" "$container_json" >"$change_file"
  for _ in $(seq 1 20); do
    if grep -Eq '"type":"patchset-created"|"type": "patchset-created"' "$listener_log"; then
      kill "$listener_pid" >/dev/null 2>&1 || true
      wait "$listener_pid" >/dev/null 2>&1 || true
      printf 'stream_events=pass log=%s\n' "$listener_log" >>"$log"
      return 0
    fi
    sleep 1
  done
  kill "$listener_pid" >/dev/null 2>&1 || true
  wait "$listener_pid" >/dev/null 2>&1 || true
  tail -40 "$listener_log" >>"$log" 2>/dev/null || true
  die "Timed out waiting for real Gerrit stream-events patchset-created event"
}

cmd_validate_integration() {
  local log evidence
  load_inputs
  require_docker_mode
  ensure_dirs
  ensure_container_integration_dirs
  log="$(bounded_log_path validate-integration)"
  [ -s "$(integration_host_state_dir)/keys/jenkins-gerrit.pub" ] || die "Missing Jenkins-to-Gerrit public key; run configure-gerrit-ssh with --yes first"
  [ -s "$(integration_host_state_dir)/keys/jenkins-agent.pub" ] || die "Missing Jenkins-to-agent public key; run configure-agent-ssh with --yes first"
  docker_exec_sh "$(jenkins_container)" "test -s '$(integration_container_state_dir)/keys/jenkins-gerrit' && test -s '$(integration_container_state_dir)/keys/jenkins-agent'" >/dev/null ||
    die "Missing Jenkins-controller private keys; rerun configure-gerrit-ssh and configure-agent-ssh with --yes"
  [ -s "$(status_file trigger)" ] || die "Missing trigger configuration; run configure-trigger with --yes first"
  ssh_from_controller_to_gerrit "gerrit version" >>"$log" 2>&1
  prove_stream_events "$log"
  docker_exec_sh "$(jenkins_container)" "ssh -i $(integration_container_state_dir)/keys/jenkins-agent -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p '$JENKINS_AGENT_SSH_PORT' '$JENKINS_AGENT_ACCOUNT@$JENKINS_AGENT_HOST' 'printf agent-ssh-ok'" >>"$log" 2>&1
  validate_agent_online "$log"
  schedule_smoke_build "$log"
  write_evidence jenkins-to-gerrit-ssh pass "Real SSH command to Gerrit succeeded as Jenkins integration account" "$log" "account=$JENKINS_GERRIT_INTEGRATION_ACCOUNT" >/dev/null
  write_evidence stream-events pass "Gerrit stream-events SSH command accepted for Jenkins integration account" "$log" "account=$JENKINS_GERRIT_INTEGRATION_ACCOUNT" >/dev/null
  write_evidence agent-connection pass "Jenkins controller SSH credential connected to Jenkins agent and Jenkins node came online" "$log" "node=$JENKINS_AGENT_LABEL" >/dev/null
  evidence="$(write_evidence scheduling pass "Jenkins scheduled a real smoke build on the configured agent label" "$log" "job=$JENKINS_VERIFICATION_JOB label=$JENKINS_AGENT_LABEL")"
  printf 'status=pass command=validate-integration proof=real jenkins_to_gerrit_ssh=pass stream_events=pass agent_connection=pass scheduling=pass evidence=%s log=%s\n' "$evidence" "$log"
}

create_gerrit_change() {
  local log json_file result_file project_file
  log="${1:?log required}"
  json_file="/tmp/step11-create-change.json"
  project_file="/tmp/step11-create-project.json"
  result_file="$(integration_host_state_dir)/status/change.json"
  cat >"$(integration_host_state_dir)/status/create-project.json" <<EOF
{
  "description": "Docker Step 11 disposable verification project",
  "submit_type": "MERGE_IF_NECESSARY",
  "create_empty_commit": true
}
EOF
  cat >"$(integration_host_state_dir)/status/create-change.json" <<EOF
{
  "project": "$GERRIT_VERIFICATION_PROJECT",
  "branch": "master",
  "subject": "Docker Step 11 verification change"
}
EOF
  docker cp "$(integration_host_state_dir)/status/create-project.json" "$(gerrit_container):$project_file" >/dev/null
  docker cp "$(integration_host_state_dir)/status/create-change.json" "$(gerrit_container):$json_file" >/dev/null
  if ! gerrit_curl "$INTEGRATION_GERRIT_ADMIN_ACCOUNT" "$INTEGRATION_GERRIT_ADMIN_PASSWORD" PUT "/projects/$GERRIT_VERIFICATION_PROJECT" "$project_file" >>"$log" 2>&1; then
    gerrit_curl "$INTEGRATION_GERRIT_ADMIN_ACCOUNT" "$INTEGRATION_GERRIT_ADMIN_PASSWORD" GET "/projects/$GERRIT_VERIFICATION_PROJECT" >>"$log" 2>&1 ||
      die "Gerrit REST could not create or find disposable project $GERRIT_VERIFICATION_PROJECT"
  fi
  printf 'project_create=rest-or-existing project=%s\n' "$GERRIT_VERIFICATION_PROJECT" >>"$log"
  gerrit_curl "$INTEGRATION_TEST_ACCOUNT" "$INTEGRATION_TEST_PASSWORD" GET "/accounts/self" >/dev/null
  gerrit_curl "$INTEGRATION_TEST_ACCOUNT" "$INTEGRATION_TEST_PASSWORD" POST "/changes/" "$json_file" >"$result_file"
  python3 - "$result_file" <<'PY'
import json, pathlib, sys
text = pathlib.Path(sys.argv[1]).read_text()
if text.startswith(")]}'"):
    text = text.split("\n", 1)[1]
data = json.loads(text)
print(str(data["_number"]) + " 1 " + data["id"])
PY
}

run_verification_build() {
  local log change patchset groovy
  log="${1:?log required}"
  change="${2:?change required}"
  patchset="${3:?patchset required}"
  groovy="$(integration_host_state_dir)/scripts/wait-triggered-verification.groovy"
  cat >"$groovy" <<EOF
import jenkins.model.Jenkins
def job = Jenkins.instance.getItem('$JENKINS_VERIFICATION_JOB')
assert job != null
def build = null
long deadline = System.currentTimeMillis() + 120000
while (System.currentTimeMillis() < deadline) {
  for (def candidate = job.getLastBuild(); candidate != null; candidate = candidate.getPreviousBuild()) {
    def env = candidate.getEnvironment(null)
    if (env.get('GERRIT_CHANGE_NUMBER') == '$change' && env.get('GERRIT_PATCHSET_NUMBER') == '$patchset') {
      build = candidate
      break
    }
  }
  if (build != null && !build.isBuilding()) { break }
  Thread.sleep(2000)
}
if (build == null) { throw new RuntimeException('no Gerrit-triggered build observed for change $change,$patchset') }
if (build.isBuilding()) { throw new RuntimeException('Gerrit-triggered build did not finish before timeout') }
if (build.result.toString() != 'SUCCESS') { throw new RuntimeException('verification build result=' + build.result) }
if (build.builtOnStr != '$JENKINS_AGENT_LABEL') { throw new RuntimeException('verification build node=' + build.builtOnStr) }
def causes = build.getCauses().collect { it.class.name }.join(',')
if (!causes.contains('gerrit')) { throw new RuntimeException('build was not caused by Gerrit Trigger: ' + causes) }
println('job_execution=pass build=' + build.number + ' node=' + build.builtOnStr + ' causes=' + causes)
EOF
  jenkins_script "$groovy" "$log"
}

post_simulation_verified_vote() {
  local log change patchset review_post_json container_json
  log="${1:?log required}"
  change="${2:?change required}"
  patchset="${3:?patchset required}"
  review_post_json="$(integration_host_state_dir)/status/simulation-verified-vote.json"
  container_json="/tmp/step11-simulation-verified-vote.json"
  cat >"$review_post_json" <<EOF
{
  "message": "Docker Step 11 simulation-only direct REST verification passed on Jenkins agent $JENKINS_AGENT_LABEL",
  "labels": {
    "Verified": 1
  },
  "tag": "autogenerated:step11-simulation-direct-rest"
}
EOF
  docker cp "$review_post_json" "$(gerrit_container):$container_json" >>"$log" 2>&1
  gerrit_curl "$JENKINS_GERRIT_INTEGRATION_ACCOUNT" "$JENKINS_GERRIT_INTEGRATION_PASSWORD" \
    POST "/changes/$change/revisions/$patchset/review" "$container_json" >>"$log" 2>&1
  printf 'review_apply=simulation-only-direct-rest change=%s patchset=%s label=Verified value=+1 account=%s\n' \
    "$change" "$patchset" "$JENKINS_GERRIT_INTEGRATION_ACCOUNT" >>"$log"
}

cmd_verify_trigger() {
  local log change patchset change_id review_json vote_result evidence
  load_inputs
  require_docker_mode
  ensure_dirs
  log="$(bounded_log_path verify-trigger)"
  cmd_validate_integration >>"$log" 2>&1
  read -r change patchset change_id <<EOF
$(create_gerrit_change "$log")
EOF
  printf 'created_change=%s patchset=%s change_id=%s\n' "$change" "$patchset" "$change_id" >>"$log"
  run_verification_build "$log" "$change" "$patchset"
  post_simulation_verified_vote "$log" "$change" "$patchset"
  review_json="$(integration_host_state_dir)/status/review.json"
  gerrit_curl "$INTEGRATION_GERRIT_ADMIN_ACCOUNT" "$INTEGRATION_GERRIT_ADMIN_PASSWORD" GET "/changes/$change/revisions/current/review" >"$review_json"
  vote_result="$(python3 - "$review_json" <<'PY'
import json, pathlib, sys
text = pathlib.Path(sys.argv[1]).read_text()
if text.startswith(")]}'"):
    text = text.split("\n", 1)[1]
data = json.loads(text)
labels = data.get("labels", {})
verified = labels.get("Verified", {})
print(verified.get("approved", {}).get("_account_id", "missing"))
PY
)"
  [ "$vote_result" != "missing" ] || die "Verified +1 vote was not present on Gerrit change"
  write_evidence job-execution pass "Disposable Jenkins verification job executed successfully on the configured agent" "$log" "change=$change job=$JENKINS_VERIFICATION_JOB" >/dev/null
  evidence="$(write_evidence verified-vote pass "Gerrit review state contains a real Verified +1 posted by the Jenkins integration account through simulation-only direct Gerrit REST" "$log" "change=$change patchset=$patchset review_apply=simulation-only-direct-rest")"
  printf 'status=pass command=verify-trigger proof=real change=%s patchset=%s job_execution=pass verified_vote=pass review_apply=simulation-only-direct-rest evidence=%s log=%s\n' "$change" "$patchset" "$evidence" "$log"
}

cmd_collect_evidence() {
  local log evidence
  load_inputs
  require_docker_mode
  ensure_dirs
  log="$(bounded_log_path collect-evidence)"
  find "$(integration_evidence_dir)" -maxdepth 1 -type f -name 'integration-*.json' -print | sort >"$log"
  [ -s "$log" ] || die "No integration evidence records found"
  evidence="$(write_evidence collect-evidence pass "Collected sanitized integration checkpoint records" "$log" "records=$(wc -l <"$log")")"
  printf 'status=pass command=collect-evidence evidence=%s log=%s\n' "$evidence" "$log"
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --gerrit-env)
        [ "$#" -ge 2 ] || die_usage "--gerrit-env requires a value"
        gerrit_env_file="$2"
        shift 2
        ;;
      --gerrit-env=*)
        gerrit_env_file="${1#--gerrit-env=}"
        shift
        ;;
      --jenkins-controller-env)
        [ "$#" -ge 2 ] || die_usage "--jenkins-controller-env requires a value"
        jenkins_controller_env_file="$2"
        shift 2
        ;;
      --jenkins-controller-env=*)
        jenkins_controller_env_file="${1#--jenkins-controller-env=}"
        shift
        ;;
      --jenkins-agent-env)
        [ "$#" -ge 2 ] || die_usage "--jenkins-agent-env requires a value"
        jenkins_agent_env_file="$2"
        shift 2
        ;;
      --jenkins-agent-env=*)
        jenkins_agent_env_file="${1#--jenkins-agent-env=}"
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
      configure-gerrit-ssh|configure-agent-ssh|configure-trigger|validate-integration|verify-trigger|collect-evidence)
        command_name="$1"
        shift
        [ "$#" -eq 0 ] || die_usage "Unexpected arguments after command: $*"
        return 0
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
  parse_args "$@"
  case "$command_name" in
    configure-gerrit-ssh) cmd_configure_gerrit_ssh ;;
    configure-agent-ssh) cmd_configure_agent_ssh ;;
    configure-trigger) cmd_configure_trigger ;;
    validate-integration) cmd_validate_integration ;;
    verify-trigger) cmd_verify_trigger ;;
    collect-evidence) cmd_collect_evidence ;;
    *) die_usage "Unknown command: $command_name" ;;
  esac
}

main "$@"
