#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
fake_bin="$tmp_dir/bin"
run_id="bootstrap-up-$$"
run_dir="$repo_root/generated/simulation/docker/$run_id"
calls="$tmp_dir/docker-calls.log"
trap 'rm -rf "$tmp_dir" "$run_dir"' EXIT

mkdir -p "$fake_bin"
cat >"$fake_bin/docker" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$DOCKER_CALLS_LOG"
case "$*" in
  *"compose version"*) printf 'Docker Compose version v2.0.0\n' ;;
  *"compose build"*) exit 0 ;;
  *"compose up -d"*) exit 0 ;;
  *" ps -q "*) printf 'container-id\n' ;;
  *"/etc/os-release"*) printf 'release=24.04 codename=noble pretty=Ubuntu 24.04\n' ;;
  *"inspect -f"*) printf 'true\n' ;;
  *) exit 0 ;;
esac
SH
chmod +x "$fake_bin/docker"
cat >"$fake_bin/docker-compose" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$DOCKER_CALLS_LOG"
case "$*" in
  *"up -d"*)
    printf "ERROR: for gerrit-target  'ContainerConfig'\n" >&2
    exit 1
    ;;
  *"down --remove-orphans"*)
    printf 'compose down must not be called by up recovery\n' >&2
    exit 99
    ;;
  *) exit 0 ;;
esac
SH
chmod +x "$fake_bin/docker-compose"

rendered_dir="$run_dir/host/rendered"

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
  "$repo_root/simulation/docker/simulate.sh" \
  --env "$tmp_dir/harness.env" init-run >/dev/null

PATH="$fake_bin:$PATH" \
  DOCKER_CALLS_LOG="$calls" \
  "$repo_root/simulation/docker/simulate.sh" \
  --env "$tmp_dir/harness.env" create >"$tmp_dir/create.out"
grep -Fq "create: ok images=project-built" "$tmp_dir/create.out"

PATH="$fake_bin:$PATH" \
  DOCKER_CALLS_LOG="$calls" \
  "$repo_root/simulation/docker/simulate.sh" \
  --env "$tmp_dir/harness.env" up >"$tmp_dir/up.out"

grep -Fq "HARNESS_RUN_ID=$run_id" "$rendered_dir/harness.runtime.env"
grep -Fq "up: started bundle-factory ldap gerrit jenkins-controller jenkins-agent" "$tmp_dir/up.out"
if grep -Fq -- 'up -d --build' "$calls"; then
  printf 'up must not build images; create owns image build\n' >&2
  exit 1
fi
for service in bundle-factory gerrit-target jenkins-controller-target jenkins-agent-target; do
  grep -F -- "exec -T -u root $service sh -c" "$calls" | \
    grep -Fq -- '/home/ci-operator/loopforge.loopforge-tmp-' || {
      printf 'up must stage the shared role-helper tree in %s\n' "$service" >&2
      exit 1
    }
done

rm -rf "$run_dir"
rm -f "$calls"
PATH="$fake_bin:$PATH" \
  DOCKER_CALLS_LOG="$calls" \
  HARNESS_FORCE_COMPOSE_V1_FOR_TESTS=1 \
  "$repo_root/simulation/docker/simulate.sh" \
  --env "$tmp_dir/harness.env" init-run >/dev/null

PATH="$fake_bin:$PATH" \
  DOCKER_CALLS_LOG="$calls" \
  HARNESS_FORCE_COMPOSE_V1_FOR_TESTS=1 \
  "$repo_root/simulation/docker/simulate.sh" \
  --env "$tmp_dir/harness.env" create >/dev/null

set +e
PATH="$fake_bin:$PATH" \
  DOCKER_CALLS_LOG="$calls" \
  HARNESS_FORCE_COMPOSE_V1_FOR_TESTS=1 \
  "$repo_root/simulation/docker/simulate.sh" \
  --env "$tmp_dir/harness.env" up >"$tmp_dir/up-compose-v1.out" 2>&1
rc=$?
set -e
[ "$rc" -ne 0 ] || {
  printf 'up should fail when docker-compose v1 reports ContainerConfig recreate bug\n' >&2
  exit 1
}
grep -Fq 'up: failed' "$tmp_dir/up-compose-v1.out"
up_log="$(sed -n 's/^log=//p' "$tmp_dir/up-compose-v1.out" | tail -1)"
[ -n "$up_log" ] || {
  printf 'up failure must report a bounded log path\n' >&2
  exit 1
}
grep -Fq 'compose_recovery_required=docker-compose-v1-containerconfig' "$up_log"
grep -Fq 'recovery_instruction=run-down-or-clean-before-up' "$up_log"
if grep -Fq -- 'down --remove-orphans' "$calls"; then
  printf 'up must not call compose down --remove-orphans for lifecycle recovery\n' >&2
  exit 1
fi
