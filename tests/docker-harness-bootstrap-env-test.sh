#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
fake_bin="$tmp_dir/bin"
run_id="bootstrap-$$"
run_dir="$repo_root/generated/simulation/docker/$run_id"
trap 'rm -rf "$tmp_dir" "$run_dir"' EXIT

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

state_dir="$run_dir/target/helper-state"

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
  "$repo_root/simulation/docker/simulate.sh" \
  --env "$tmp_dir/harness.env" preflight >"$tmp_dir/preflight.out"
grep -Fq "mode=docker-simulation" "$tmp_dir/preflight.out"

PATH="$fake_bin:$PATH" \
  "$repo_root/simulation/docker/simulate.sh" \
  --env "$tmp_dir/harness.env" init-run >"$tmp_dir/init-run.out"

grep -Fq "init-run: ok run-id=$run_id" "$tmp_dir/init-run.out"
! grep -Fq "gerrit_url=" "$tmp_dir/init-run.out"
! grep -Fq "jenkins_url=" "$tmp_dir/init-run.out"

runtime_env="$state_dir/rendered/harness.runtime.env"
grep -Fq "HARNESS_RUN_ID=$run_id" "$runtime_env"
grep -Fq "HARNESS_PROJECT_NAME=$run_id" "$runtime_env"
