#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
fake_bin="$tmp_dir/bin"
calls="$tmp_dir/docker-calls.log"
run_id="role-env-test-$$"
run_dir="$repo_root/generated/simulation/docker/$run_id"
cleanup() {
  rc=$?
  if [ "$rc" -ne 0 ] && [ -f "$calls" ]; then
    printf '%s\n' "--- docker calls ---" >&2
    sed -n '1,200p' "$calls" >&2
  fi
  rm -rf "$tmp_dir" "$run_dir"
  exit "$rc"
}
trap cleanup EXIT

mkdir -p "$fake_bin"
cat >"$fake_bin/docker" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$DOCKER_CALLS_LOG"
case "$*" in
  *"compose version --short"*) printf '2.0.0\n' ;;
  *"compose version"*) printf 'Docker Compose version v2.0.0\n' ;;
  compose*)
    if [ "${1:-}" = "compose" ]; then
      shift
    fi
    while [ "$#" -gt 0 ]; do
      case "$1" in
        -f|--file|--project-name|-p)
        shift 2
          ;;
        -*)
        shift
          ;;
        *)
          break
          ;;
      esac
    done
    case "${1:-}" in
      ps)
        printf 'container-id\n'
        ;;
      exec)
        shift
        [ "${1:-}" = "-T" ] && shift
        service="${1:-}"
        shift
        case "$*" in
          *"/etc/os-release"*)
            printf '24.04 noble\n'
            ;;
          "test -x "*)
            exit 0
            ;;
          "env")
            case "$service" in
              bundle-factory) printf 'HARNESS_ENVIRONMENT=bundle-factory\n' ;;
              *) printf 'HARNESS_ENVIRONMENT=%s\n' "$service" ;;
            esac
            ;;
          *"/workspace/scripts/"*)
            exit 9
            ;;
          *)
            exit 0
            ;;
        esac
        ;;
      *)
        exit 0
        ;;
    esac
    ;;
  inspect*)
    printf 'true\n'
    ;;
esac
SH
chmod +x "$fake_bin/docker"

cp "$repo_root/simulation/docker/examples/docker.env.example" "$tmp_dir/harness.env"
cp "$repo_root/examples/gerrit.env.example" "$tmp_dir/gerrit.env"
cp "$repo_root/examples/jenkins-controller.env.example" "$tmp_dir/jenkins-controller.env"
cp "$repo_root/examples/jenkins-agent.env.example" "$tmp_dir/jenkins-agent.env"
cat >>"$tmp_dir/gerrit.env" <<'EOF'
GERRIT_SENTINEL=original
EOF
cat >>"$tmp_dir/jenkins-controller.env" <<'EOF'
JENKINS_CONTROLLER_SENTINEL=original
EOF
cat >>"$tmp_dir/jenkins-agent.env" <<'EOF'
JENKINS_AGENT_SENTINEL=original
EOF
cat >>"$tmp_dir/harness.env" <<EOF
HARNESS_RUN_ID=$run_id
HARNESS_PROJECT_NAME=$run_id
HARNESS_GERRIT_ENV_FILE=$(printf '%q' "$tmp_dir/gerrit.env")
HARNESS_JENKINS_CONTROLLER_ENV_FILE=$(printf '%q' "$tmp_dir/jenkins-controller.env")
HARNESS_JENKINS_AGENT_ENV_FILE=$(printf '%q' "$tmp_dir/jenkins-agent.env")
EOF

PATH="$fake_bin:$PATH" \
DOCKER_CALLS_LOG="$calls" \
  "$repo_root/simulation/docker/simulate.sh" render-config --env "$tmp_dir/harness.env" >/dev/null

state_dir="$run_dir/state"
runtime_dir="$state_dir/rendered/runtime-inputs"
product_home_dir="$run_dir/product-homes"
[ -d "$product_home_dir/gerrit" ] || {
  printf 'Expected Gerrit product home backing dir outside harness state: %s\n' "$product_home_dir/gerrit" >&2
  exit 1
}
[ -d "$product_home_dir/jenkins-controller" ] || {
  printf 'Expected Jenkins product home backing dir outside harness state: %s\n' "$product_home_dir/jenkins-controller" >&2
  exit 1
}
[ -d "$product_home_dir/jenkins-agent" ] || {
  printf 'Expected agent product home backing dir outside harness state: %s\n' "$product_home_dir/jenkins-agent" >&2
  exit 1
}
case "$product_home_dir" in
  "$state_dir"|"$state_dir"/*)
    printf 'Product home backing dir must not be under harness state: %s\n' "$product_home_dir" >&2
    exit 1
    ;;
esac
cat >"$tmp_dir/gerrit.env" <<'EOF'
GERRIT_DOWNLOAD_ARTIFACTS="0"
GERRIT_SENTINEL=mutated-after-render
EOF
cat >"$tmp_dir/jenkins-controller.env" <<'EOF'
JENKINS_DOWNLOAD_ARTIFACTS="0"
JENKINS_CONTROLLER_SENTINEL=mutated-after-render
EOF
cat >"$tmp_dir/jenkins-agent.env" <<'EOF'
JENKINS_AGENT_SENTINEL=mutated-after-render
EOF

for file in \
  "$state_dir/bundle-factory/rendered/gerrit-bundle-factory.env" \
  "$state_dir/bundle-factory/rendered/jenkins-controller-bundle-factory.env" \
  "$state_dir/bundle-factory/rendered/jenkins-agent.env" \
  "$state_dir/gerrit/rendered/gerrit.env" \
  "$state_dir/jenkins-controller/rendered/jenkins-controller.env" \
  "$state_dir/jenkins-agent/rendered/jenkins-agent.env"
do
  [ -f "$file" ] || {
    printf 'Expected render-config to create helper env file: %s\n' "$file" >&2
    exit 1
  }
  mode="$(stat -c '%a' "$file")"
  [ "$mode" = "600" ] || {
    printf 'Expected helper env file mode 600 for %s, got %s\n' "$file" "$mode" >&2
    exit 1
  }
done

common_env=(
  PATH="$fake_bin:$PATH"
  DOCKER_CALLS_LOG="$calls"
  HARNESS_ENV_FILE="$tmp_dir/harness.env"
)

set +e
env "${common_env[@]}" \
  "$repo_root/simulation/docker/simulate.sh" --env "$tmp_dir/harness.env" prepare-artifacts --role gerrit >/dev/null 2>&1
env "${common_env[@]}" \
  "$repo_root/simulation/docker/simulate.sh" --env "$tmp_dir/harness.env" run-role-gate --role jenkins-controller >/dev/null 2>&1
env "${common_env[@]}" \
  "$repo_root/simulation/docker/simulate.sh" --env "$tmp_dir/harness.env" run-role-gate --role jenkins-agent >/dev/null 2>&1
set -e

grep -Fq -- '/workspace/scripts/gerrit-setup.sh --env /harness/state/rendered/gerrit-bundle-factory.env --yes prepare-artifacts' "$calls"
grep -Fq -- '/workspace/scripts/jenkins-controller-setup.sh --env /harness/state/rendered/jenkins-controller-bundle-factory.env --yes prepare-artifacts' "$calls"
grep -Fq -- '/workspace/scripts/jenkins-agent-setup.sh --env /harness/state/rendered/jenkins-agent.env prepare-artifacts' "$calls"

grep -Fq 'GERRIT_SENTINEL=original' "$runtime_dir/gerrit.env"
grep -Fq 'JENKINS_CONTROLLER_SENTINEL=original' "$runtime_dir/jenkins-controller.env"
grep -Fq 'JENKINS_AGENT_SENTINEL=original' "$runtime_dir/jenkins-agent.env"
grep -Fq 'GERRIT_DOWNLOAD_ARTIFACTS="1"' "$state_dir/bundle-factory/rendered/gerrit-bundle-factory.env"
grep -Fq 'JENKINS_DOWNLOAD_ARTIFACTS="1"' "$state_dir/bundle-factory/rendered/jenkins-controller-bundle-factory.env"
grep -Fq 'GERRIT_SENTINEL=original' "$state_dir/gerrit/rendered/gerrit.env"
grep -Fq 'JENKINS_CONTROLLER_SENTINEL=original' "$state_dir/jenkins-controller/rendered/jenkins-controller.env"
grep -Fq 'JENKINS_AGENT_SENTINEL=original' "$state_dir/jenkins-agent/rendered/jenkins-agent.env"
grep -Fq 'GERRIT_SITE_PATH="/srv/gerrit"' "$state_dir/gerrit/rendered/gerrit.env"
grep -Fq 'JENKINS_HOME="/var/lib/jenkins"' "$state_dir/jenkins-controller/rendered/jenkins-controller.env"
grep -Fq 'JENKINS_AGENT_REMOTE_FS="/var/lib/jenkins-agent"' "$state_dir/jenkins-agent/rendered/jenkins-agent.env"
if grep -R -Fq 'mutated-after-render' \
  "$runtime_dir" \
  "$state_dir/bundle-factory/rendered" \
  "$state_dir/gerrit/rendered" \
  "$state_dir/jenkins-controller/rendered" \
  "$state_dir/jenkins-agent/rendered"
then
  printf 'Rendered helper envs used mutated original operator env files\n' >&2
  exit 1
fi
