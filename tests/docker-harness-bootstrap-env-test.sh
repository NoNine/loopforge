#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
fake_bin="$tmp_dir/bin"
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$fake_bin"
cat >"$fake_bin/docker" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  *"compose version"*) printf 'Docker Compose version v2.0.0\n' ;;
  *) exit 0 ;;
esac
SH
chmod +x "$fake_bin/docker"

state_dir="$tmp_dir/state"
staging_dir="$tmp_dir/staging"
evidence_dir="$tmp_dir/evidence"
log_dir="$tmp_dir/logs"

cat >"$tmp_dir/harness.env" <<EOF
HARNESS_MODE=docker-harness-simulation
HARNESS_RUN_ID=bootstrap-$$
HARNESS_PROJECT_NAME=bootstrap-$$
HARNESS_GERRIT_ENV_FILE=examples/gerrit.env.example
HARNESS_JENKINS_CONTROLLER_ENV_FILE=examples/jenkins-controller.env.example
HARNESS_JENKINS_AGENT_ENV_FILE=examples/jenkins-agent.env.example
HARNESS_INTEGRATION_ENV_FILE=examples/integration.env.example
EOF

PATH="$fake_bin:$PATH" \
  "$repo_root/simulation/docker/docker-harness.sh" \
  --env "$tmp_dir/harness.env" preflight >"$tmp_dir/preflight.out"
grep -Fq "mode=docker-harness-simulation" "$tmp_dir/preflight.out"

PATH="$fake_bin:$PATH" \
  HARNESS_STATE_DIR="$state_dir" \
  HARNESS_STAGING_DIR="$staging_dir" \
  HARNESS_EVIDENCE_DIR="$evidence_dir" \
  HARNESS_LOG_DIR="$log_dir" \
  "$repo_root/simulation/docker/docker-harness.sh" \
  --env "$tmp_dir/harness.env" render-config >"$tmp_dir/render.out"

grep -Fq "render-config: ok run-id=bootstrap-$$" "$tmp_dir/render.out"
! grep -Fq "gerrit_url=" "$tmp_dir/render.out"
! grep -Fq "jenkins_url=" "$tmp_dir/render.out"

runtime_env="$state_dir/rendered/harness.runtime.env"
grep -Fq "HARNESS_RUN_ID=bootstrap-$$" "$runtime_env"
grep -Fq "HARNESS_PROJECT_NAME=bootstrap-$$" "$runtime_env"
