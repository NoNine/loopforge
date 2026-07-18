#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
fake_bin="$tmp_dir/bin"
calls="$tmp_dir/docker-calls.log"
run_id="role-order-$$"
run_dir="$repo_root/generated/simulation/docker/$run_id"
set_dir="$repo_root/generated/simulation/docker/sets/$run_id"
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
    if [ -d "$run_dir/host/logs/harness" ]; then
      printf '%s\n' '--- harness logs ---' >&2
      find "$run_dir/host/logs/harness" -maxdepth 1 -type f -print \
        -exec tail -30 {} \; >&2
    fi
  fi
  rm -rf "$tmp_dir" "$run_dir" "$repo_root/generated/simulation/docker/sets/$run_id"
  rm -f "$repo_root/generated/simulation/docker/locks/$run_id.lock"
  exit "$rc"
}
trap cleanup EXIT

mkdir -p "$fake_bin"
cat >"$fake_bin/docker" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$DOCKER_CALLS_LOG"
. "$DOCKER_SET_FAKE_LIB"
if fake_docker_set_handle "$@"; then exit 0; else rc=$?; [ "$rc" -eq 125 ] || exit "$rc"; fi
case "$*" in
  *"compose version --short"*) printf '2.0.0\n' ;;
  *"compose version"*) printf 'Docker Compose version v2.0.0\n' ;;
  "ps -a --format {{.Names}}")
    if [ -f "$DOCKER_CONTAINERS_READY" ]; then
      printf '%s-bundle-factory\n%s-ldap\n%s-gerrit-target\n%s-jenkins-controller-target\n%s-jenkins-agent-target\n' \
        "$HARNESS_PROJECT_NAME" "$HARNESS_PROJECT_NAME" "$HARNESS_PROJECT_NAME" "$HARNESS_PROJECT_NAME" "$HARNESS_PROJECT_NAME"
    fi
    ;;
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
        while [ "$#" -gt 0 ]; do
          case "$1" in
            -T)
              shift
              ;;
            -u|-e)
              shift 2
              ;;
            *)
              break
              ;;
          esac
        done
        service="${1:-}"
        shift
        case "$*" in
          *"sha256sum -c checksums.sha256"*)
            exit 0
            ;;
          *"printf \"release=%s"*)
            printf 'release=24.04 codename=noble pretty=Ubuntu 24.04\n'
            ;;
          *"/etc/os-release"*)
            printf '24.04 noble\n'
            ;;
          *"find /var/lib/loopforge/evidence"*)
            case "$service" in
              gerrit-target) printf '/var/lib/loopforge/evidence/gerrit-readiness-test.json\n' ;;
              jenkins-controller-target) printf '/var/lib/loopforge/evidence/jenkins-controller-readiness-test.json\n' ;;
              jenkins-agent-target) printf '/var/lib/loopforge/evidence/jenkins-agent-readiness-test.json\n' ;;
            esac
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
          *"/home/ci-operator/loopforge/scripts/"*)
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
  cp\ *:/*)
    case "$2" in *:/*) ;; *) exit 0 ;; esac
    src="${2#*:}"
    dest="${3:-}"
    mkdir -p "$(dirname "$dest")"
    case "$src" in
      /var/lib/loopforge/evidence/gerrit-readiness-test.json)
        printf '%s\n' '{"bounded_log_references":"/var/log/loopforge/gerrit.log","service_log_reference":"/srv/gerrit/logs/gerrit.log"}' >"$dest"
        ;;
      /var/lib/loopforge/evidence/jenkins-controller-readiness-test.json)
        printf '%s\n' '{"bounded_log_references":"/var/log/loopforge/controller.log","service_log_reference":"/var/lib/jenkins/logs/jenkins-controller.log","runtime_status_reference":"/var/lib/jenkins/target/helper-state/runtime.status"}' >"$dest"
        ;;
      /var/lib/loopforge/evidence/jenkins-agent-readiness-test.json)
        printf '%s\n' '{"bounded_log_references":"/var/log/loopforge/agent.log","service_log_reference":"/var/lib/jenkins-agent/logs/agent-service.log"}' >"$dest"
        ;;
      /var/log/loopforge/gerrit.log)
        printf 'gerrit log\n' >"$dest"
        ;;
      /var/log/loopforge/controller.log)
        printf 'controller log\n' >"$dest"
        ;;
      /var/log/loopforge/agent.log)
        printf 'agent log\n' >"$dest"
        ;;
      *)
        printf 'unexpected docker cp source: %s\n' "$src" >&2
        exit 1
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
export DOCKER_SET_FAKE_LIB="$repo_root/tests/fixtures/docker-set-state.sh"
export DOCKER_SET_FAKE_STATE_DIR="$tmp_dir/docker-state"
export REPO_ROOT="$repo_root"
cat >"$fake_bin/ssh-keyscan" <<'SH'
#!/usr/bin/env bash
printf '[127.0.0.1]:%s ssh-ed25519 test-key\n' "${4:-22}"
SH
chmod +x "$fake_bin/ssh-keyscan"

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
HARNESS_SET_ID=$run_id
HARNESS_GERRIT_ENV_FILE=$(printf '%q' "$tmp_dir/gerrit.env")
HARNESS_JENKINS_CONTROLLER_ENV_FILE=$(printf '%q' "$tmp_dir/jenkins-controller.env")
HARNESS_JENKINS_AGENT_ENV_FILE=$(printf '%q' "$tmp_dir/jenkins-agent.env")
HARNESS_GERRIT_HTTP_HOST_PORT=$gerrit_host_port
HARNESS_JENKINS_HTTP_HOST_PORT=$jenkins_host_port
EOF
common_env=(
  PATH="$fake_bin:$PATH"
  DOCKER_CALLS_LOG="$calls"
  DOCKER_CONTAINERS_READY="$tmp_dir/containers-ready"
  HARNESS_ENV_FILE="$tmp_dir/harness.env"
)

env "${common_env[@]}" \
  "$repo_root/simulation/docker/simulate.sh" init-run --env "$tmp_dir/harness.env" >/dev/null
env "${common_env[@]}" \
  "$repo_root/simulation/docker/simulate.sh" create --env "$tmp_dir/harness.env" >/dev/null
env "${common_env[@]}" \
  "$repo_root/simulation/docker/simulate.sh" start --env "$tmp_dir/harness.env" >/dev/null

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

gerrit_host_evidence="$(find "$run_dir/host/evidence/harness" -maxdepth 1 -type f -name 'gerrit-readiness-*.host.json' -print | sort | tail -1)"
controller_host_evidence="$(find "$run_dir/host/evidence/harness" -maxdepth 1 -type f -name 'jenkins-controller-readiness-*.host.json' -print | sort | tail -1)"
agent_host_evidence="$(find "$run_dir/host/evidence/harness" -maxdepth 1 -type f -name 'jenkins-agent-readiness-*.host.json' -print | sort | tail -1)"
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
grep -Fq '"runtime_status_reference": "/var/lib/jenkins/target/helper-state/runtime.status"' "$controller_host_evidence" || {
  printf 'jenkins-controller runtime status metadata reference was not preserved\n' >&2
  exit 1
}
if grep -Fq 'product-home/jenkins-controller/target/helper-state/runtime.status' "$controller_host_evidence"; then
  printf 'jenkins-controller runtime status must not be normalized as a bounded log snapshot\n' >&2
  exit 1
fi
grep -Fq '"service_log_reference": "/var/lib/jenkins-agent/logs/agent-service.log"' "$agent_host_evidence" || {
  printf 'jenkins-agent service log metadata reference was not preserved\n' >&2
  exit 1
}
if grep -Fq "$set_dir/runtime/product-homes" "$gerrit_host_evidence" "$controller_host_evidence" "$agent_host_evidence"; then
  printf 'product-home paths must not be normalized into bounded log references\n' >&2
  exit 1
fi

gerrit_env_copy_line="$(grep -n 'runtime-inputs/gerrit.env cid-3:/tmp/loopforge-input-cp-' "$calls" | cut -d: -f1 | head -1)"
controller_env_copy_line="$(grep -n 'runtime-inputs/jenkins-controller.env cid-4:/tmp/loopforge-input-cp-' "$calls" | cut -d: -f1 | head -1)"
agent_env_copy_line="$(grep -n 'runtime-inputs/jenkins-agent.env cid-5:/tmp/loopforge-input-cp-' "$calls" | cut -d: -f1 | head -1)"
gerrit_install_line="$(grep -n '/home/ci-operator/loopforge/scripts/gerrit-setup.sh --env /home/ci-operator/loopforge-inputs/gerrit.env --yes install' "$calls" | cut -d: -f1 | head -1)"
controller_install_line="$(grep -n '/home/ci-operator/loopforge/scripts/jenkins-controller-setup.sh --env /home/ci-operator/loopforge-inputs/jenkins-controller.env --yes install' "$calls" | cut -d: -f1 | head -1)"
agent_install_line="$(grep -n '/home/ci-operator/loopforge/scripts/jenkins-agent-setup.sh --env /home/ci-operator/loopforge-inputs/jenkins-agent.env --yes install' "$calls" | cut -d: -f1 | head -1)"

if [ -f "$tmp_dir/role-calls.log" ] && grep -Eq '^prepare-artifacts |^stage-artifacts ' "$tmp_dir/role-calls.log"; then
  printf 'role configuration must not rerun prepare-artifacts or stage-artifacts\n' >&2
  sed -n '1,120p' "$tmp_dir/role-calls.log" >&2
  exit 1
fi
for role in gerrit jenkins-controller jenkins-agent; do
  grep -Fq "staged_artifacts_ready role=$role" "$run_dir/host/logs/harness/configure-role-$role-"*.log || {
    printf 'configure-role did not verify staged artifacts for %s\n' "$role" >&2
    exit 1
  }
done
[ -n "$gerrit_install_line" ] || {
  printf 'gerrit install did not run\n' >&2
  exit 1
}
if [ -z "$gerrit_env_copy_line" ] || [ "$gerrit_env_copy_line" -ge "$gerrit_install_line" ]; then
  printf 'gerrit operator input env was not Docker-copied before install\n' >&2
  exit 1
fi
[ -n "$controller_install_line" ] || {
  printf 'jenkins-controller install did not run\n' >&2
  exit 1
}
if [ -z "$controller_env_copy_line" ] || [ "$controller_env_copy_line" -ge "$controller_install_line" ]; then
  printf 'jenkins-controller operator input env was not Docker-copied before install\n' >&2
  exit 1
fi
[ -n "$agent_install_line" ] || {
  printf 'jenkins-agent install did not run\n' >&2
  exit 1
}
if [ -z "$agent_env_copy_line" ] || [ "$agent_env_copy_line" -ge "$agent_install_line" ]; then
  printf 'jenkins-agent operator input env was not Docker-copied before install\n' >&2
  exit 1
fi
