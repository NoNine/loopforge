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
  *"compose down"*) exit 0 ;;
  *" ps -q gerrit-target"*) printf 'gerrit-container\n' ;;
  *" ps -q jenkins-controller-target"*) printf 'jenkins-container\n' ;;
  *" ps -q "*) printf 'container-id\n' ;;
  *"/etc/os-release"*) printf 'release=24.04 codename=noble pretty=Ubuntu 24.04\n' ;;
  *"inspect -f {{.State.Running}}"*) printf 'true\n' ;;
  *"inspect -f "*"gerrit-container"*) printf '18081\n' ;;
  *"inspect -f "*"jenkins-container"*) printf '18082\n' ;;
  *"inspect -f "*) printf 'true\n' ;;
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
HARNESS_RUN_ID=summary-$$
HARNESS_PROJECT_NAME=summary-$$
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
  "$repo_root/simulation/docker/docker-harness.sh" --env "$tmp_dir/harness.env" preflight >"$tmp_dir/preflight.out"
grep -Fq "preflight: ok mode=docker-simulation compose=" "$tmp_dir/preflight.out"

PATH="$fake_bin:$PATH" \
HARNESS_STATE_DIR="$state_dir" \
HARNESS_STAGING_DIR="$staging_dir" \
HARNESS_EVIDENCE_DIR="$evidence_dir" \
HARNESS_LOG_DIR="$log_dir" \
  "$repo_root/simulation/docker/docker-harness.sh" --env "$tmp_dir/harness.env" render-config >"$tmp_dir/render.out"
grep -Fq "render-config: ok run-id=summary-$$" "$tmp_dir/render.out"
! grep -Fq "gerrit_url=" "$tmp_dir/render.out"
! grep -Fq "jenkins_url=" "$tmp_dir/render.out"

PATH="$fake_bin:$PATH" \
HARNESS_STATE_DIR="$state_dir" \
HARNESS_STAGING_DIR="$staging_dir" \
HARNESS_EVIDENCE_DIR="$evidence_dir" \
HARNESS_LOG_DIR="$log_dir" \
  "$repo_root/simulation/docker/docker-harness.sh" --env "$tmp_dir/harness.env" up >"$tmp_dir/up.out"
grep -Fq "up: started bundle-factory ldap gerrit jenkins-controller jenkins-agent" "$tmp_dir/up.out"
! grep -Fq "gerrit_url=" "$tmp_dir/up.out"
! grep -Fq "jenkins_url=" "$tmp_dir/up.out"

PATH="$fake_bin:$PATH" \
HARNESS_STATE_DIR="$state_dir" \
HARNESS_STAGING_DIR="$staging_dir" \
HARNESS_EVIDENCE_DIR="$evidence_dir" \
HARNESS_LOG_DIR="$log_dir" \
  "$repo_root/simulation/docker/docker-harness.sh" --env "$tmp_dir/harness.env" status >"$tmp_dir/status.out"
grep -Fq "status: running" "$tmp_dir/status.out"
grep -Fq "Run ID        summary-$$" "$tmp_dir/status.out"
grep -Fq "Project       summary-$$" "$tmp_dir/status.out"
grep -Fq "Gerrit URL    http://127.0.0.1:18081/" "$tmp_dir/status.out"
grep -Fq "Jenkins URL   http://127.0.0.1:18082/login" "$tmp_dir/status.out"
grep -Fq "Login accounts" "$tmp_dir/status.out"
grep -Fq "Gerrit              gerrit-admin    admin-password        Gerrit admin user" "$tmp_dir/status.out"
grep -Fq "Jenkins             jenkins-admin   admin-password        Jenkins admin user" "$tmp_dir/status.out"
grep -Fq "Gerrit              test-user       test-password         Test/change workflow user" "$tmp_dir/status.out"
grep -Fq "Gerrit integration  jenkins-gerrit  integration-password  Jenkins-to-Gerrit integration account" "$tmp_dir/status.out"
tail -1 "$tmp_dir/status.out" | grep -Fq -- "------------------  --------------  --------------------  ----------------------------------------"

PATH="$fake_bin:$PATH" \
HARNESS_STATE_DIR="$state_dir" \
HARNESS_STAGING_DIR="$staging_dir" \
HARNESS_EVIDENCE_DIR="$evidence_dir" \
HARNESS_LOG_DIR="$log_dir" \
  "$repo_root/simulation/docker/docker-harness.sh" --env "$tmp_dir/harness.env" down >"$tmp_dir/down.out"
grep -Fq "down: stopped harness containers" "$tmp_dir/down.out"
