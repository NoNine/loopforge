#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
fake_bin="$tmp_dir/bin"
calls="$tmp_dir/docker-calls.log"
run_id="role-precondition-$$"
run_dir="$repo_root/generated/simulation/docker/$run_id"
cleanup() {
  rc=$?
  if [ "$rc" -ne 0 ]; then
    if [ -f "$calls" ]; then
      printf '%s\n' '--- docker calls ---' >&2
      sed -n '1,200p' "$calls" >&2
    fi
    if [ -d "$run_dir/target/logs" ]; then
      printf '%s\n' '--- configure-role logs ---' >&2
      find "$run_dir/target/logs" -maxdepth 1 -type f -name 'configure-role-gerrit-*.log' -print -exec sed -n '1,120p' {} \; >&2
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
      cp)
        exit 0
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
          *"sha256sum -c checksums.sha256"*)
            printf 'missing_staged_artifacts manifest=/var/lib/loopforge/staging/gerrit/payload/manifest.txt\n'
            exit 1
            ;;
          *"/workspace/scripts/"*)
            printf 'role helper must not run when staged artifacts are missing\n' >&2
            exit 99
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

mkdir -p "$run_dir/host/rendered" "$run_dir/target/logs" "$run_dir/target/evidence"
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

env \
  PATH="$fake_bin:$PATH" \
  DOCKER_CALLS_LOG="$calls" \
  "$repo_root/simulation/docker/simulate.sh" init-run --env "$tmp_dir/harness.env" >/dev/null

set +e
env \
  PATH="$fake_bin:$PATH" \
  DOCKER_CALLS_LOG="$calls" \
  HARNESS_ENV_FILE="$tmp_dir/harness.env" \
  "$repo_root/simulation/docker/simulate.sh" --env "$tmp_dir/harness.env" configure-role --role gerrit \
  >"$tmp_dir/configure-role.out" 2>&1
rc=$?
set -e

[ "$rc" -ne 0 ] || {
  printf 'configure-role unexpectedly succeeded without staged artifacts\n' >&2
  exit 1
}
grep -Fq 'configure-role[gerrit]: failed' "$tmp_dir/configure-role.out"
grep -Fq 'run stage-artifacts --role gerrit first' "$tmp_dir/configure-role.out"
grep -Fq 'missing_staged_artifacts manifest=' "$run_dir/target/logs"/configure-role-gerrit-*.log
grep -Fq 'Staged artifacts are missing or invalid' "$run_dir/target/evidence"/configure-role-gerrit-*.json
if grep -Eq '/workspace/scripts/gerrit-setup\.sh .* (--yes )?(install|configure|validate|collect-evidence)' "$calls"; then
  printf 'configure-role must not call the role helper when staged artifacts are missing\n' >&2
  exit 1
fi
