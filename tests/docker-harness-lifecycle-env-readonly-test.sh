#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
fake_bin="$tmp_dir/bin"
calls="$tmp_dir/docker-calls.log"
run_id="env-readonly-$$"
run_dir="$repo_root/generated/simulation/docker/$run_id"
cleanup() {
  rc=$?
  if [ "$rc" -ne 0 ]; then
    if [ -f "$calls" ]; then
      printf '%s\n' "--- docker calls ---" >&2
      sed -n '1,220p' "$calls" >&2
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
          *"prepare-artifacts"*)
            exit 7
            ;;
          *"/home/ci-operator/loopforge/scripts/"*)
            exit 7
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
)

env "${common_env[@]}" \
  "$repo_root/simulation/docker/simulate.sh" init-run --env "$tmp_dir/harness.env" \
  >/dev/null

snapshot="$tmp_dir/env-files.before"
find "$run_dir/host/source-inputs" -type f -name '*.env' -print0 |
  sort -z |
  xargs -0 sha256sum >"$snapshot"

for command in \
  "prepare-artifacts --role gerrit" \
  "prepare-artifacts --role jenkins-controller" \
  "prepare-artifacts --role jenkins-agent" \
  "configure-role --role gerrit" \
  "configure-role --role jenkins-controller" \
  "configure-role --role jenkins-agent" \
  "validate-role --role gerrit" \
  "validate-role --role jenkins-controller" \
  "validate-role --role jenkins-agent"
do
  set +e
  # shellcheck disable=SC2086
  env "${common_env[@]}" "$repo_root/simulation/docker/simulate.sh" $command \
    >"$tmp_dir/${command// /-}.out" 2>&1
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || {
    printf 'Expected lifecycle command to fail in fake Docker mode: %s\n' "$command" >&2
    exit 1
  }
done

after="$tmp_dir/env-files.after"
find "$run_dir/host/source-inputs" -type f -name '*.env' -print0 |
  sort -z |
  xargs -0 sha256sum >"$after"

if ! cmp -s "$snapshot" "$after"; then
  printf 'Lifecycle command modified source input snapshots\n' >&2
  diff -u "$snapshot" "$after" >&2 || true
  exit 1
fi
[ ! -e "$run_dir/host/runtime-inputs" ]
