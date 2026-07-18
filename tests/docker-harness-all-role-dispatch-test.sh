#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
fake_bin="$tmp_dir/bin"
run_id="dispatch-$$"
run_dir="$repo_root/generated/simulation/docker/$run_id"
trap 'rm -rf "$tmp_dir" "$run_dir" "$repo_root/generated/simulation/docker/sets/$run_id"; rm -f "$repo_root/generated/simulation/docker/locks/$run_id.lock"' EXIT

state_dir="$repo_root/generated/simulation/docker/sets/$run_id/runtime/helper-state"
calls="$tmp_dir/calls.log"

mkdir -p "$fake_bin"
cat >"$fake_bin/docker" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
. "$DOCKER_SET_FAKE_LIB"
if fake_docker_set_handle "$@"; then exit 0; else rc=$?; [ "$rc" -eq 125 ] || exit "$rc"; fi
case "$*" in
  *"compose version"*) printf 'Docker Compose version v2.0.0\n' ;;
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

cat >"$tmp_dir/harness.env" <<EOF
HARNESS_MODE=docker-simulation
HARNESS_RUN_ID=$run_id
HARNESS_SET_ID=$run_id
HARNESS_GERRIT_ENV_FILE=examples/gerrit.env.example
HARNESS_JENKINS_CONTROLLER_ENV_FILE=examples/jenkins-controller.env.example
HARNESS_JENKINS_AGENT_ENV_FILE=examples/jenkins-agent.env.example
HARNESS_INTEGRATION_ENV_FILE=examples/integration.env.example
EOF
PATH="$fake_bin:$PATH" \
  "$repo_root/simulation/docker/simulate.sh" --env "$tmp_dir/harness.env" init-run >"$tmp_dir/init-run.out"
PATH="$fake_bin:$PATH" \
  "$repo_root/simulation/docker/simulate.sh" --env "$tmp_dir/harness.env" create >/dev/null
PATH="$fake_bin:$PATH" \
  "$repo_root/simulation/docker/simulate.sh" --env "$tmp_dir/harness.env" start >/dev/null

PATH="$fake_bin:$PATH" HARNESS_TEST_STUB_ROLE_COMMANDS="$calls" \
  "$repo_root/simulation/docker/simulate.sh" --env "$tmp_dir/harness.env" prepare-artifacts >"$tmp_dir/prepare.out"

PATH="$fake_bin:$PATH" HARNESS_TEST_STUB_ROLE_COMMANDS="$calls" \
  "$repo_root/simulation/docker/simulate.sh" --env "$tmp_dir/harness.env" stage-artifacts >"$tmp_dir/stage.out"

grep -Fxq 'prepare-artifacts gerrit' "$calls"
grep -Fxq 'prepare-artifacts jenkins-controller' "$calls"
grep -Fxq 'prepare-artifacts jenkins-agent' "$calls"
grep -Fxq 'stage-artifacts gerrit' "$calls"
grep -Fxq 'stage-artifacts jenkins-controller' "$calls"
grep -Fxq 'stage-artifacts jenkins-agent' "$calls"
