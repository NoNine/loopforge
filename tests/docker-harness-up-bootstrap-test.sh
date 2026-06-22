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
  *"compose up -d --build"*) exit 0 ;;
  *" ps -q "*) printf 'container-id\n' ;;
  *"/etc/os-release"*) printf 'release=24.04 codename=noble pretty=Ubuntu 24.04\n' ;;
  *"inspect -f"*) printf 'true\n' ;;
  *) exit 0 ;;
esac
SH
chmod +x "$fake_bin/docker"

state_dir="$tmp_dir/state"
staging_dir="$tmp_dir/staging"
evidence_dir="$tmp_dir/evidence"
log_dir="$tmp_dir/logs"

cat >"$tmp_dir/harness.env" <<EOF
HARNESS_MODE=docker-simulation
HARNESS_RUN_ID=bootstrap-up-$$
HARNESS_PROJECT_NAME=bootstrap-up-$$
HARNESS_GERRIT_ENV_FILE=examples/gerrit.env.example
HARNESS_JENKINS_CONTROLLER_ENV_FILE=examples/jenkins-controller.env.example
HARNESS_JENKINS_AGENT_ENV_FILE=examples/jenkins-agent.env.example
HARNESS_INTEGRATION_ENV_FILE=examples/integration.env.example
EOF

PATH="$fake_bin:$PATH" \
HARNESS_STATE_DIR="$state_dir" \
HARNESS_STAGING_DIR="$staging_dir" \
HARNESS_EVIDENCE_DIR="$evidence_dir" \
HARNESS_LOG_DIR="$log_dir" \
  "$repo_root/simulation/docker/simulate.sh" \
  --env "$tmp_dir/harness.env" render-config >/dev/null

PATH="$fake_bin:$PATH" \
HARNESS_STATE_DIR="$state_dir" \
HARNESS_STAGING_DIR="$staging_dir" \
HARNESS_EVIDENCE_DIR="$evidence_dir" \
HARNESS_LOG_DIR="$log_dir" \
  "$repo_root/simulation/docker/simulate.sh" \
  --env "$tmp_dir/harness.env" up >"$tmp_dir/up.out"

grep -Fq "HARNESS_RUN_ID=bootstrap-up-$$" "$state_dir/rendered/harness.runtime.env"
grep -Fq "up: started bundle-factory ldap gerrit jenkins-controller jenkins-agent" "$tmp_dir/up.out"
