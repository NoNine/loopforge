#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
fake_bin="$tmp_dir/bin"
calls="$tmp_dir/docker-calls.log"
run_id="audit-state-$$"
set_id="audit-state-$$"
run_dir="$repo_root/generated/simulation/docker/$run_id"
cleanup() {
  rc=$?
  if [ "$rc" -ne 0 ] && [ -f "$calls" ]; then
    printf '%s\n' '--- docker calls ---' >&2
    sed -n '1,240p' "$calls" >&2
  fi
  rm -rf "$tmp_dir" "$run_dir" "$repo_root/generated/simulation/docker/sets/$set_id"
  rm -f "$repo_root/generated/simulation/docker/locks/$set_id.lock"
  exit "$rc"
}
trap cleanup EXIT

mkdir -p "$fake_bin"
cat >"$fake_bin/docker" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$DOCKER_CALLS_LOG"
case "$*" in
  *"compose version"*) printf 'Docker Compose version v2.0.0\n' ;;
  ps\ -a\ --format*)
    [ -f "$DOCKER_CONTAINERS_FILE" ] && cat "$DOCKER_CONTAINERS_FILE"
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
        shift
        [ "${1:-}" = "-q" ] && shift
        service="${1:-}"
        if grep -Fxq "$HARNESS_PROJECT_NAME-$service" "$DOCKER_CONTAINERS_FILE" 2>/dev/null; then
          printf 'container-id\n'
        fi
        ;;
      exec)
        shift
        [ "${1:-}" = "-T" ] && shift
        service="${1:-}"
        shift
        case "$*" in
          "stat -Lc %d:%i "*)
            case "$service:$*" in
              bundle-factory:*"/workspace") stat -Lc '%d:%i' "$REPO_ROOT" ;;
              ldap:*"/var/lib/ldap") stat -Lc '%d:%i' "$RUN_DIR/target/ldap/data" ;;
              ldap:*"/etc/ldap/slapd.d") stat -Lc '%d:%i' "$RUN_DIR/target/ldap/config" ;;
              gerrit-target:*"/workspace"|jenkins-controller-target:*"/workspace"|jenkins-agent-target:*"/workspace") stat -Lc '%d:%i' "$REPO_ROOT" ;;
              gerrit-target:*"/srv/gerrit") stat -Lc '%d:%i' "$RUN_DIR/target/product-homes/gerrit" ;;
              jenkins-controller-target:*"/var/lib/jenkins") stat -Lc '%d:%i' "$RUN_DIR/target/product-homes/jenkins-controller" ;;
              jenkins-controller-target:*"/data/jenkins-shared") stat -Lc '%d:%i' "$RUN_DIR/target/shared-jenkins-storage" ;;
              jenkins-agent-target:*"/var/lib/jenkins-agent") stat -Lc '%d:%i' "$RUN_DIR/target/product-homes/jenkins-agent" ;;
              jenkins-agent-target:*"/data/jenkins-shared") stat -Lc '%d:%i' "$RUN_DIR/target/shared-jenkins-storage" ;;
              *)
                printf 'unexpected stat target service=%s command=%s\n' "$service" "$*" >&2
                exit 99
                ;;
            esac
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
  inspect\ -f\ *Mounts*)
    case "$*" in
      *-bundle-factory)
        printf '%s\t%s\n' "$REPO_ROOT" /workspace
        ;;
      *-ldap)
        printf '%s\t%s\n' "$RUN_DIR/target/ldap/data" /var/lib/ldap
        printf '%s\t%s\n' "$RUN_DIR/target/ldap/config" /etc/ldap/slapd.d
        ;;
      *-gerrit-target)
        printf '%s\t%s\n' "$REPO_ROOT" /workspace
        printf '%s\t%s\n' "$RUN_DIR/target/product-homes/gerrit" /srv/gerrit
        ;;
      *-jenkins-controller-target)
        printf '%s\t%s\n' "$REPO_ROOT" /workspace
        printf '%s\t%s\n' "$RUN_DIR/target/product-homes/jenkins-controller" /var/lib/jenkins
        printf '%s\t%s\n' "$RUN_DIR/target/shared-jenkins-storage" /data/jenkins-shared
        ;;
      *-jenkins-agent-target)
        printf '%s\t%s\n' "$REPO_ROOT" /workspace
        printf '%s\t%s\n' "$RUN_DIR/target/product-homes/jenkins-agent" /var/lib/jenkins-agent
        printf '%s\t%s\n' "$RUN_DIR/target/shared-jenkins-storage" /data/jenkins-shared
        ;;
    esac
    ;;
  inspect\ -f\ *State.Running*)
    printf 'true\n'
    ;;
  inspect*)
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
SH
chmod +x "$fake_bin/docker"

cat >"$tmp_dir/harness.env" <<EOF
HARNESS_MODE=docker-simulation
HARNESS_RUN_ID=$run_id
HARNESS_SET_ID=$set_id
HARNESS_GERRIT_ENV_FILE=examples/gerrit.env.example
HARNESS_JENKINS_CONTROLLER_ENV_FILE=examples/jenkins-controller.env.example
HARNESS_JENKINS_AGENT_ENV_FILE=examples/jenkins-agent.env.example
HARNESS_INTEGRATION_ENV_FILE=examples/integration.env.example
EOF

PATH="$fake_bin:$PATH" \
DOCKER_CALLS_LOG="$calls" \
DOCKER_CONTAINERS_FILE="$tmp_dir/empty-containers" \
REPO_ROOT="$repo_root" \
RUN_DIR="$run_dir" \
  "$repo_root/simulation/docker/simulate.sh" --env "$tmp_dir/harness.env" init-run >/dev/null

mkdir -p "$tmp_dir"
: >"$tmp_dir/empty-containers"

for service in bundle-factory ldap gerrit-target jenkins-controller-target jenkins-agent-target; do
  printf 'loopforge-docker-%s-%s\n' "$set_id" "$service"
done >"$tmp_dir/containers"

PATH="$fake_bin:$PATH" \
DOCKER_CALLS_LOG="$calls" \
DOCKER_CONTAINERS_FILE="$tmp_dir/containers" \
REPO_ROOT="$repo_root" \
RUN_DIR="$run_dir" \
  "$repo_root/simulation/docker/simulate.sh" --env "$tmp_dir/harness.env" audit-state >"$tmp_dir/audit.out"

grep -Fq 'audit-state: ok' "$tmp_dir/audit.out"
grep -Fq 'exec -T gerrit-target stat -Lc %d:%i /srv/gerrit' "$calls"
grep -Fq 'exec -T jenkins-controller-target stat -Lc %d:%i /var/lib/jenkins' "$calls"
grep -Fq 'exec -T jenkins-agent-target stat -Lc %d:%i /var/lib/jenkins-agent' "$calls"
if grep -Fq 'stat -Lc %d:%i /var/lib/loopforge' "$calls" ||
  grep -Fq 'stat -Lc %d:%i /var/log/loopforge' "$calls"; then
  printf 'audit-state must not enforce helper-owned Loopforge roots as Docker bind mounts\n' >&2
  exit 1
fi
