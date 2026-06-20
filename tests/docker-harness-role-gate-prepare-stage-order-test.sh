#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
fake_bin="$tmp_dir/bin"
calls="$tmp_dir/docker-calls.log"
cleanup() {
  rc=$?
  if [ "$rc" -ne 0 ]; then
    if [ -f "$tmp_dir/role-calls.log" ]; then
      printf '%s\n' '--- role calls ---' >&2
      sed -n '1,120p' "$tmp_dir/role-calls.log" >&2
    fi
    if [ -f "$calls" ]; then
      printf '%s\n' '--- docker calls ---' >&2
      sed -n '1,200p' "$calls" >&2
    fi
  fi
  rm -rf "$tmp_dir"
  exit "$rc"
}
trap cleanup EXIT

mkdir -p "$fake_bin"
cat >"$fake_bin/docker" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$DOCKER_CALLS_LOG"
case "$*" in
  *"compose version --short"*) printf '2.0.0\n' ;;
  *"compose version"*) printf 'Docker Compose version v2.0.0\n' ;;
  compose*)
    if [ "${1:-}" = "compose" ]; then
      shift
    fi
    while [ "$#" -gt 0 ]; do
      case "$1" in
        -f|--file|--project-name|-p)
          shift 2
          ;;
        -*)
          shift
          ;;
        *)
          break
          ;;
      esac
    done
    case "${1:-}" in
      ps)
        printf 'container-id\n'
        ;;
      exec)
        shift
        [ "${1:-}" = "-T" ] && shift
        service="${1:-}"
        shift
        case "$*" in
          *"/etc/os-release"*)
            printf '24.04 noble\n'
            ;;
          "test -x "*)
            exit 0
            ;;
          "env")
            case "$service" in
              bundle-factory) printf 'HARNESS_ENVIRONMENT=bundle-factory\n' ;;
              *) printf 'HARNESS_ENVIRONMENT=%s\n' "$service" ;;
            esac
            ;;
          *"/workspace/scripts/"*)
            exit 0
            ;;
          *)
            exit 0
            ;;
        esac
        ;;
      *)
        exit 0
        ;;
    esac
    ;;
  inspect*)
    printf 'true\n'
    ;;
esac
SH
chmod +x "$fake_bin/docker"

write_manifest() {
  local role dir
  role="${1:?role required}"
  dir="$tmp_dir/staging/$role"
  mkdir -p "$dir"
  cat >"$dir/manifest.txt" <<EOF
harness_manifest_version=1
role=$role
ubuntu_release=24.04
ubuntu_codename=noble
java_version=21
artifact_source=curated-bundle-factory
os_dependency_source=approved-internal-os-repos
public_internet_fallback=simulation-only
bundle_contains_keys=no
EOF
  case "$role" in
    jenkins-controller)
      cat >>"$dir/manifest.txt" <<'EOF'
gerrit_version=not-applicable
jenkins_version=2.555.3
jenkins_plugin_manager_version=2.15.0
EOF
      ;;
    jenkins-agent)
      cat >>"$dir/manifest.txt" <<'EOF'
gerrit_version=not-applicable
jenkins_version=not-applicable
jenkins_plugin_manager_version=not-applicable
EOF
      ;;
  esac
}

write_manifest jenkins-controller
write_manifest jenkins-agent
mkdir -p "$tmp_dir/state/rendered" "$tmp_dir/evidence" "$tmp_dir/logs"
cp "$repo_root/simulation/docker/examples/docker.env.example" "$tmp_dir/harness.env"
cp "$repo_root/examples/gerrit.env.example" "$tmp_dir/gerrit.env"
cp "$repo_root/examples/jenkins-controller.env.example" "$tmp_dir/jenkins-controller.env"
cp "$repo_root/examples/jenkins-agent.env.example" "$tmp_dir/jenkins-agent.env"
cat >>"$tmp_dir/harness.env" <<EOF
HARNESS_GERRIT_ENV_FILE=$(printf '%q' "$tmp_dir/gerrit.env")
HARNESS_JENKINS_CONTROLLER_ENV_FILE=$(printf '%q' "$tmp_dir/jenkins-controller.env")
HARNESS_JENKINS_AGENT_ENV_FILE=$(printf '%q' "$tmp_dir/jenkins-agent.env")
EOF
printf 'controller log\n' >"$tmp_dir/logs/controller.log"
printf 'agent log\n' >"$tmp_dir/logs/agent.log"
cat >"$tmp_dir/evidence/jenkins-controller-readiness-test.json" <<'EOF'
{"bounded_log_references":"/harness/logs/controller.log"}
EOF
cat >"$tmp_dir/evidence/jenkins-agent-readiness-test.json" <<'EOF'
{"bounded_log_references":"/harness/logs/agent.log"}
EOF

common_env=(
  PATH="$fake_bin:$PATH"
  DOCKER_CALLS_LOG="$calls"
  HARNESS_TEST_STUB_ROLE_COMMANDS="$tmp_dir/role-calls.log"
  HARNESS_RUN_ID="role-order-$$"
  HARNESS_PROJECT_NAME="role-order-$$"
  HARNESS_STATE_DIR="$tmp_dir/state"
  HARNESS_STAGING_DIR="$tmp_dir/staging"
  HARNESS_EVIDENCE_DIR="$tmp_dir/evidence"
  HARNESS_LOG_DIR="$tmp_dir/logs"
)

env "${common_env[@]}" \
  "$repo_root/simulation/docker/docker-harness.sh" render-config --env "$tmp_dir/harness.env" >/dev/null

env "${common_env[@]}" \
  "$repo_root/simulation/docker/docker-harness.sh" run-role-gate --role jenkins-controller >/dev/null
env "${common_env[@]}" \
  "$repo_root/simulation/docker/docker-harness.sh" run-role-gate --role jenkins-agent >/dev/null

controller_prepare_line="$(grep -n '^prepare-artifacts jenkins-controller$' "$tmp_dir/role-calls.log" | cut -d: -f1)"
controller_stage_line="$(grep -n '^stage-artifacts jenkins-controller$' "$tmp_dir/role-calls.log" | cut -d: -f1)"
agent_prepare_line="$(grep -n '^prepare-artifacts jenkins-agent$' "$tmp_dir/role-calls.log" | cut -d: -f1)"
agent_stage_line="$(grep -n '^stage-artifacts jenkins-agent$' "$tmp_dir/role-calls.log" | cut -d: -f1)"
controller_install_line="$(grep -n '/workspace/scripts/jenkins-controller-setup.sh --env /harness/state/rendered/jenkins-controller.env --yes install' "$calls" | cut -d: -f1 | head -1)"
agent_install_line="$(grep -n '/workspace/scripts/jenkins-agent-setup.sh --env /harness/state/rendered/jenkins-agent.env --yes install' "$calls" | cut -d: -f1 | head -1)"

[ "$controller_prepare_line" -lt "$controller_install_line" ] || {
  printf 'jenkins-controller prepare did not run before install\n' >&2
  exit 1
}
[ "$controller_stage_line" -lt "$controller_install_line" ] || {
  printf 'jenkins-controller stage did not run before install\n' >&2
  exit 1
}
[ "$agent_prepare_line" -lt "$agent_install_line" ] || {
  printf 'jenkins-agent prepare did not run before install\n' >&2
  exit 1
}
[ "$agent_stage_line" -lt "$agent_install_line" ] || {
  printf 'jenkins-agent stage did not run before install\n' >&2
  exit 1
}
