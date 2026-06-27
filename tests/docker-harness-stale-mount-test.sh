#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
fake_bin="$tmp_dir/bin"
calls="$tmp_dir/docker-calls.log"
run_id="stale-mount-$$"
run_dir="$repo_root/generated/simulation/docker/$run_id"
cleanup() {
  rc=$?
  if [ "$rc" -ne 0 ]; then
    [ -f "$calls" ] && {
      printf '%s\n' '--- docker calls ---' >&2
      sed -n '1,240p' "$calls" >&2
    }
    [ -f "$tmp_dir/status.out" ] && {
      printf '%s\n' '--- status output ---' >&2
      sed -n '1,120p' "$tmp_dir/status.out" >&2
    }
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
        case "${1:-}" in
          bundle-factory|ldap|gerrit-target|jenkins-controller-target|jenkins-agent-target)
            printf '%s-id\n' "${1:-}"
            ;;
        esac
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
              bundle-factory:*"/var/lib/loopforge/rendered")
                if [ "${STALE_IDENTITY:-0}" = "1" ]; then
                  printf 'stale:identity\n'
                else
                  stat -Lc '%d:%i' "$STALE_SOURCE"
                fi
                ;;
              bundle-factory:*"/var/lib/loopforge/evidence") stat -Lc '%d:%i' "$RUN_DIR/target/helper-state/bundle-factory/evidence" ;;
              bundle-factory:*"/var/lib/loopforge/artifact-bundle-work") stat -Lc '%d:%i' "$RUN_DIR/target/helper-state/bundle-factory/artifact-bundle-work" ;;
              ldap:*"/var/lib/ldap") stat -Lc '%d:%i' "$RUN_DIR/target/ldap/data" ;;
              ldap:*"/etc/ldap/slapd.d") stat -Lc '%d:%i' "$RUN_DIR/target/ldap/config" ;;
              gerrit-target:*"/workspace"|jenkins-controller-target:*"/workspace"|jenkins-agent-target:*"/workspace") stat -Lc '%d:%i' "$REPO_ROOT" ;;
              gerrit-target:*"/var/lib/loopforge") stat -Lc '%d:%i' "$RUN_DIR/target/helper-state/gerrit" ;;
              gerrit-target:*"/srv/gerrit") stat -Lc '%d:%i' "$RUN_DIR/target/product-homes/gerrit" ;;
              gerrit-target:*"/var/lib/loopforge/validation-secrets") stat -Lc '%d:%i' "$RUN_DIR/host/validation-secrets/gerrit" ;;
              gerrit-target:*"/var/lib/loopforge/evidence") stat -Lc '%d:%i' "$RUN_DIR/target/evidence/gerrit" ;;
              jenkins-controller-target:*"/var/lib/loopforge/evidence") stat -Lc '%d:%i' "$RUN_DIR/target/evidence/jenkins-controller" ;;
              jenkins-agent-target:*"/var/lib/loopforge/evidence") stat -Lc '%d:%i' "$RUN_DIR/target/evidence/jenkins-agent" ;;
              gerrit-target:*"/var/log/loopforge") stat -Lc '%d:%i' "$RUN_DIR/target/logs/gerrit" ;;
              jenkins-controller-target:*"/var/log/loopforge") stat -Lc '%d:%i' "$RUN_DIR/target/logs/jenkins-controller" ;;
              jenkins-agent-target:*"/var/log/loopforge") stat -Lc '%d:%i' "$RUN_DIR/target/logs/jenkins-agent" ;;
              jenkins-controller-target:*"/var/lib/loopforge") stat -Lc '%d:%i' "$RUN_DIR/target/helper-state/jenkins-controller" ;;
              jenkins-controller-target:*"/var/lib/jenkins") stat -Lc '%d:%i' "$RUN_DIR/target/product-homes/jenkins-controller" ;;
              jenkins-controller-target:*"/mnt/jenkins-shared"|jenkins-agent-target:*"/mnt/jenkins-shared") stat -Lc '%d:%i' "$RUN_DIR/target/shared-jenkins-storage" ;;
              jenkins-agent-target:*"/var/lib/loopforge") stat -Lc '%d:%i' "$RUN_DIR/target/helper-state/jenkins-agent" ;;
              jenkins-agent-target:*"/var/lib/jenkins-agent") stat -Lc '%d:%i' "$RUN_DIR/target/product-homes/jenkins-agent" ;;
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
      cp)
        exit 0
        ;;
      *)
        exit 0
        ;;
    esac
    ;;
  inspect\ -f\ *State.Running*)
    printf 'true\n'
    ;;
  inspect\ -f\ *NetworkSettings.Ports*)
    case "$*" in
      *gerrit-target-id) printf '18081\n' ;;
      *jenkins-controller-target-id) printf '18082\n' ;;
    esac
    ;;
  inspect\ -f\ *Mounts*)
    case "$*" in
      *-bundle-factory)
        printf '%s\t%s\n' "$REPO_ROOT" /workspace
        printf '%s\t%s\n' "$STALE_SOURCE" /var/lib/loopforge/rendered
        printf '%s\t%s\n' "$RUN_DIR/target/helper-state/bundle-factory/evidence" /var/lib/loopforge/evidence
        printf '%s\t%s\n' "$RUN_DIR/target/helper-state/bundle-factory/artifact-bundle-work" /var/lib/loopforge/artifact-bundle-work
        ;;
      *-ldap)
        printf '%s\t%s\n' "$RUN_DIR/target/ldap/data" /var/lib/ldap
        printf '%s\t%s\n' "$RUN_DIR/target/ldap/config" /etc/ldap/slapd.d
        ;;
      *-gerrit-target)
        printf '%s\t%s\n' "$REPO_ROOT" /workspace
        printf '%s\t%s\n' "$RUN_DIR/target/helper-state/gerrit" /var/lib/loopforge
        printf '%s\t%s\n' "$RUN_DIR/target/product-homes/gerrit" /srv/gerrit
        printf '%s\t%s\n' "$RUN_DIR/host/validation-secrets/gerrit" /var/lib/loopforge/validation-secrets
        printf '%s\t%s\n' "$RUN_DIR/target/evidence/gerrit" /var/lib/loopforge/evidence
        printf '%s\t%s\n' "$RUN_DIR/target/logs/gerrit" /var/log/loopforge
        ;;
      *-jenkins-controller-target)
        printf '%s\t%s\n' "$REPO_ROOT" /workspace
        printf '%s\t%s\n' "$RUN_DIR/target/helper-state/jenkins-controller" /var/lib/loopforge
        printf '%s\t%s\n' "$RUN_DIR/target/product-homes/jenkins-controller" /var/lib/jenkins
        printf '%s\t%s\n' "$RUN_DIR/target/shared-jenkins-storage" /mnt/jenkins-shared
        printf '%s\t%s\n' "$RUN_DIR/target/evidence/jenkins-controller" /var/lib/loopforge/evidence
        printf '%s\t%s\n' "$RUN_DIR/target/logs/jenkins-controller" /var/log/loopforge
        ;;
      *-jenkins-agent-target)
        printf '%s\t%s\n' "$REPO_ROOT" /workspace
        printf '%s\t%s\n' "$RUN_DIR/target/helper-state/jenkins-agent" /var/lib/loopforge
        printf '%s\t%s\n' "$RUN_DIR/target/product-homes/jenkins-agent" /var/lib/jenkins-agent
        printf '%s\t%s\n' "$RUN_DIR/target/shared-jenkins-storage" /mnt/jenkins-shared
        printf '%s\t%s\n' "$RUN_DIR/target/evidence/jenkins-agent" /var/lib/loopforge/evidence
        printf '%s\t%s\n' "$RUN_DIR/target/logs/jenkins-agent" /var/log/loopforge
        ;;
    esac
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
HARNESS_PROJECT_NAME=$run_id
HARNESS_GERRIT_ENV_FILE=examples/gerrit.env.example
HARNESS_JENKINS_CONTROLLER_ENV_FILE=examples/jenkins-controller.env.example
HARNESS_JENKINS_AGENT_ENV_FILE=examples/jenkins-agent.env.example
HARNESS_INTEGRATION_ENV_FILE=examples/integration.env.example
EOF

PATH="$fake_bin:$PATH" \
DOCKER_CALLS_LOG="$calls" \
DOCKER_CONTAINERS_FILE="$tmp_dir/containers" \
REPO_ROOT="$repo_root" \
RUN_DIR="$run_dir" \
STALE_SOURCE="$tmp_dir/unused" \
  "$repo_root/simulation/docker/simulate.sh" --env "$tmp_dir/harness.env" init-run >/dev/null

mkdir -p "$tmp_dir/stale-source"
chmod 0500 "$tmp_dir/stale-source"
for service in bundle-factory ldap gerrit-target jenkins-controller-target jenkins-agent-target; do
  printf '%s-%s\n' "$run_id" "$service"
done >"$tmp_dir/containers"
PATH="$fake_bin:$PATH" \
DOCKER_CALLS_LOG="$calls" \
DOCKER_CONTAINERS_FILE="$tmp_dir/containers" \
REPO_ROOT="$repo_root" \
RUN_DIR="$run_dir" \
STALE_SOURCE="$run_dir/host/bundle-factory/rendered" \
STALE_IDENTITY=0 \
  "$repo_root/simulation/docker/simulate.sh" --env "$tmp_dir/harness.env" status \
  >"$tmp_dir/status-ok.out" 2>&1
grep -Fq 'status: running' "$tmp_dir/status-ok.out"

set +e
PATH="$fake_bin:$PATH" \
DOCKER_CALLS_LOG="$calls" \
DOCKER_CONTAINERS_FILE="$tmp_dir/containers" \
REPO_ROOT="$repo_root" \
RUN_DIR="$run_dir" \
STALE_SOURCE="$tmp_dir/stale-source" \
STALE_IDENTITY=1 \
  "$repo_root/simulation/docker/simulate.sh" --env "$tmp_dir/harness.env" status \
  >"$tmp_dir/status.out" 2>&1
rc=$?
set -e

[ "$rc" -eq 0 ] || {
  printf 'status should stay on the cheap path when generated state is stale\n' >&2
  exit 1
}
grep -Fq 'status: running' "$tmp_dir/status.out"
if grep -Fq 'Stale Docker bind mount' "$tmp_dir/status.out"; then
  printf 'status must not run the expensive bind-mount sweep\n' >&2
  exit 1
fi

set +e
PATH="$fake_bin:$PATH" \
DOCKER_CALLS_LOG="$calls" \
DOCKER_CONTAINERS_FILE="$tmp_dir/containers" \
REPO_ROOT="$repo_root" \
RUN_DIR="$run_dir" \
STALE_SOURCE="$tmp_dir/stale-source" \
STALE_IDENTITY=1 \
  "$repo_root/simulation/docker/simulate.sh" --env "$tmp_dir/harness.env" audit-state \
  >"$tmp_dir/audit-state.out" 2>&1
rc=$?
set -e

[ "$rc" -ne 0 ] || {
  printf 'audit-state should fail on stale generated bind mount\n' >&2
  exit 1
}
grep -Fq 'Stale Docker bind mount' "$tmp_dir/audit-state.out"
grep -Fq 'run down or clean before resuming' "$tmp_dir/audit-state.out"
