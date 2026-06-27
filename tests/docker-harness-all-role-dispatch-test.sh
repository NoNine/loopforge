#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
run_id="dispatch-$$"
run_dir="$repo_root/generated/simulation/docker/$run_id"
trap 'rm -rf "$tmp_dir" "$run_dir"' EXIT

state_dir="$run_dir/target/helper-state"
calls="$tmp_dir/calls.log"

cat >"$tmp_dir/harness.env" <<EOF
HARNESS_MODE=docker-simulation
HARNESS_RUN_ID=$run_id
HARNESS_PROJECT_NAME=$run_id
HARNESS_GERRIT_ENV_FILE=examples/gerrit.env.example
HARNESS_JENKINS_CONTROLLER_ENV_FILE=examples/jenkins-controller.env.example
HARNESS_JENKINS_AGENT_ENV_FILE=examples/jenkins-agent.env.example
HARNESS_INTEGRATION_ENV_FILE=examples/integration.env.example
EOF
"$repo_root/simulation/docker/simulate.sh" --env "$tmp_dir/harness.env" init-run >"$tmp_dir/init-run.out"

HARNESS_TEST_STUB_ROLE_COMMANDS="$calls" \
  "$repo_root/simulation/docker/simulate.sh" --env "$tmp_dir/harness.env" prepare-artifacts >"$tmp_dir/prepare.out"

HARNESS_TEST_STUB_ROLE_COMMANDS="$calls" \
  "$repo_root/simulation/docker/simulate.sh" --env "$tmp_dir/harness.env" stage-artifacts >"$tmp_dir/stage.out"

grep -Fxq 'prepare-artifacts gerrit' "$calls"
grep -Fxq 'prepare-artifacts jenkins-controller' "$calls"
grep -Fxq 'prepare-artifacts jenkins-agent' "$calls"
grep -Fxq 'stage-artifacts gerrit' "$calls"
grep -Fxq 'stage-artifacts jenkins-controller' "$calls"
grep -Fxq 'stage-artifacts jenkins-agent' "$calls"
