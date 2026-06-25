#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
run_id="runtime-inputs-$$"
run_dir="$repo_root/generated/simulation/docker/$run_id"
trap 'rm -rf "$tmp_dir" "$run_dir"' EXIT

state_dir="$run_dir/state"

cat >"$tmp_dir/integration.env" <<'EOF'
JENKINS_SHARED_STORAGE_PATH=/mnt/harness-shared
INTEGRATION_SENTINEL=original
EOF
cat >"$tmp_dir/gerrit.env" <<'EOF'
GERRIT_DOWNLOAD_ARTIFACTS="0"
GERRIT_HOST="gerrit-target"
GERRIT_SENTINEL=original
EOF
cat >"$tmp_dir/jenkins-controller.env" <<'EOF'
JENKINS_DOWNLOAD_ARTIFACTS="0"
JENKINS_CONTROLLER_SENTINEL=original
EOF
cat >"$tmp_dir/jenkins-agent.env" <<'EOF'
JENKINS_AGENT_SENTINEL=original
EOF
cat >"$tmp_dir/harness.env" <<EOF
HARNESS_MODE=docker-simulation
HARNESS_RUN_ID=$run_id
HARNESS_PROJECT_NAME=$run_id
HARNESS_GERRIT_ENV_FILE=$(printf '%q' "$tmp_dir/gerrit.env")
HARNESS_JENKINS_CONTROLLER_ENV_FILE=$(printf '%q' "$tmp_dir/jenkins-controller.env")
HARNESS_JENKINS_AGENT_ENV_FILE=$(printf '%q' "$tmp_dir/jenkins-agent.env")
HARNESS_INTEGRATION_ENV_FILE=$(printf '%q' "$tmp_dir/integration.env")
EOF

  "$repo_root/simulation/docker/simulate.sh" init-run --env "$tmp_dir/harness.env" \
  >"$tmp_dir/init-run.out"

runtime_dir="$state_dir/rendered/runtime-inputs"
runtime_env="$state_dir/rendered/harness.runtime.env"
product_home_dir="$run_dir/product-homes"

for file in harness.env gerrit.env jenkins-controller.env jenkins-agent.env integration.env; do
  [ -f "$runtime_dir/$file" ] || {
    printf 'Expected runtime input copy: %s\n' "$runtime_dir/$file" >&2
    exit 1
  }
  mode="$(stat -c '%a' "$runtime_dir/$file")"
  [ "$mode" = "600" ] || {
    printf 'Expected %s to have mode 600, got %s\n' "$runtime_dir/$file" "$mode" >&2
    exit 1
  }
done

grep -Fq "HARNESS_ENV_FILE=$runtime_dir/harness.env" "$runtime_env"
grep -Fq "HARNESS_GERRIT_ENV_FILE=$runtime_dir/gerrit.env" "$runtime_env"
grep -Fq "HARNESS_JENKINS_CONTROLLER_ENV_FILE=$runtime_dir/jenkins-controller.env" "$runtime_env"
grep -Fq "HARNESS_JENKINS_AGENT_ENV_FILE=$runtime_dir/jenkins-agent.env" "$runtime_env"
grep -Fq "HARNESS_INTEGRATION_ENV_FILE=$runtime_dir/integration.env" "$runtime_env"
grep -Fq "HARNESS_GENERATED_RUN_DIR=$run_dir" "$runtime_env"
grep -Fq "HARNESS_PRODUCT_HOME_DIR=$product_home_dir" "$runtime_env"
[ "$product_home_dir" != "$state_dir" ] || {
  printf 'Product home dir must not equal harness state dir\n' >&2
  exit 1
}
case "$product_home_dir" in
  "$state_dir"/*)
    printf 'Product home dir must not be below harness state dir\n' >&2
    exit 1
    ;;
esac

cat >"$tmp_dir/gerrit.env" <<'EOF'
GERRIT_SENTINEL=mutated-after-render
EOF

grep -Fq 'GERRIT_SENTINEL=original' "$runtime_dir/gerrit.env"
if grep -Fq 'mutated-after-render' "$runtime_dir/gerrit.env"; then
  printf 'Runtime input copy changed after original operator env mutation\n' >&2
  exit 1
fi

gerrit_browser_port="$(sed -n 's/^HARNESS_GERRIT_HTTP_HOST_PORT=//p' "$state_dir/rendered/harness.env")"
grep -Fq 'GERRIT_HOST="gerrit-target"' "$runtime_dir/helper-envs/gerrit-target/gerrit.env"
grep -Fq "GERRIT_CANONICAL_WEB_URL=http://127.0.0.1:$gerrit_browser_port/" "$runtime_dir/helper-envs/gerrit-target/gerrit.env"

loaded_gerrit_env="$(
  # shellcheck disable=SC1090
  . "$runtime_env"
  printf '%s\n' "$HARNESS_GERRIT_ENV_FILE"
)"
[ "$loaded_gerrit_env" = "$runtime_dir/gerrit.env" ] || {
  printf 'Expected lifecycle config to point at runtime copy, got %s\n' "$loaded_gerrit_env" >&2
  exit 1
}

loaded_product_home_dir="$(
  # shellcheck disable=SC1090
  . "$runtime_env"
  printf '%s\n' "$HARNESS_PRODUCT_HOME_DIR"
)"
[ "$loaded_product_home_dir" = "$product_home_dir" ] || {
  printf 'Expected runtime config to preserve product home dir, got %s\n' "$loaded_product_home_dir" >&2
  exit 1
}
