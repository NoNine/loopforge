#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

state_dir="$tmp_dir/state"
staging_dir="$tmp_dir/staging"
evidence_dir="$tmp_dir/evidence"
log_dir="$tmp_dir/logs"
calls="$tmp_dir/calls.log"

mkdir -p "$state_dir/rendered"
cat >"$state_dir/rendered/harness.runtime.env" <<EOF
HARNESS_RUN_ID=dispatch-$$
HARNESS_PROJECT_NAME=dispatch-$$
HARNESS_STATE_DIR=$(printf '%q' "$state_dir")
HARNESS_STAGING_DIR=$(printf '%q' "$staging_dir")
HARNESS_EVIDENCE_DIR=$(printf '%q' "$evidence_dir")
HARNESS_LOG_DIR=$(printf '%q' "$log_dir")
HARNESS_RENDERED_ENV=$(printf '%q' "$state_dir/rendered/harness.env")
HARNESS_RUNTIME_ENV=$(printf '%q' "$state_dir/rendered/harness.runtime.env")
HARNESS_BASELINE_CONTRACT=$(printf '%q' "$state_dir/rendered/artifact-manifest-contract.txt")
HARNESS_PUBLIC_INTERNET_FALLBACK_LABEL=simulation-only
HARNESS_UBUNTU_BASELINE_RELEASE=24.04
HARNESS_UBUNTU_BASELINE_CODENAME=noble
HARNESS_JAVA_BASELINE=21
HARNESS_GERRIT_BASELINE=3.13.6
HARNESS_JENKINS_BASELINE=2.555.3
HARNESS_JENKINS_PLUGIN_MANAGER_BASELINE=2.15.0
EOF

HARNESS_TEST_STUB_ROLE_COMMANDS="$calls" \
HARNESS_RUN_ID="dispatch-$$" \
HARNESS_PROJECT_NAME="dispatch-$$" \
HARNESS_STATE_DIR="$state_dir" \
HARNESS_STAGING_DIR="$staging_dir" \
HARNESS_EVIDENCE_DIR="$evidence_dir" \
HARNESS_LOG_DIR="$log_dir" \
  "$repo_root/simulation/docker/simulate.sh" prepare-artifacts >"$tmp_dir/prepare.out"

HARNESS_TEST_STUB_ROLE_COMMANDS="$calls" \
HARNESS_RUN_ID="dispatch-$$" \
HARNESS_PROJECT_NAME="dispatch-$$" \
HARNESS_STATE_DIR="$state_dir" \
HARNESS_STAGING_DIR="$staging_dir" \
HARNESS_EVIDENCE_DIR="$evidence_dir" \
HARNESS_LOG_DIR="$log_dir" \
  "$repo_root/simulation/docker/simulate.sh" stage-artifacts >"$tmp_dir/stage.out"

grep -Fxq 'prepare-artifacts gerrit' "$calls"
grep -Fxq 'prepare-artifacts jenkins-controller' "$calls"
grep -Fxq 'prepare-artifacts jenkins-agent' "$calls"
grep -Fxq 'stage-artifacts gerrit' "$calls"
grep -Fxq 'stage-artifacts jenkins-controller' "$calls"
grep -Fxq 'stage-artifacts jenkins-agent' "$calls"
