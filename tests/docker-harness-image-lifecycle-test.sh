#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
fake_bin="$tmp_dir/bin"
run_id="image-lifecycle-$$"
run_dir="$repo_root/generated/simulation/docker/$run_id"
calls="$tmp_dir/docker-calls.log"
containers="$tmp_dir/containers"
trap 'rm -rf "$tmp_dir" "$run_dir"' EXIT

mkdir -p "$fake_bin"
cat >"$fake_bin/docker" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$DOCKER_CALLS_LOG"
case "$*" in
  *"compose version"*) printf 'Docker Compose version v2.0.0\n' ;;
  ps\ -a\ --format*)
    [ -f "$DOCKER_CONTAINERS_FILE" ] && cat "$DOCKER_CONTAINERS_FILE"
    ;;
  image\ inspect\ *)
    [ "${DOCKER_NO_IMAGE_REFS:-0}" = 0 ] || exit 1
    ref="${*:3}"
    case "$ref" in
      "$HARNESS_PROJECT_NAME-bundle-factory"|"$HARNESS_PROJECT_NAME-gerrit-target"|"$HARNESS_PROJECT_NAME-jenkins-controller-target"|"$HARNESS_PROJECT_NAME-jenkins-agent-target"|"$HARNESS_PROJECT_NAME-ldap")
        printf '[{"Id":"id-%s"}]\n' "$ref"
        ;;
      "$HARNESS_PROJECT_NAME"_*)
        exit 1
        ;;
      *)
        exit 1
        ;;
    esac
    ;;
  images\ -q\ --filter*)
    printf '%s\n' "sha256:labelled-project-image"
    ;;
  image\ rm\ *)
    target="${*:3}"
    case "$target" in
      ubuntu:24.04|osixia/openldap:1.5.0)
        printf 'base image must not be removed: %s\n' "$target" >&2
        exit 42
        ;;
    esac
    printf 'removed %s\n' "$target"
    ;;
  compose*)
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
SH
chmod +x "$fake_bin/docker"

cat >"$tmp_dir/harness.env" <<EOF
HARNESS_MODE=docker-simulation
HARNESS_RUN_ID=$run_id
HARNESS_PROJECT_NAME=$run_id
HARNESS_UBUNTU_IMAGE=ubuntu:24.04
HARNESS_LDAP_IMAGE=osixia/openldap:1.5.0
HARNESS_GERRIT_ENV_FILE=examples/gerrit.env.example
HARNESS_JENKINS_CONTROLLER_ENV_FILE=examples/jenkins-controller.env.example
HARNESS_JENKINS_AGENT_ENV_FILE=examples/jenkins-agent.env.example
HARNESS_INTEGRATION_ENV_FILE=examples/integration.env.example
EOF

grep -Fq 'org.loopforge.resource="${LOOPFORGE_RESOURCE}"' "$repo_root/simulation/docker/target/Dockerfile"
grep -Fq 'org.loopforge.service="${LOOPFORGE_SERVICE}"' "$repo_root/simulation/docker/target/Dockerfile"
grep -Fq 'org.loopforge.resource="${LOOPFORGE_RESOURCE}"' "$repo_root/simulation/docker/ldap/Dockerfile"
grep -Fq 'LOOPFORGE_PROJECT: "${HARNESS_PROJECT_NAME}"' "$repo_root/simulation/docker/compose.yaml"
for service in bundle-factory ldap gerrit-target jenkins-controller-target jenkins-agent-target; do
  grep -Fq "LOOPFORGE_SERVICE: \"$service\"" "$repo_root/simulation/docker/compose.yaml"
  grep -Fq "org.loopforge.service: \"$service\"" "$repo_root/simulation/docker/compose.yaml"
done
grep -Fq 'org.loopforge.network: "harness"' "$repo_root/simulation/docker/compose.yaml"

PATH="$fake_bin:$PATH" \
  DOCKER_CALLS_LOG="$calls" \
  DOCKER_CONTAINERS_FILE="$containers" \
  "$repo_root/simulation/docker/simulate.sh" --env "$tmp_dir/harness.env" init-run >/dev/null

PATH="$fake_bin:$PATH" \
  DOCKER_CALLS_LOG="$calls" \
  DOCKER_CONTAINERS_FILE="$containers" \
  "$repo_root/simulation/docker/simulate.sh" --env "$tmp_dir/harness.env" destroy >"$tmp_dir/destroy.out"

grep -Fq 'destroy: ok images-removed=5' "$tmp_dir/destroy.out"
grep -Fq "image rm $run_id-bundle-factory" "$calls"
grep -Fq "image rm $run_id-ldap" "$calls"
if grep -Fq "image rm sha256:labelled-project-image" "$calls"; then
  printf 'destroy must not remove a duplicate labelled ID when project image names exist\n' >&2
  exit 1
fi
if grep -Eq 'image rm (ubuntu:24\.04|osixia/openldap:1\.5\.0)' "$calls"; then
  printf 'destroy must not remove configured base images\n' >&2
  exit 1
fi
[ -f "$run_dir/host/rendered/harness.runtime.env" ] || {
  printf 'destroy must not remove generated runtime config\n' >&2
  exit 1
}

rm -f "$calls"
PATH="$fake_bin:$PATH" \
  DOCKER_CALLS_LOG="$calls" \
  DOCKER_CONTAINERS_FILE="$containers" \
  DOCKER_NO_IMAGE_REFS=1 \
  "$repo_root/simulation/docker/simulate.sh" --env "$tmp_dir/harness.env" destroy >"$tmp_dir/destroy-label-fallback.out"
grep -Fq 'destroy: ok images-removed=1' "$tmp_dir/destroy-label-fallback.out"
grep -Fq "image rm sha256:labelled-project-image" "$calls"

printf '%s-bundle-factory\n' "$run_id" >"$containers"
set +e
PATH="$fake_bin:$PATH" \
  DOCKER_CALLS_LOG="$calls" \
  DOCKER_CONTAINERS_FILE="$containers" \
  "$repo_root/simulation/docker/simulate.sh" --env "$tmp_dir/harness.env" destroy >"$tmp_dir/destroy-with-containers.out" 2>&1
rc=$?
set -e
[ "$rc" -ne 0 ] || {
  printf 'destroy should fail while selected containers exist\n' >&2
  exit 1
}
grep -Fq 'Selected Docker simulation containers still exist; run down before destroy' "$tmp_dir/destroy-with-containers.out"
