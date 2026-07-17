#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
fake_bin="$tmp_dir/bin"
run_id="runtime-inputs-$$"
run_dir="$repo_root/generated/simulation/docker/$run_id"
trap 'rm -rf "$tmp_dir" "$run_dir" "$repo_root/generated/simulation/docker/sets/$run_id"; rm -f "$repo_root/generated/simulation/docker/locks/$run_id.lock"' EXIT

host_dir="$run_dir/host"

mkdir -p "$fake_bin"
cat >"$fake_bin/docker" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  *"compose version"*) printf 'Docker Compose version v2.0.0\n' ;;
  *" ps -q "*) printf 'container-id\n' ;;
  *"/etc/os-release"*) printf 'release=24.04 codename=noble pretty=Ubuntu 24.04\n' ;;
  *"gerrit-target"*"stat -c"*) printf '61010:61010\n' ;;
  *"jenkins-controller-target"*"stat -c"*) printf '61020:61020\n' ;;
  *"jenkins-agent-target"*"stat -c"*) printf '61030:61030\n' ;;
  *"inspect -f"*) printf 'true\n' ;;
  *) exit 0 ;;
esac
SH
chmod +x "$fake_bin/docker"
cat >"$fake_bin/ssh-keyscan" <<'SH'
#!/usr/bin/env bash
printf '[127.0.0.1]:%s ssh-ed25519 test-key\n' "${4:-22}"
SH
chmod +x "$fake_bin/ssh-keyscan"

cat >"$tmp_dir/integration.env" <<'EOF'
JENKINS_SHARED_STORAGE_PATH=/data/jenkins-shared
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
HARNESS_SET_ID=$run_id
HARNESS_GERRIT_ENV_FILE=$(printf '%q' "$tmp_dir/gerrit.env")
HARNESS_JENKINS_CONTROLLER_ENV_FILE=$(printf '%q' "$tmp_dir/jenkins-controller.env")
HARNESS_JENKINS_AGENT_ENV_FILE=$(printf '%q' "$tmp_dir/jenkins-agent.env")
HARNESS_INTEGRATION_ENV_FILE=$(printf '%q' "$tmp_dir/integration.env")
HARNESS_LDAP_BIND_PASSWORD=runtime-secret-fixture
EOF

PATH="$fake_bin:$PATH" \
  "$repo_root/simulation/docker/simulate.sh" init-run --env "$tmp_dir/harness.env" \
  >"$tmp_dir/init-run.out"

source_dir="$host_dir/source-inputs"
runtime_dir="$host_dir/runtime-inputs"
runtime_env="$host_dir/rendered/harness.runtime.env"
product_home_dir="$run_dir/target/product-homes"

for file in harness.env gerrit.env jenkins-controller.env jenkins-agent.env integration.env; do
  [ -f "$source_dir/$file" ] || {
    printf 'Expected source input snapshot: %s\n' "$source_dir/$file" >&2
    exit 1
  }
  mode="$(stat -c '%a' "$source_dir/$file")"
  [ "$mode" = "600" ] || {
    printf 'Expected %s to have mode 600, got %s\n' "$source_dir/$file" "$mode" >&2
    exit 1
  }
done
[ ! -e "$runtime_dir" ]
[ ! -e "$host_dir/state/effective-inputs.env" ]
grep -Fxq 'input_state=pending' "$host_dir/state/workflow-state.env"

grep -Fq "HARNESS_ENV_FILE=$source_dir/harness.env" "$runtime_env"
grep -Fq "HARNESS_GERRIT_ENV_FILE=$runtime_dir/gerrit.env" "$runtime_env"
grep -Fq "HARNESS_JENKINS_CONTROLLER_ENV_FILE=$runtime_dir/jenkins-controller.env" "$runtime_env"
grep -Fq "HARNESS_JENKINS_AGENT_ENV_FILE=$runtime_dir/jenkins-agent.env" "$runtime_env"
grep -Fq "HARNESS_INTEGRATION_ENV_FILE=$runtime_dir/integration.env" "$runtime_env"
grep -Fq "HARNESS_GENERATED_RUN_DIR=$run_dir" "$runtime_env"
grep -Fq "HARNESS_PRODUCT_HOME_DIR=$product_home_dir" "$runtime_env"
grep -Fq "HARNESS_LDAP_BIND_PASSWORD=runtime-secret-fixture" "$runtime_env"
grep -Fq "HARNESS_LDAP_BIND_PASSWORD=runtime-secret-fixture" "$source_dir/harness.env"
if grep -R -Fq 'simulation-owned-redacted' "$host_dir/rendered" "$source_dir"; then
  printf 'Generated simulation env files must not replace the LDAP bind password with a redaction marker\n' >&2
  exit 1
fi
if grep -Fq 'HARNESS_STATE_DIR=' "$runtime_env"; then
  state_dir="$(sed -n 's/^HARNESS_STATE_DIR=//p' "$runtime_env")"
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
fi

cat >"$tmp_dir/gerrit.env" <<'EOF'
GERRIT_SENTINEL=mutated-after-render
EOF

grep -Fq 'GERRIT_SENTINEL=original' "$source_dir/gerrit.env"
if grep -Fq 'mutated-after-render' "$source_dir/gerrit.env"; then
  printf 'Source input snapshot changed after original operator env mutation\n' >&2
  exit 1
fi

PATH="$fake_bin:$PATH" \
  "$repo_root/simulation/docker/simulate.sh" create --env "$tmp_dir/harness.env" \
  >"$tmp_dir/create.out"
PATH="$fake_bin:$PATH" \
  "$repo_root/simulation/docker/simulate.sh" start --env "$tmp_dir/harness.env" \
  >"$tmp_dir/start.out"

for file in harness.env gerrit.env jenkins-controller.env jenkins-agent.env integration.env; do
  [ -f "$runtime_dir/$file" ] || {
    printf 'Expected effective input: %s\n' "$runtime_dir/$file" >&2
    exit 1
  }
  [ "$(stat -c '%a' "$runtime_dir/$file")" = 600 ]
done
[ -f "$host_dir/state/effective-inputs.env" ]
grep -Fxq 'input_state=ready' "$host_dir/state/workflow-state.env"
grep -Eq '^effective_inputs_fingerprint=[a-f0-9]{64}$' \
  "$host_dir/state/effective-inputs.env"
grep -Fq 'GERRIT_SENTINEL=original' "$runtime_dir/gerrit.env"
if grep -R -Fq 'mutated-after-render' "$runtime_dir"; then
  printf 'Effective inputs used mutated external operator files\n' >&2
  exit 1
fi

gerrit_browser_port="$(sed -n 's/^HARNESS_GERRIT_HTTP_HOST_PORT=//p' "$host_dir/rendered/harness.env")"
grep -Fq 'GERRIT_HOST="gerrit-target"' "$runtime_dir/gerrit.env"
grep -Fq "GERRIT_CANONICAL_WEB_URL=http://127.0.0.1:$gerrit_browser_port/" "$runtime_dir/gerrit.env"
[ ! -e "$runtime_dir/helper-envs" ]
if grep -Eq '^INTEGRATION_(GERRIT|JENKINS_CONTROLLER|JENKINS_AGENT)_TARGET_SSH_HOST=' \
  "$runtime_dir/integration.env"; then
  printf 'Docker effective integration input must exclude invocation-only hosts\n' >&2
  exit 1
fi

effective_before="$(sha256sum "$runtime_dir"/*.env "$host_dir/state/effective-inputs.env")"
if ! PATH="$fake_bin:$PATH" \
  "$repo_root/simulation/docker/simulate.sh" start --env "$tmp_dir/harness.env" \
  >"$tmp_dir/start-repeat.out" 2>&1; then
  cat "$tmp_dir/start-repeat.out" >&2
  repeat_log="$(sed -n 's/^log=//p' "$tmp_dir/start-repeat.out" | tail -1)"
  [ -z "$repeat_log" ] || tail -30 "$repeat_log" >&2
  exit 1
fi
[ "$effective_before" = "$(sha256sum "$runtime_dir"/*.env "$host_dir/state/effective-inputs.env")" ] || {
  printf 'Repeated start changed the published effective inputs\n' >&2
  exit 1
}

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
