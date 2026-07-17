#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
fake_bin="$tmp_dir/bin"
run_id="summary-$$"
set_id="summary-$$"
run_dir="$repo_root/generated/simulation/docker/$run_id"
trap 'rm -rf "$tmp_dir" "$run_dir" "$repo_root/generated/simulation/docker/sets/$set_id"; rm -f "$repo_root/generated/simulation/docker/locks/$set_id.lock"' EXIT

mkdir -p "$fake_bin"
cat >"$fake_bin/docker" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  *"compose version"*) printf 'Docker Compose version v2.0.0\n' ;;
  *"compose build"*) exit 0 ;;
  *"compose up -d"*) exit 0 ;;
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
  "$repo_root/simulation/docker/simulate.sh" --env "$tmp_dir/harness.env" preflight >"$tmp_dir/preflight.out"
grep -Fq "preflight: ok mode=docker-simulation compose=" "$tmp_dir/preflight.out"

PATH="$fake_bin:$PATH" \
  "$repo_root/simulation/docker/simulate.sh" --env "$tmp_dir/harness.env" init-run >"$tmp_dir/init-run.out"
grep -Fq "init-run: ok set-id=$set_id run-id=$run_id" "$tmp_dir/init-run.out"
! grep -Fq "gerrit_url=" "$tmp_dir/init-run.out"
! grep -Fq "jenkins_url=" "$tmp_dir/init-run.out"

PATH="$fake_bin:$PATH" \
  "$repo_root/simulation/docker/simulate.sh" --env "$tmp_dir/harness.env" create >"$tmp_dir/create.out"
grep -Fq "create: ok images=project-built" "$tmp_dir/create.out"

PATH="$fake_bin:$PATH" \
  "$repo_root/simulation/docker/simulate.sh" --env "$tmp_dir/harness.env" start >"$tmp_dir/start.out"
grep -Fq "start: started bundle-factory ldap gerrit jenkins-controller jenkins-agent" "$tmp_dir/start.out"
! grep -Fq "gerrit_url=" "$tmp_dir/start.out"
! grep -Fq "jenkins_url=" "$tmp_dir/start.out"

PATH="$fake_bin:$PATH" \
  "$repo_root/simulation/docker/simulate.sh" --env "$tmp_dir/harness.env" status >"$tmp_dir/status.out"
grep -Fq "status: running" "$tmp_dir/status.out"
grep -Fq "Run ID        $run_id" "$tmp_dir/status.out"
grep -Fq "Project       loopforge-docker-$set_id" "$tmp_dir/status.out"
grep -Fq "Gerrit URL    http://127.0.0.1:18081/" "$tmp_dir/status.out"
grep -Fq "Jenkins URL   http://127.0.0.1:18082/login" "$tmp_dir/status.out"
grep -Fq "Login accounts" "$tmp_dir/status.out"
grep -Fq "Gerrit              gerrit-admin    admin-password        Gerrit admin user" "$tmp_dir/status.out"
grep -Fq "Jenkins             jenkins-admin   admin-password        Jenkins admin user" "$tmp_dir/status.out"
grep -Fq "Gerrit              test-user       test-password         Test/change workflow user" "$tmp_dir/status.out"
if grep -Fq "Gerrit integration  jenkins-gerrit  integration-password" "$tmp_dir/status.out"; then
  printf 'status must not print a password-backed Gerrit integration account\n' >&2
  exit 1
fi
tail -1 "$tmp_dir/status.out" | grep -Fq -- "------------------  --------------  --------------------  ----------------------------------------"

PATH="$fake_bin:$PATH" \
  "$repo_root/simulation/docker/simulate.sh" --env "$tmp_dir/harness.env" stop >"$tmp_dir/stop.out"
grep -Fq "stop: stopped harness containers" "$tmp_dir/stop.out"
