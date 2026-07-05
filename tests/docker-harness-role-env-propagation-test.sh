#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
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

grep -Fq -- '/home/ci-operator/loopforge-inputs/bundle-factory/gerrit-bundle-factory.env' "$repo_root/simulation/docker/simulate.sh"
grep -Fq -- '/home/ci-operator/loopforge-inputs/bundle-factory/jenkins-controller-bundle-factory.env' "$repo_root/simulation/docker/simulate.sh"
grep -Fq -- '/home/ci-operator/loopforge-inputs/bundle-factory/%s.env' "$repo_root/simulation/docker/simulate.sh"
grep -Fq -- '/home/ci-operator/loopforge-inputs/%s.env' "$repo_root/simulation/docker/simulate.sh"
grep -Fq -- 'transfer_mode=docker-cp-input-waiver' "$repo_root/simulation/docker/simulate.sh"
if grep -Fq -- '/var/lib/loopforge/rendered' "$repo_root/simulation/docker/simulate.sh"; then
  printf 'Docker harness must not stage helper env files under Loopforge rendered state\n' >&2
  exit 1
fi

grep -Fq 'GERRIT_SENTINEL=original' "$runtime_dir/gerrit.env"
grep -Fq 'JENKINS_CONTROLLER_SENTINEL=original' "$runtime_dir/jenkins-controller.env"
grep -Fq 'JENKINS_AGENT_SENTINEL=original' "$runtime_dir/jenkins-agent.env"
grep -Fq 'GERRIT_DOWNLOAD_ARTIFACTS="1"' "$runtime_dir/helper-envs/bundle-factory/gerrit-bundle-factory.env"
grep -Fq 'GERRIT_ARTIFACT_OUTPUT_DIR="/var/lib/loopforge/preparing/gerrit-artifacts-bundle/gerrit"' "$runtime_dir/helper-envs/bundle-factory/gerrit-bundle-factory.env"
grep -Fq 'JENKINS_DOWNLOAD_ARTIFACTS="1"' "$runtime_dir/helper-envs/bundle-factory/jenkins-controller-bundle-factory.env"
grep -Fq 'JENKINS_ARTIFACT_OUTPUT_DIR="/var/lib/loopforge/preparing/jenkins-artifacts-bundle/jenkins"' "$runtime_dir/helper-envs/bundle-factory/jenkins-controller-bundle-factory.env"
grep -Fq 'JENKINS_AGENT_ARTIFACT_OUTPUT_DIR="/var/lib/loopforge/preparing/jenkins-agent-artifacts-bundle/jenkins-agent"' "$runtime_dir/helper-envs/bundle-factory/jenkins-agent.env"
grep -Fq 'GERRIT_SENTINEL=original' "$runtime_dir/helper-envs/gerrit-target/gerrit.env"
grep -Fq 'JENKINS_CONTROLLER_SENTINEL=original' "$runtime_dir/helper-envs/jenkins-controller-target/jenkins-controller.env"
grep -Fq 'JENKINS_AGENT_SENTINEL=original' "$runtime_dir/helper-envs/jenkins-agent-target/jenkins-agent.env"
grep -Fq 'GERRIT_SITE_PATH="/srv/gerrit"' "$runtime_dir/helper-envs/gerrit-target/gerrit.env"
grep -Fq 'GERRIT_STAGED_ARTIFACT_DIR="/var/lib/loopforge/staging/gerrit"' "$runtime_dir/helper-envs/gerrit-target/gerrit.env"
grep -Fq 'GERRIT_EVIDENCE_DIR="/var/lib/loopforge/evidence"' "$runtime_dir/helper-envs/gerrit-target/gerrit.env"
grep -Fq 'GERRIT_LOG_DIR="/var/log/loopforge"' "$runtime_dir/helper-envs/gerrit-target/gerrit.env"
grep -Fq 'JENKINS_HOME="/var/lib/jenkins"' "$runtime_dir/helper-envs/jenkins-controller-target/jenkins-controller.env"
grep -Fq 'JENKINS_STAGED_ARTIFACT_DIR="/var/lib/loopforge/staging/jenkins"' "$runtime_dir/helper-envs/jenkins-controller-target/jenkins-controller.env"
grep -Fq 'JENKINS_EVIDENCE_DIR="/var/lib/loopforge/evidence"' "$runtime_dir/helper-envs/jenkins-controller-target/jenkins-controller.env"
grep -Fq 'JENKINS_LOG_DIR="/var/log/loopforge"' "$runtime_dir/helper-envs/jenkins-controller-target/jenkins-controller.env"
grep -Fq 'JENKINS_AGENT_REMOTE_FS="/var/lib/jenkins-agent"' "$runtime_dir/helper-envs/jenkins-agent-target/jenkins-agent.env"
grep -Fq 'JENKINS_AGENT_STAGED_ARTIFACT_DIR="/var/lib/loopforge/staging/jenkins-agent"' "$runtime_dir/helper-envs/jenkins-agent-target/jenkins-agent.env"
grep -Fq 'JENKINS_AGENT_EVIDENCE_DIR="/var/lib/loopforge/evidence"' "$runtime_dir/helper-envs/jenkins-agent-target/jenkins-agent.env"
grep -Fq 'JENKINS_AGENT_LOG_DIR="/var/log/loopforge"' "$runtime_dir/helper-envs/jenkins-agent-target/jenkins-agent.env"
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
