#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
fake_bin="$tmp_dir/bin"
calls="$tmp_dir/docker-calls.log"
cleanup() {
  rc=$?
  if [ "$rc" -ne 0 ]; then
    if [ -f "$calls" ]; then
      printf '%s\n' "--- docker calls ---" >&2
      sed -n '1,220p' "$calls" >&2
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
          *"prepare-artifacts"*)
            exit 7
            ;;
          *"/workspace/scripts/"*)
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

mkdir -p "$tmp_dir/state/rendered" "$tmp_dir/staging" "$tmp_dir/evidence" "$tmp_dir/logs"
cp "$repo_root/simulation/docker/examples/docker.env.example" "$tmp_dir/harness.env"
cp "$repo_root/examples/gerrit.env.example" "$tmp_dir/gerrit.env"
cp "$repo_root/examples/jenkins-controller.env.example" "$tmp_dir/jenkins-controller.env"
cp "$repo_root/examples/jenkins-agent.env.example" "$tmp_dir/jenkins-agent.env"
cat >>"$tmp_dir/harness.env" <<EOF
HARNESS_GERRIT_ENV_FILE=$(printf '%q' "$tmp_dir/gerrit.env")
HARNESS_JENKINS_CONTROLLER_ENV_FILE=$(printf '%q' "$tmp_dir/jenkins-controller.env")
HARNESS_JENKINS_AGENT_ENV_FILE=$(printf '%q' "$tmp_dir/jenkins-agent.env")
EOF

common_env=(
  PATH="$fake_bin:$PATH"
  DOCKER_CALLS_LOG="$calls"
  HARNESS_RUN_ID="env-readonly-$$"
  HARNESS_PROJECT_NAME="env-readonly-$$"
  HARNESS_STATE_DIR="$tmp_dir/state"
  HARNESS_STAGING_DIR="$tmp_dir/staging"
  HARNESS_EVIDENCE_DIR="$tmp_dir/evidence"
  HARNESS_LOG_DIR="$tmp_dir/logs"
)

env "${common_env[@]}" \
  "$repo_root/simulation/docker/docker-harness.sh" render-config --env "$tmp_dir/harness.env" \
  >/dev/null

snapshot="$tmp_dir/env-files.before"
find "$tmp_dir/state" -type f \( -name '*.env' -o -path '*/runtime-inputs/*' \) -print0 |
  sort -z |
  xargs -0 sha256sum >"$snapshot"

for command in \
  "prepare-artifacts --role gerrit" \
  "prepare-artifacts --role jenkins-controller" \
  "prepare-artifacts --role jenkins-agent" \
  "run-role-gate --role gerrit" \
  "run-role-gate --role jenkins-controller" \
  "run-role-gate --role jenkins-agent"
do
  set +e
  # shellcheck disable=SC2086
  env "${common_env[@]}" "$repo_root/simulation/docker/docker-harness.sh" $command \
    >"$tmp_dir/${command// /-}.out" 2>&1
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || {
    printf 'Expected lifecycle command to fail in fake Docker mode: %s\n' "$command" >&2
    exit 1
  }
done

after="$tmp_dir/env-files.after"
find "$tmp_dir/state" -type f \( -name '*.env' -o -path '*/runtime-inputs/*' \) -print0 |
  sort -z |
  xargs -0 sha256sum >"$after"

if ! cmp -s "$snapshot" "$after"; then
  printf 'Lifecycle command created or modified rendered/runtime env files\n' >&2
  diff -u "$snapshot" "$after" >&2 || true
  exit 1
fi
