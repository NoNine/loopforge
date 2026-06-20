#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
cleanup() {
  rc=$?
  rm -rf "$tmp_dir"
  exit "$rc"
}
trap cleanup EXIT

state_dir="$tmp_dir/state"
staging_dir="$tmp_dir/staging"
evidence_dir="$tmp_dir/evidence"
log_dir="$tmp_dir/logs"
script="$repo_root/simulation/docker/docker-harness.sh"

(
  cd /tmp
  HARNESS_RUN_ID="relative-default-$$" \
  HARNESS_PROJECT_NAME="relative-default-$$" \
  HARNESS_STATE_DIR="$state_dir/default-state" \
  HARNESS_STAGING_DIR="$staging_dir/default-staging" \
  HARNESS_EVIDENCE_DIR="$evidence_dir/default-evidence" \
  HARNESS_LOG_DIR="$log_dir/default-logs" \
    "$script" render-config >"$tmp_dir/default-render.out"
)

for file in harness.env gerrit.env jenkins-controller.env jenkins-agent.env integration.env; do
  [ -f "$state_dir/default-state/rendered/runtime-inputs/$file" ] || {
    printf 'Expected default render runtime input copy from non-repo cwd: %s\n' "$file" >&2
    exit 1
  }
done

cat >"$tmp_dir/custom-relative.env" <<'EOF'
HARNESS_MODE=docker-harness-simulation
HARNESS_RUN_ID=custom-relative
HARNESS_PROJECT_NAME=custom-relative
HARNESS_GERRIT_ENV_FILE=examples/gerrit.env.example
HARNESS_JENKINS_CONTROLLER_ENV_FILE=examples/jenkins-controller.env.example
HARNESS_JENKINS_AGENT_ENV_FILE=examples/jenkins-agent.env.example
HARNESS_INTEGRATION_ENV_FILE=examples/integration.env.example
EOF

(
  cd "$repo_root"
  HARNESS_RUN_ID="relative-custom-$$" \
  HARNESS_PROJECT_NAME="relative-custom-$$" \
  HARNESS_STATE_DIR="$state_dir/custom-state" \
  HARNESS_STAGING_DIR="$staging_dir/custom-staging" \
  HARNESS_EVIDENCE_DIR="$evidence_dir/custom-evidence" \
  HARNESS_LOG_DIR="$log_dir/custom-logs" \
    "$script" render-config --env "$tmp_dir/custom-relative.env" >"$tmp_dir/custom-render.out"
)

runtime_env="$state_dir/custom-state/rendered/harness.runtime.env"
runtime_dir="$state_dir/custom-state/rendered/runtime-inputs"
grep -Fq "HARNESS_GERRIT_ENV_FILE=$runtime_dir/gerrit.env" "$runtime_env"
for file in gerrit.env jenkins-controller.env jenkins-agent.env integration.env; do
  [ -f "$runtime_dir/$file" ] || {
    printf 'Expected custom relative runtime input copy: %s\n' "$file" >&2
    exit 1
  }
done
