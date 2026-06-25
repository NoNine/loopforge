#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
fake_bin="$tmp_dir/bin"
calls="$tmp_dir/docker-calls.log"
run_id="role-order-$$"
run_dir="$repo_root/generated/simulation/docker/$run_id"
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
  rm -rf "$tmp_dir" "$run_dir"
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
        if [ "${1:-}" = "-u" ]; then
          shift 2
        fi
        service="${1:-}"
        shift
        case "$*" in
          *"sha256sum -c checksums.sha256"*)
            exit 0
            ;;
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
  inspect\ -f\ *State.Running*)
    printf 'true\n'
    ;;
  inspect*)
    ;;
esac
SH
chmod +x "$fake_bin/docker"

mkdir -p \
  "$run_dir/state/rendered" \
  "$run_dir/evidence" \
  "$run_dir/logs"
cp "$repo_root/simulation/docker/examples/docker.env.example" "$tmp_dir/harness.env"
cp "$repo_root/examples/gerrit.env.example" "$tmp_dir/gerrit.env"
cp "$repo_root/examples/jenkins-controller.env.example" "$tmp_dir/jenkins-controller.env"
cp "$repo_root/examples/jenkins-agent.env.example" "$tmp_dir/jenkins-agent.env"
read -r gerrit_host_port jenkins_host_port <<EOF
$(python3 - <<'PY'
import socket

ports = []
for _ in range(2):
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.bind(("127.0.0.1", 0))
    ports.append(sock.getsockname()[1])
    sock.close()
print(*ports)
PY
)
EOF
cat >>"$tmp_dir/harness.env" <<EOF
HARNESS_RUN_ID=$run_id
HARNESS_PROJECT_NAME=$run_id
HARNESS_GERRIT_ENV_FILE=$(printf '%q' "$tmp_dir/gerrit.env")
HARNESS_JENKINS_CONTROLLER_ENV_FILE=$(printf '%q' "$tmp_dir/jenkins-controller.env")
HARNESS_JENKINS_AGENT_ENV_FILE=$(printf '%q' "$tmp_dir/jenkins-agent.env")
HARNESS_GERRIT_HTTP_HOST_PORT=$gerrit_host_port
HARNESS_JENKINS_HTTP_HOST_PORT=$jenkins_host_port
EOF
printf 'gerrit log\n' >"$run_dir/logs/gerrit.log"
printf 'controller log\n' >"$run_dir/logs/controller.log"
printf 'agent log\n' >"$run_dir/logs/agent.log"
cat >"$run_dir/evidence/gerrit-readiness-test.json" <<'EOF'
{"bounded_log_references":"/var/log/loopforge/gerrit.log","service_log_reference":"/srv/gerrit/logs/gerrit.log"}
EOF
cat >"$run_dir/evidence/jenkins-controller-readiness-test.json" <<'EOF'
{"bounded_log_references":"/var/log/loopforge/controller.log","service_log_reference":"/var/lib/jenkins/logs/jenkins-controller.log","runtime_status_reference":"/var/lib/jenkins/state/runtime.status"}
EOF
cat >"$run_dir/evidence/jenkins-agent-readiness-test.json" <<'EOF'
{"bounded_log_references":"/var/log/loopforge/agent.log","service_log_reference":"/var/lib/jenkins-agent/logs/agent-service.log"}
EOF

common_env=(
  PATH="$fake_bin:$PATH"
  DOCKER_CALLS_LOG="$calls"
  HARNESS_TEST_STUB_ROLE_COMMANDS="$tmp_dir/role-calls.log"
  HARNESS_ENV_FILE="$tmp_dir/harness.env"
)

env "${common_env[@]}" \
  "$repo_root/simulation/docker/simulate.sh" init-run --env "$tmp_dir/harness.env" >/dev/null

env "${common_env[@]}" \
  "$repo_root/simulation/docker/simulate.sh" --env "$tmp_dir/harness.env" configure-role --role gerrit >/dev/null
env "${common_env[@]}" \
  "$repo_root/simulation/docker/simulate.sh" --env "$tmp_dir/harness.env" validate-role --role gerrit >/dev/null
env "${common_env[@]}" \
  "$repo_root/simulation/docker/simulate.sh" --env "$tmp_dir/harness.env" configure-role --role jenkins-controller >/dev/null
env "${common_env[@]}" \
  "$repo_root/simulation/docker/simulate.sh" --env "$tmp_dir/harness.env" validate-role --role jenkins-controller >/dev/null
env "${common_env[@]}" \
  "$repo_root/simulation/docker/simulate.sh" --env "$tmp_dir/harness.env" configure-role --role jenkins-agent >/dev/null
env "${common_env[@]}" \
  "$repo_root/simulation/docker/simulate.sh" --env "$tmp_dir/harness.env" validate-role --role jenkins-agent >/dev/null

if [ -f "$tmp_dir/role-calls.log" ] && grep -Eq '^.* --role$|^.* --role ' "$tmp_dir/role-calls.log"; then
  printf 'role dispatch must pass bare role names to internal command functions\n' >&2
  sed -n '1,120p' "$tmp_dir/role-calls.log" >&2
  exit 1
fi

gerrit_host_evidence="$(find "$run_dir/evidence" -maxdepth 1 -type f -name 'gerrit-readiness-*.json.host.json' -print | sort | tail -1)"
controller_host_evidence="$(find "$run_dir/evidence" -maxdepth 1 -type f -name 'jenkins-controller-readiness-*.json.host.json' -print | sort | tail -1)"
agent_host_evidence="$(find "$run_dir/evidence" -maxdepth 1 -type f -name 'jenkins-agent-readiness-*.json.host.json' -print | sort | tail -1)"
[ -n "$gerrit_host_evidence" ] || {
  printf 'gerrit normalized host evidence was not written\n' >&2
  exit 1
}
[ -n "$controller_host_evidence" ] || {
  printf 'jenkins-controller normalized host evidence was not written\n' >&2
  exit 1
}
[ -n "$agent_host_evidence" ] || {
  printf 'jenkins-agent normalized host evidence was not written\n' >&2
  exit 1
}
grep -Fq '"service_log_reference": "/srv/gerrit/logs/gerrit.log"' "$gerrit_host_evidence" || {
  printf 'gerrit service log metadata reference was not preserved\n' >&2
  exit 1
}
grep -Fq '"service_log_reference": "/var/lib/jenkins/logs/jenkins-controller.log"' "$controller_host_evidence" || {
  printf 'jenkins-controller service log metadata reference was not preserved\n' >&2
  exit 1
}
grep -Fq '"runtime_status_reference": "/var/lib/jenkins/state/runtime.status"' "$controller_host_evidence" || {
  printf 'jenkins-controller runtime status metadata reference was not preserved\n' >&2
  exit 1
}
if grep -Fq 'product-home/jenkins-controller/state/runtime.status' "$controller_host_evidence"; then
  printf 'jenkins-controller runtime status must not be normalized as a bounded log snapshot\n' >&2
  exit 1
fi
grep -Fq '"service_log_reference": "/var/lib/jenkins-agent/logs/agent-service.log"' "$agent_host_evidence" || {
  printf 'jenkins-agent service log metadata reference was not preserved\n' >&2
  exit 1
}
if grep -Fq "$run_dir/product-homes" "$gerrit_host_evidence" "$controller_host_evidence" "$agent_host_evidence"; then
  printf 'product-home paths must not be normalized into bounded log references\n' >&2
  exit 1
fi

gerrit_chown_line="$(grep -n 'gerrit-target sh -c .*chown -R gerrit:gerrit /srv/gerrit' "$calls" | cut -d: -f1 | head -1)"
controller_chown_line="$(grep -n 'jenkins-controller-target sh -c .*chown -R jenkins:jenkins /var/lib/jenkins' "$calls" | cut -d: -f1 | head -1)"
agent_chown_line="$(grep -n 'jenkins-agent-target sh -c .*chown -R jenkins-agent:jenkins-agent /var/lib/jenkins-agent' "$calls" | cut -d: -f1 | head -1)"
gerrit_env_copy_line="$(grep -n 'helper-envs/gerrit-target/gerrit.env container-id:/tmp/loopforge-docker-cp-' "$calls" | cut -d: -f1 | head -1)"
controller_env_copy_line="$(grep -n 'helper-envs/jenkins-controller-target/jenkins-controller.env container-id:/tmp/loopforge-docker-cp-' "$calls" | cut -d: -f1 | head -1)"
agent_env_copy_line="$(grep -n 'helper-envs/jenkins-agent-target/jenkins-agent.env container-id:/tmp/loopforge-docker-cp-' "$calls" | cut -d: -f1 | head -1)"
gerrit_install_line="$(grep -n '/workspace/scripts/gerrit-setup.sh --env /var/lib/loopforge/rendered/gerrit.env --yes install' "$calls" | cut -d: -f1 | head -1)"
controller_install_line="$(grep -n '/workspace/scripts/jenkins-controller-setup.sh --env /var/lib/loopforge/rendered/jenkins-controller.env --yes install' "$calls" | cut -d: -f1 | head -1)"
agent_install_line="$(grep -n '/workspace/scripts/jenkins-agent-setup.sh --env /var/lib/loopforge/rendered/jenkins-agent.env --yes install' "$calls" | cut -d: -f1 | head -1)"

if [ -f "$tmp_dir/role-calls.log" ] && grep -Eq '^prepare-artifacts |^stage-artifacts ' "$tmp_dir/role-calls.log"; then
  printf 'role configuration must not rerun prepare-artifacts or stage-artifacts\n' >&2
  sed -n '1,120p' "$tmp_dir/role-calls.log" >&2
  exit 1
fi
for role in gerrit jenkins-controller jenkins-agent; do
  grep -Fq "staged_artifacts_ready role=$role" "$run_dir/logs/configure-role-$role-"*.log || {
    printf 'configure-role did not verify staged artifacts for %s\n' "$role" >&2
    exit 1
  }
done
[ -n "$gerrit_install_line" ] || {
  printf 'gerrit install did not run\n' >&2
  exit 1
}
if [ -z "$gerrit_chown_line" ] || [ "$gerrit_chown_line" -ge "$gerrit_install_line" ]; then
  printf 'gerrit product home ownership was not prepared before install\n' >&2
  exit 1
fi
if [ -z "$gerrit_env_copy_line" ] || [ "$gerrit_env_copy_line" -ge "$gerrit_install_line" ]; then
  printf 'gerrit rendered env was not Docker-copied before install\n' >&2
  exit 1
fi
[ -n "$controller_install_line" ] || {
  printf 'jenkins-controller install did not run\n' >&2
  exit 1
}
if [ -z "$controller_chown_line" ] || [ "$controller_chown_line" -ge "$controller_install_line" ]; then
  printf 'jenkins-controller product home ownership was not prepared before install\n' >&2
  exit 1
fi
if [ -z "$controller_env_copy_line" ] || [ "$controller_env_copy_line" -ge "$controller_install_line" ]; then
  printf 'jenkins-controller rendered env was not Docker-copied before install\n' >&2
  exit 1
fi
[ -n "$agent_install_line" ] || {
  printf 'jenkins-agent install did not run\n' >&2
  exit 1
}
if [ -z "$agent_chown_line" ] || [ "$agent_chown_line" -ge "$agent_install_line" ]; then
  printf 'jenkins-agent product home ownership was not prepared before install\n' >&2
  exit 1
fi
if [ -z "$agent_env_copy_line" ] || [ "$agent_env_copy_line" -ge "$agent_install_line" ]; then
  printf 'jenkins-agent rendered env was not Docker-copied before install\n' >&2
  exit 1
fi
