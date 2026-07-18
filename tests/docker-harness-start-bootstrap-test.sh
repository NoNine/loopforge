#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
fake_bin="$tmp_dir/bin"
run_id="bootstrap-start-$$"
set_id="bootstrap-$$"
run_dir="$repo_root/generated/simulation/docker/$run_id"
calls="$tmp_dir/docker-calls.log"
cleanup() {
  rm -rf "$tmp_dir" "$run_dir" \
    "$repo_root/generated/simulation/docker/sets/$set_id"
  rm -f "$repo_root/generated/simulation/docker/locks/$set_id.lock"
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
export DOCKER_SET_FAKE_LIB="$repo_root/tests/fixtures/docker-set-state.sh"
export DOCKER_SET_FAKE_STATE_DIR="$tmp_dir/docker-state"
export REPO_ROOT="$repo_root"
cat >"$fake_bin/ssh-keyscan" <<'SH'
#!/usr/bin/env bash
printf '[127.0.0.1]:%s ssh-ed25519 test-key\n' "${4:-22}"
SH
chmod +x "$fake_bin/ssh-keyscan"

rendered_dir="$run_dir/host/rendered"

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
  "$repo_root/simulation/docker/simulate.sh" \
  --env "$tmp_dir/harness.env" init-run >/dev/null

PATH="$fake_bin:$PATH" \
  DOCKER_CALLS_LOG="$calls" \
  "$repo_root/simulation/docker/simulate.sh" \
  --env "$tmp_dir/harness.env" create >"$tmp_dir/create.out"
grep -Fq "create: ok state=created resources=stopped" "$tmp_dir/create.out"

start_line=$(( $(wc -l <"$calls") + 1 ))
PATH="$fake_bin:$PATH" \
  DOCKER_CALLS_LOG="$calls" \
  "$repo_root/simulation/docker/simulate.sh" \
  --env "$tmp_dir/harness.env" start >"$tmp_dir/start.out"

grep -Fq "HARNESS_RUN_ID=$run_id" "$rendered_dir/harness.runtime.env"
grep -Fq "start: ok state=started durable=baseline resources=running target-access=ready inputs=ready" "$tmp_dir/start.out"
[ -d "$run_dir/host/runtime-inputs" ]
[ -f "$run_dir/host/state/effective-inputs.env" ]
grep -Fxq 'input_state=ready' "$run_dir/host/state/workflow-state.env"
tail -n +"$start_line" "$calls" >"$tmp_dir/start-calls.log"
if grep -Eq -- 'compose .* start .*--build|compose .* up' "$tmp_dir/start-calls.log"; then
  printf 'start must not build images; create owns image build\n' >&2
  exit 1
fi
for service in bundle-factory gerrit-target jenkins-controller-target jenkins-agent-target; do
  grep -F -- "exec -T -u root $service sh -c" "$calls" | \
    grep -Fq -- '/home/ci-operator/loopforge.loopforge-tmp-' || {
      printf 'start must stage the shared role-helper tree in %s\n' "$service" >&2
      exit 1
    }
done
