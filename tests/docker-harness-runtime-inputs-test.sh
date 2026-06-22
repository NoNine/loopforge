#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

state_dir="$tmp_dir/state"
staging_dir="$tmp_dir/staging"
evidence_dir="$tmp_dir/evidence"
log_dir="$tmp_dir/logs"

cat >"$tmp_dir/integration.env" <<'EOF'
JENKINS_SHARED_STORAGE_PATH=/mnt/harness-shared
INTEGRATION_SENTINEL=original
EOF
cat >"$tmp_dir/gerrit.env" <<'EOF'
GERRIT_DOWNLOAD_ARTIFACTS="0"
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
HARNESS_RUN_ID=runtime-inputs-$$
HARNESS_PROJECT_NAME=runtime-inputs-$$
HARNESS_GERRIT_ENV_FILE=$(printf '%q' "$tmp_dir/gerrit.env")
HARNESS_JENKINS_CONTROLLER_ENV_FILE=$(printf '%q' "$tmp_dir/jenkins-controller.env")
HARNESS_JENKINS_AGENT_ENV_FILE=$(printf '%q' "$tmp_dir/jenkins-agent.env")
HARNESS_INTEGRATION_ENV_FILE=$(printf '%q' "$tmp_dir/integration.env")
EOF

HARNESS_STATE_DIR="$state_dir" \
HARNESS_STAGING_DIR="$staging_dir" \
HARNESS_EVIDENCE_DIR="$evidence_dir" \
HARNESS_LOG_DIR="$log_dir" \
  "$repo_root/simulation/docker/simulate.sh" render-config --env "$tmp_dir/harness.env" \
  >"$tmp_dir/render.out"

runtime_dir="$state_dir/rendered/runtime-inputs"
runtime_env="$state_dir/rendered/harness.runtime.env"
product_home_dir="$repo_root/simulation/product-homes/docker/runtime-inputs-$$"

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
