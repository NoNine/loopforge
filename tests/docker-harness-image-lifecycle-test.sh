#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
fake_bin="$tmp_dir/bin"
run_id="image-lifecycle-$$"
run_dir="$repo_root/generated/simulation/docker/$run_id"
calls="$tmp_dir/docker-calls.log"
containers="$tmp_dir/containers.tsv"
networks="$tmp_dir/networks.tsv"
images="$tmp_dir/images.tsv"
trap 'rm -rf "$tmp_dir" "$run_dir"' EXIT

mkdir -p "$fake_bin"
cat >"$fake_bin/docker" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$DOCKER_CALLS_LOG"
require_selected_filters() {
  case "$*" in
    *"label=org.loopforge.resource=docker-simulation"*\
*"label=org.loopforge.project=$HARNESS_PROJECT_NAME"*\
*"label=org.loopforge.run-id=$HARNESS_RUN_ID"*)
      return 0
      ;;
  esac
  printf 'foreign-resource\n'
  return 1
}
query_service() {
  local service
  service=""
  case "$*" in
    *"label=org.loopforge.service=bundle-factory"*) service=bundle-factory ;;
    *"label=org.loopforge.service=ldap"*) service=ldap ;;
    *"label=org.loopforge.service=gerrit-target"*) service=gerrit-target ;;
    *"label=org.loopforge.service=jenkins-controller-target"*) service=jenkins-controller-target ;;
    *"label=org.loopforge.service=jenkins-agent-target"*) service=jenkins-agent-target ;;
    *) printf 'foreign-service\n'; return 1 ;;
  esac
  printf '%s\n' "$service"
}
case "$*" in
  ps\ -a\ -q\ --filter*)
    require_selected_filters "$@" >/dev/null || exit 0
    service="$(query_service "$@")" || exit 0
    awk -F '\t' -v service="$service" '$2 == service { print $1 }' "$DOCKER_CONTAINERS_FILE"
    ;;
  network\ ls\ -q\ --filter*)
    require_selected_filters "$@" >/dev/null || exit 0
    case "$*" in
      *"label=org.loopforge.network=harness"*) ;;
      *) printf 'foreign-network\n'; exit 0 ;;
    esac
    awk -F '\t' '$2 == "harness" { print $1 }' "$DOCKER_NETWORKS_FILE"
    ;;
  images\ -q\ --filter*)
    require_selected_filters "$@" >/dev/null || exit 0
    service="$(query_service "$@")" || exit 0
    awk -F '\t' -v service="$service" '$2 == service { print $1 }' "$DOCKER_IMAGES_FILE"
    ;;
  rm\ -f\ *)
    target="${*:3}"
    case "$target" in
      foreign-*)
        printf 'foreign container must not be removed: %s\n' "$target" >&2
        exit 42
        ;;
    esac
    printf 'removed container %s\n' "$target"
    awk -F '\t' -v target="$target" '$1 != target' "$DOCKER_CONTAINERS_FILE" >"$DOCKER_CONTAINERS_FILE.tmp"
    mv "$DOCKER_CONTAINERS_FILE.tmp" "$DOCKER_CONTAINERS_FILE"
    ;;
  network\ rm\ *)
    target="${*:3}"
    case "$target" in
      foreign-*)
        printf 'foreign network must not be removed: %s\n' "$target" >&2
        exit 42
        ;;
    esac
    printf 'removed network %s\n' "$target"
    awk -F '\t' -v target="$target" '$1 != target' "$DOCKER_NETWORKS_FILE" >"$DOCKER_NETWORKS_FILE.tmp"
    mv "$DOCKER_NETWORKS_FILE.tmp" "$DOCKER_NETWORKS_FILE"
    ;;
  image\ rm\ *)
    target="${*:3}"
    case "$target" in
      ubuntu:24.04|osixia/openldap:1.5.0|foreign-*)
        printf 'base image must not be removed: %s\n' "$target" >&2
        exit 42
        ;;
    esac
    printf 'removed %s\n' "$target"
    awk -F '\t' -v target="$target" '$1 != target' "$DOCKER_IMAGES_FILE" >"$DOCKER_IMAGES_FILE.tmp"
    mv "$DOCKER_IMAGES_FILE.tmp" "$DOCKER_IMAGES_FILE"
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

reset_docker_state() {
  cat >"$containers" <<EOF_CONTAINERS
c-bundle-factory	bundle-factory
c-ldap	ldap
c-gerrit-target	gerrit-target
c-jenkins-controller-target	jenkins-controller-target
c-jenkins-agent-target	jenkins-agent-target
foreign-container	bundle-factory-foreign
EOF_CONTAINERS
  cat >"$networks" <<EOF_NETWORKS
n-harness	harness
foreign-network	harness-foreign
EOF_NETWORKS
  cat >"$images" <<EOF_IMAGES
i-bundle-factory	bundle-factory
i-ldap	ldap
i-gerrit-target	gerrit-target
i-jenkins-controller-target	jenkins-controller-target
i-jenkins-agent-target	jenkins-agent-target
ubuntu:24.04	base
osixia/openldap:1.5.0	base
foreign-image	bundle-factory-foreign
EOF_IMAGES
}

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
  DOCKER_NETWORKS_FILE="$networks" \
  DOCKER_IMAGES_FILE="$images" \
  "$repo_root/simulation/docker/simulate.sh" --env "$tmp_dir/harness.env" init-run >/dev/null

reset_docker_state
PATH="$fake_bin:$PATH" \
  DOCKER_CALLS_LOG="$calls" \
  DOCKER_CONTAINERS_FILE="$containers" \
  DOCKER_NETWORKS_FILE="$networks" \
  DOCKER_IMAGES_FILE="$images" \
  "$repo_root/simulation/docker/simulate.sh" --env "$tmp_dir/harness.env" destroy >"$tmp_dir/destroy.out"

grep -Fq 'destroy: ok containers-removed=5 networks-removed=1 images-removed=5' "$tmp_dir/destroy.out"
grep -Fq 'rm -f c-bundle-factory' "$calls"
grep -Fq 'network rm n-harness' "$calls"
grep -Fq 'image rm i-bundle-factory' "$calls"
grep -Fq 'image rm i-ldap' "$calls"
if grep -Eq 'image rm (ubuntu:24\.04|osixia/openldap:1\.5\.0)' "$calls"; then
  printf 'destroy must not remove configured base images\n' >&2
  exit 1
fi
if grep -Eq 'rm -f foreign-|network rm foreign-|image rm foreign-' "$calls"; then
  printf 'destroy must not remove foreign Docker resources\n' >&2
  exit 1
fi
[ -f "$run_dir/host/rendered/harness.runtime.env" ] || {
  printf 'destroy must not remove generated runtime config\n' >&2
  exit 1
}

rm -f "$calls"
rm -rf "$run_dir"
reset_docker_state
PATH="$fake_bin:$PATH" \
  DOCKER_CALLS_LOG="$calls" \
  DOCKER_CONTAINERS_FILE="$containers" \
  DOCKER_NETWORKS_FILE="$networks" \
  DOCKER_IMAGES_FILE="$images" \
  "$repo_root/simulation/docker/simulate.sh" --env "$tmp_dir/harness.env" destroy >"$tmp_dir/destroy-recovery.out"
grep -Fq 'destroy: ok containers-removed=5 networks-removed=1 images-removed=5' "$tmp_dir/destroy-recovery.out"
