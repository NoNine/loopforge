#!/usr/bin/env bash
# shellcheck disable=SC2016

set -euo pipefail

repo_root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir" "$repo_root/generated/simulation/docker"/run-workflow-*-"$$" 2>/dev/null || true' EXIT

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
partial_calls="$tmp_dir/partial-calls.log"
partial_workflow_calls="$tmp_dir/partial-workflow-calls.log"
post_clean_calls="$tmp_dir/post-clean-calls.log"
post_clean_workflow_calls="$tmp_dir/post-clean-workflow-calls.log"

mkdir -p "$run_dir"

set +e
PATH="$fake_bin:$PATH" DOCKER_CALLS_LOG="$fresh_calls" \
  HARNESS_TEST_WORKFLOW_CALLS="$fresh_workflow_calls" \
  HARNESS_RUN_ID="$run_id" HARNESS_PROJECT_NAME="$run_id" \
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
  $0 == "up" { up = NR }
  END { exit !(init && create && up && init < create && create < up) }
' "$fresh_workflow_calls"

PATH="$fake_bin:$PATH" DOCKER_CALLS_LOG="$resume_calls" \
  HARNESS_RUN_ID="$run_id" HARNESS_PROJECT_NAME="$run_id" \
  "$repo_root/simulation/docker/simulate.sh" --env "$harness_env" init-run >/dev/null

set +e
PATH="$fake_bin:$PATH" DOCKER_CALLS_LOG="$resume_calls" \
  HARNESS_TEST_WORKFLOW_CALLS="$resume_workflow_calls" \
  HARNESS_RUN_ID="$run_id" HARNESS_PROJECT_NAME="$run_id" \
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
grep -Fq '==> up' "$tmp_dir/resume.out"
if grep -Eq '^==> (preflight|init-run)$' "$tmp_dir/resume.out"; then
  printf 'resume workflow should not rerun preflight or init-run\n' >&2
  exit 1
fi

partial_run_id="run-workflow-partial-$$"
partial_dir="$repo_root/generated/simulation/docker/$partial_run_id"
mkdir -p "$partial_dir/host/rendered"
cat >"$partial_dir/host/rendered/harness.env" <<EOF
HARNESS_MODE=docker-simulation
HARNESS_RUN_ID=$partial_run_id
HARNESS_PROJECT_NAME=$partial_run_id
EOF

set +e
PATH="$fake_bin:$PATH" DOCKER_CALLS_LOG="$partial_calls" \
  HARNESS_TEST_WORKFLOW_CALLS="$partial_workflow_calls" \
  HARNESS_RUN_ID="$partial_run_id" HARNESS_PROJECT_NAME="$partial_run_id" \
  "$repo_root/simulation/docker/simulate.sh" --env "$harness_env" run >"$tmp_dir/partial.out" 2>&1
partial_rc=$?
set -e
[ "$partial_rc" -eq 0 ] || {
  printf 'partial-state fresh workflow failed\n' >&2
  sed -n '1,160p' "$tmp_dir/partial.out" >&2
  exit 1
}
grep -Fq 'run: mode=fresh run-id='"$partial_run_id" "$tmp_dir/partial.out"
grep -Fq '==> preflight' "$tmp_dir/partial.out"
grep -Fq '==> init-run' "$tmp_dir/partial.out"
grep -Fq '==> create' "$tmp_dir/partial.out"
grep -Fq 'preflight' "$partial_workflow_calls"
grep -Fq 'init-run' "$partial_workflow_calls"
grep -Fq 'create' "$partial_workflow_calls"

post_clean_run_id="run-workflow-post-clean-$$"
post_clean_dir="$repo_root/generated/simulation/docker/$post_clean_run_id"
mkdir -p \
  "$post_clean_dir/target/artifacts/exported" \
  "$post_clean_dir/evidence" \
  "$post_clean_dir/logs"

set +e
PATH="$fake_bin:$PATH" DOCKER_CALLS_LOG="$post_clean_calls" \
  HARNESS_TEST_WORKFLOW_CALLS="$post_clean_workflow_calls" \
  HARNESS_RUN_ID="$post_clean_run_id" HARNESS_PROJECT_NAME="$post_clean_run_id" \
  "$repo_root/simulation/docker/simulate.sh" --env "$harness_env" run >"$tmp_dir/post-clean.out" 2>&1
post_clean_rc=$?
set -e
[ "$post_clean_rc" -eq 0 ] || {
  printf 'post-clean fresh workflow failed\n' >&2
  sed -n '1,160p' "$tmp_dir/post-clean.out" >&2
  exit 1
}
grep -Fq 'run: mode=fresh run-id='"$post_clean_run_id" "$tmp_dir/post-clean.out"
grep -Fq '==> preflight' "$tmp_dir/post-clean.out"
grep -Fq '==> init-run' "$tmp_dir/post-clean.out"
grep -Fq '==> create' "$tmp_dir/post-clean.out"
grep -Fq 'preflight' "$post_clean_workflow_calls"
grep -Fq 'init-run' "$post_clean_workflow_calls"
grep -Fq 'create' "$post_clean_workflow_calls"
