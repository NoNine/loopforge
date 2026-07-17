#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
cleanup() {
  rc=$?
  rm -rf "$tmp_dir" \
    "$repo_root/generated/simulation/docker/relative-default-$$" \
    "$repo_root/generated/simulation/docker/custom-relative" \
    "$repo_root/generated/simulation/docker/sets/relative-default-$$" \
    "$repo_root/generated/simulation/docker/sets/custom-relative"
  rm -f "$repo_root/generated/simulation/docker/locks/relative-default-$$.lock" \
    "$repo_root/generated/simulation/docker/locks/custom-relative.lock"
  exit "$rc"
}
trap cleanup EXIT

script="$repo_root/simulation/docker/simulate.sh"
default_host_dir="$repo_root/generated/simulation/docker/relative-default-$$/host"
custom_host_dir="$repo_root/generated/simulation/docker/custom-relative/host"

(
  cd /tmp
  HARNESS_RUN_ID="relative-default-$$" \
  HARNESS_SET_ID="relative-default-$$" \
    "$script" init-run >"$tmp_dir/default-init-run.out"
)

for file in harness.env gerrit.env jenkins-controller.env jenkins-agent.env integration.env; do
  [ -f "$default_host_dir/source-inputs/$file" ] || {
    printf 'Expected default init-run source snapshot from non-repo cwd: %s\n' "$file" >&2
    exit 1
  }
done

cat >"$tmp_dir/custom-relative.env" <<'EOF'
HARNESS_MODE=docker-simulation
HARNESS_RUN_ID=custom-relative
HARNESS_SET_ID=custom-relative
HARNESS_GERRIT_ENV_FILE=examples/gerrit.env.example
HARNESS_JENKINS_CONTROLLER_ENV_FILE=examples/jenkins-controller.env.example
HARNESS_JENKINS_AGENT_ENV_FILE=examples/jenkins-agent.env.example
HARNESS_INTEGRATION_ENV_FILE=examples/integration.env.example
EOF

(
  cd "$repo_root"
    "$script" init-run --env "$tmp_dir/custom-relative.env" >"$tmp_dir/custom-init-run.out"
)

runtime_env="$custom_host_dir/rendered/harness.runtime.env"
runtime_dir="$custom_host_dir/runtime-inputs"
source_dir="$custom_host_dir/source-inputs"
grep -Fq "HARNESS_GERRIT_ENV_FILE=$runtime_dir/gerrit.env" "$runtime_env"
for file in gerrit.env jenkins-controller.env jenkins-agent.env integration.env; do
  [ -f "$source_dir/$file" ] || {
    printf 'Expected custom relative source snapshot: %s\n' "$file" >&2
    exit 1
  }
done
[ ! -e "$runtime_dir" ]
