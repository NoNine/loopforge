#!/usr/bin/env bash
# shellcheck disable=SC2016

set -euo pipefail

repo_root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir" "$repo_root/generated/simulation/docker"/run-workflow-*-"$$" \
    "$repo_root/generated/simulation/docker/sets"/run-workflow-*-"$$" 2>/dev/null || true
  rm -f "$repo_root/generated/simulation/docker/locks"/run-workflow-*-"$$".lock 2>/dev/null || true
}
trap cleanup EXIT

fake_bin="$tmp_dir/bin"
mkdir -p "$fake_bin"
cat >"$fake_bin/docker" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$DOCKER_CALLS_LOG"
case "$*" in
  *"compose version"*) printf 'Docker Compose version v2.0.0\n' ;;
  ps\ -a\ --format*) exit 0 ;;
  *) exit 0 ;;
esac
SH
chmod +x "$fake_bin/docker"

harness_env="$tmp_dir/harness.env"
sed \
  -e '/^HARNESS_GERRIT_HTTP_HOST_PORT=/d' \
  -e '/^HARNESS_JENKINS_HTTP_HOST_PORT=/d' \
  "$repo_root/simulation/docker/examples/docker.env.example" >"$harness_env"

run_id="run-workflow-$$"
run_dir="$repo_root/generated/simulation/docker/$run_id"
fresh_calls="$tmp_dir/fresh-calls.log"
fresh_workflow_calls="$tmp_dir/fresh-workflow-calls.log"
resume_calls="$tmp_dir/resume-calls.log"
resume_workflow_calls="$tmp_dir/resume-workflow-calls.log"

set +e
PATH="$fake_bin:$PATH" DOCKER_CALLS_LOG="$fresh_calls" \
  HARNESS_TEST_WORKFLOW_CALLS="$fresh_workflow_calls" \
  HARNESS_RUN_ID="$run_id" HARNESS_SET_ID="$run_id" \
  "$repo_root/simulation/docker/simulate.sh" --env "$harness_env" run >"$tmp_dir/fresh.out" 2>&1
fresh_rc=$?
set -e
[ "$fresh_rc" -eq 0 ] || {
  printf 'fresh workflow failed\n' >&2
  sed -n '1,120p' "$tmp_dir/fresh.out" >&2
  exit 1
}
grep -Fq 'run: mode=fresh run-id='"$run_id" "$tmp_dir/fresh.out"
grep -Fq 'preflight' "$fresh_workflow_calls"
grep -Fq 'init-run' "$fresh_workflow_calls"
grep -Fq 'create' "$fresh_workflow_calls"
awk '
  $0 == "init-run" { init = NR }
  $0 == "create" { create = NR }
  $0 == "start" { start = NR }
  END { exit !(init && create && start && init < create && create < start) }
' "$fresh_workflow_calls"

PATH="$fake_bin:$PATH" DOCKER_CALLS_LOG="$resume_calls" \
  HARNESS_RUN_ID="$run_id" HARNESS_SET_ID="$run_id" \
  "$repo_root/simulation/docker/simulate.sh" --env "$harness_env" init-run >/dev/null

set +e
PATH="$fake_bin:$PATH" DOCKER_CALLS_LOG="$resume_calls" \
  HARNESS_TEST_WORKFLOW_CALLS="$resume_workflow_calls" \
  HARNESS_RUN_ID="$run_id" HARNESS_SET_ID="$run_id" \
  "$repo_root/simulation/docker/simulate.sh" --env "$harness_env" run >"$tmp_dir/resume.out" 2>&1
resume_rc=$?
set -e
[ "$resume_rc" -eq 0 ] || {
  printf 'resume workflow failed\n' >&2
  sed -n '1,160p' "$tmp_dir/resume.out" >&2
  exit 1
}
grep -Fq 'run: mode=resume run-id='"$run_id" "$tmp_dir/resume.out"
grep -Fq '==> create' "$tmp_dir/resume.out"
grep -Fq '==> start' "$tmp_dir/resume.out"
if grep -Eq '^==> (preflight|init-run)$' "$tmp_dir/resume.out"; then
  printf 'resume workflow should not rerun preflight or init-run\n' >&2
  exit 1
fi
