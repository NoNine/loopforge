#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
docker_harness_sources=("$repo_root/simulation/docker/simulate.sh" "$repo_root/simulation/docker/lib/"*.sh)
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
  "ps -a --format {{.Names}}")
    if [ "${FAKE_CONTAINERS_EXIST:-0}" = "1" ]; then
      printf '%s-bundle-factory\n%s-ldap\n%s-gerrit-target\n%s-jenkins-controller-target\n%s-jenkins-agent-target\n' \
        "$FAKE_PROJECT_NAME" "$FAKE_PROJECT_NAME" "$FAKE_PROJECT_NAME" "$FAKE_PROJECT_NAME" "$FAKE_PROJECT_NAME"
      printf '%s-bundle-factory\n%s-ldap\n%s-gerrit-target\n%s-jenkins-controller-target\n%s-jenkins-agent-target\n' \
        "gerrit-jenkins-harness" "gerrit-jenkins-harness" "gerrit-jenkins-harness" "gerrit-jenkins-harness" "gerrit-jenkins-harness"
    fi
    ;;
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
        if [ "${1:-}" = "-u" ]; then
          shift 2
        fi
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
          *"/home/ci-operator/loopforge/scripts/"*)
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
GERRIT_SITE_PATH="/custom/gerrit-site"
GERRIT_ARTIFACT_OUTPUT_DIR="/custom/preparing/gerrit-artifacts-bundle/gerrit"
GERRIT_STAGED_ARTIFACT_DIR="/custom/staging/gerrit"
GERRIT_EVIDENCE_DIR="/custom/evidence/gerrit"
GERRIT_LOG_DIR="/custom/logs/gerrit"
EOF
cat >>"$tmp_dir/jenkins-controller.env" <<'EOF'
JENKINS_CONTROLLER_SENTINEL=original
JENKINS_HOME="/custom/jenkins-home"
JENKINS_STAGED_ARTIFACT_DIR="/custom/staging/jenkins"
JENKINS_ARTIFACT_OUTPUT_DIR="/custom/preparing/jenkins-artifacts-bundle/jenkins"
JENKINS_EVIDENCE_DIR="/custom/evidence/jenkins"
JENKINS_LOG_DIR="/custom/logs/jenkins"
EOF
cat >>"$tmp_dir/jenkins-agent.env" <<'EOF'
JENKINS_AGENT_SENTINEL=original
JENKINS_AGENT_REMOTE_FS="/custom/jenkins-agent-home"
JENKINS_AGENT_STATE_DIR="/custom/jenkins-agent-state"
JENKINS_AGENT_STAGED_ARTIFACT_DIR="/custom/staging/jenkins-agent"
JENKINS_AGENT_ARTIFACT_OUTPUT_DIR="/custom/preparing/jenkins-agent-artifacts-bundle/jenkins-agent"
JENKINS_AGENT_EVIDENCE_DIR="/custom/evidence/jenkins-agent"
JENKINS_AGENT_LOG_DIR="/custom/logs/jenkins-agent"
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
  "$repo_root/simulation/docker/simulate.sh" init-run --env "$tmp_dir/harness.env" >/dev/null

host_dir="$run_dir/host"
state_dir="$run_dir/target/helper-state"
runtime_dir="$host_dir/runtime-inputs"
product_home_dir="$run_dir/target/product-homes"
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
  "$runtime_dir/helper-envs/bundle-factory/gerrit-bundle-factory.env" \
  "$runtime_dir/helper-envs/bundle-factory/jenkins-controller-bundle-factory.env" \
  "$runtime_dir/helper-envs/bundle-factory/jenkins-agent.env" \
  "$runtime_dir/helper-envs/gerrit-target/gerrit.env" \
  "$runtime_dir/helper-envs/jenkins-controller-target/jenkins-controller.env" \
  "$runtime_dir/helper-envs/jenkins-agent-target/jenkins-agent.env"
do
  [ -f "$file" ] || {
    printf 'Expected init-run to create helper env file: %s\n' "$file" >&2
    exit 1
  }
  mode="$(stat -c '%a' "$file")"
  [ "$mode" = "600" ] || {
    printf 'Expected helper env file mode 600 for %s, got %s\n' "$file" "$mode" >&2
    exit 1
  }
done

grep -Fq -- '/home/ci-operator/loopforge-inputs/gerrit.env' "${docker_harness_sources[@]}"
grep -Fq -- '/home/ci-operator/loopforge-inputs/jenkins-controller.env' "${docker_harness_sources[@]}"
grep -Fq -- '/home/ci-operator/loopforge-inputs/%s.env' "${docker_harness_sources[@]}"
grep -Fq -- 'transfer_mode=docker-cp-input-waiver' "${docker_harness_sources[@]}"
grep -Fq -- 'ci-operator ci-operator 0600 "$log"' "${docker_harness_sources[@]}"
if grep -Fq -- '/home/ci-operator/loopforge-inputs/bundle-factory/' "${docker_harness_sources[@]}"; then
  printf 'Docker bundle-factory role envs must use the canonical flat operator input path\n' >&2
  exit 1
fi
if grep -Fq -- '/var/lib/loopforge/rendered' "${docker_harness_sources[@]}"; then
  printf 'Docker harness must not stage helper env files under Loopforge rendered state\n' >&2
  exit 1
fi

grep -Fq 'GERRIT_SENTINEL=original' "$runtime_dir/gerrit.env"
grep -Fq 'JENKINS_CONTROLLER_SENTINEL=original' "$runtime_dir/jenkins-controller.env"
grep -Fq 'JENKINS_AGENT_SENTINEL=original' "$runtime_dir/jenkins-agent.env"
grep -Fq 'GERRIT_DOWNLOAD_ARTIFACTS=1' "$runtime_dir/helper-envs/bundle-factory/gerrit-bundle-factory.env"
grep -Fq 'GERRIT_ARTIFACT_OUTPUT_DIR="/custom/preparing/gerrit-artifacts-bundle/gerrit"' "$runtime_dir/helper-envs/bundle-factory/gerrit-bundle-factory.env"
if grep -R -Fq 'GERRIT_LOCAL_ARTIFACT_OUTPUT_DIR' \
  "$repo_root/examples" \
  "$repo_root/scripts" \
  "$repo_root/simulation/docker/lib"
then
  printf 'GERRIT_LOCAL_ARTIFACT_OUTPUT_DIR must not remain in examples, scripts, or Docker rendering\n' >&2
  exit 1
fi
grep -Fq 'JENKINS_DOWNLOAD_ARTIFACTS=1' "$runtime_dir/helper-envs/bundle-factory/jenkins-controller-bundle-factory.env"
grep -Fq 'JENKINS_ARTIFACT_OUTPUT_DIR="/custom/preparing/jenkins-artifacts-bundle/jenkins"' "$runtime_dir/helper-envs/bundle-factory/jenkins-controller-bundle-factory.env"
grep -Fq 'JENKINS_AGENT_ARTIFACT_OUTPUT_DIR="/custom/preparing/jenkins-agent-artifacts-bundle/jenkins-agent"' "$runtime_dir/helper-envs/bundle-factory/jenkins-agent.env"
grep -Fq 'GERRIT_SENTINEL=original' "$runtime_dir/helper-envs/gerrit-target/gerrit.env"
grep -Fq 'JENKINS_CONTROLLER_SENTINEL=original' "$runtime_dir/helper-envs/jenkins-controller-target/jenkins-controller.env"
grep -Fq 'JENKINS_AGENT_SENTINEL=original' "$runtime_dir/helper-envs/jenkins-agent-target/jenkins-agent.env"
grep -Fq 'GERRIT_SITE_PATH="/custom/gerrit-site"' "$runtime_dir/helper-envs/gerrit-target/gerrit.env"
grep -Fq 'GERRIT_STAGED_ARTIFACT_DIR="/custom/staging/gerrit"' "$runtime_dir/helper-envs/gerrit-target/gerrit.env"
grep -Fq 'GERRIT_EVIDENCE_DIR="/custom/evidence/gerrit"' "$runtime_dir/helper-envs/gerrit-target/gerrit.env"
grep -Fq 'GERRIT_LOG_DIR="/custom/logs/gerrit"' "$runtime_dir/helper-envs/gerrit-target/gerrit.env"
grep -Fq 'JENKINS_HOME="/custom/jenkins-home"' "$runtime_dir/helper-envs/jenkins-controller-target/jenkins-controller.env"
grep -Fq 'JENKINS_STAGED_ARTIFACT_DIR="/custom/staging/jenkins"' "$runtime_dir/helper-envs/jenkins-controller-target/jenkins-controller.env"
grep -Fq 'JENKINS_EVIDENCE_DIR="/custom/evidence/jenkins"' "$runtime_dir/helper-envs/jenkins-controller-target/jenkins-controller.env"
grep -Fq 'JENKINS_LOG_DIR="/custom/logs/jenkins"' "$runtime_dir/helper-envs/jenkins-controller-target/jenkins-controller.env"
grep -Fq 'JENKINS_AGENT_REMOTE_FS="/custom/jenkins-agent-home"' "$runtime_dir/helper-envs/jenkins-agent-target/jenkins-agent.env"
grep -Fq 'JENKINS_AGENT_STATE_DIR="/custom/jenkins-agent-state"' "$runtime_dir/helper-envs/jenkins-agent-target/jenkins-agent.env"
grep -Fq 'JENKINS_AGENT_STAGED_ARTIFACT_DIR="/custom/staging/jenkins-agent"' "$runtime_dir/helper-envs/jenkins-agent-target/jenkins-agent.env"
grep -Fq 'JENKINS_AGENT_EVIDENCE_DIR="/custom/evidence/jenkins-agent"' "$runtime_dir/helper-envs/jenkins-agent-target/jenkins-agent.env"
grep -Fq 'JENKINS_AGENT_LOG_DIR="/custom/logs/jenkins-agent"' "$runtime_dir/helper-envs/jenkins-agent-target/jenkins-agent.env"
if grep -R --include='*.env' -Fq 'HARNESS_LDAP_BIND_PASSWORD=' "$runtime_dir"; then
  printf 'Runtime input/helper env files must not store the LDAP bind password\n' >&2
  exit 1
fi
if grep -Fq '/harness/evidence' \
  "$runtime_dir/helper-envs/gerrit-target/gerrit.env" \
  "$runtime_dir/helper-envs/jenkins-controller-target/jenkins-controller.env" \
  "$runtime_dir/helper-envs/jenkins-agent-target/jenkins-agent.env"
then
  printf 'Target rendered envs must not expose /harness/evidence\n' >&2
  exit 1
fi
if grep -Fq '/harness/logs' \
  "$runtime_dir/helper-envs/gerrit-target/gerrit.env" \
  "$runtime_dir/helper-envs/jenkins-controller-target/jenkins-controller.env" \
  "$runtime_dir/helper-envs/jenkins-agent-target/jenkins-agent.env"
then
  printf 'Target rendered envs must not expose /harness/logs\n' >&2
  exit 1
fi
if grep -R -Fq 'mutated-after-render' \
  "$runtime_dir"
then
  printf 'Rendered helper envs used mutated original operator env files\n' >&2
  exit 1
fi
