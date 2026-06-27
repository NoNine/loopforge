#!/usr/bin/env bash
# shellcheck disable=SC2016

set -euo pipefail

repo_root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"

for path in \
  simulation/docker/compose.yaml \
  simulation/docker/ldap/Dockerfile \
  simulation/docker/ldap/50-harness-seed.ldif \
  simulation/docker/target/Dockerfile \
  simulation/docker/scripts/harness-sleep.sh \
  simulation/docker/examples/docker.env.example
do
  [ -f "$repo_root/$path" ] || {
    printf 'Missing Docker simulation asset at %s\n' "$path" >&2
    exit 1
  }
done

[ ! -e "$repo_root/simulation/docker/harness/README.md" ] || {
  printf 'Nested harness README should be removed after README merge\n' >&2
  exit 1
}
[ ! -e "$repo_root/simulation/docker/harness/examples/harness.env.example" ] || {
  printf 'Old harness env example path should be removed\n' >&2
  exit 1
}

grep -Fq -- '--home-dir /srv/gerrit' "$repo_root/simulation/docker/target/Dockerfile" || {
  printf 'Docker target image must create Gerrit with native home /srv/gerrit\n' >&2
  exit 1
}
grep -Fq -- '--home-dir /var/lib/jenkins' "$repo_root/simulation/docker/target/Dockerfile" || {
  printf 'Docker target image must create Jenkins with native home /var/lib/jenkins\n' >&2
  exit 1
}
grep -Fq -- '--home-dir /var/lib/jenkins-agent' "$repo_root/simulation/docker/target/Dockerfile" || {
  printf 'Docker target image must create Jenkins agent with native home /var/lib/jenkins-agent\n' >&2
  exit 1
}
grep -Fq -- 'groupadd --system ci-operator' "$repo_root/simulation/docker/target/Dockerfile" || {
  printf 'Docker target image must include a distinct ci-operator group\n' >&2
  exit 1
}
grep -Fq -- '--gid ci-operator --home-dir /home/ci-operator --shell /bin/bash ci-operator' "$repo_root/simulation/docker/target/Dockerfile" || {
  printf 'Docker target image must include a distinct ci-operator account\n' >&2
  exit 1
}
grep -Fq -- "sudo \\" "$repo_root/simulation/docker/target/Dockerfile" || {
  printf 'Docker target image must install sudo for the ci-operator account\n' >&2
  exit 1
}
grep -Fq -- "/etc/sudoers.d/harness-ci-operator" "$repo_root/simulation/docker/target/Dockerfile" || {
  printf 'Docker target image must configure ci-operator sudo through a named sudoers drop-in\n' >&2
  exit 1
}
grep -Fq -- "ci-operator ALL=(ALL) NOPASSWD:ALL" "$repo_root/simulation/docker/target/Dockerfile" || {
  printf 'Docker target image must grant ci-operator passwordless sudo\n' >&2
  exit 1
}
grep -Fq -- "chmod 0440 /etc/sudoers.d/harness-ci-operator" "$repo_root/simulation/docker/target/Dockerfile" || {
  printf 'ci-operator sudoers drop-in must be mode 0440\n' >&2
  exit 1
}
if grep -F -- '--home-dir /home/ci-operator' "$repo_root/simulation/docker/target/Dockerfile" |
  grep -Eq 'gerrit|jenkins|jenkins-agent'; then
  printf 'ci-operator account must not be a product runtime account\n' >&2
  exit 1
fi
grep -Fq -- 'http://mirrors.tuna.tsinghua.edu.cn/ubuntu/' "$repo_root/simulation/docker/target/Dockerfile" || {
  printf 'Docker target image must use the Tsinghua Ubuntu apt mirror\n' >&2
  exit 1
}
grep -Fq -- '/etc/apt/sources.list.d/ubuntu.sources' "$repo_root/simulation/docker/target/Dockerfile" || {
  printf 'Docker target image must rewrite Ubuntu 24.04 deb822 apt sources\n' >&2
  exit 1
}
grep -Fq -- 'http://archive.ubuntu.com/ubuntu/' "$repo_root/simulation/docker/target/Dockerfile" || {
  printf 'Docker target image must rewrite archive.ubuntu.com apt source URL\n' >&2
  exit 1
}
grep -Fq -- 'http://security.ubuntu.com/ubuntu/' "$repo_root/simulation/docker/target/Dockerfile" || {
  printf 'Docker target image must rewrite security.ubuntu.com apt source URL\n' >&2
  exit 1
}
if grep -Fq -- 'wget -q --show-progress=off' "$repo_root/scripts/gerrit-setup.sh" ||
  grep -Fq -- 'wget -q --show-progress=off' "$repo_root/scripts/jenkins-controller-setup.sh"; then
  printf 'Docker helper downloads must use wget -nv instead of silent wget\n' >&2
  exit 1
fi
grep -Fq -- 'wget -nv --show-progress=off' "$repo_root/scripts/gerrit-setup.sh" || {
  printf 'Gerrit helper must use wget -nv for minimal download logs\n' >&2
  exit 1
}
grep -Fq -- 'wget -nv --show-progress=off' "$repo_root/scripts/jenkins-controller-setup.sh" || {
  printf 'Jenkins controller helper must use wget -nv for minimal download logs\n' >&2
  exit 1
}

grep -Fxq -- 'version: "2"' "$repo_root/simulation/docker/compose.yaml" || {
  printf 'Docker compose must declare legacy-compatible Compose file version 2\n' >&2
  exit 1
}
grep -Fxq -- 'services:' "$repo_root/simulation/docker/compose.yaml" || {
  printf 'Docker compose must keep top-level services for Compose v2 format\n' >&2
  exit 1
}
grep -Fxq -- 'networks:' "$repo_root/simulation/docker/compose.yaml" || {
  printf 'Docker compose must keep top-level networks for Compose v2 format\n' >&2
  exit 1
}
if grep -Eq '^[[:space:]]+name: "\$\{HARNESS_PROJECT_NAME\}-network"$' "$repo_root/simulation/docker/compose.yaml"; then
  printf 'Docker compose must not use custom network name unsupported by legacy docker-compose v1\n' >&2
  exit 1
fi
for service in bundle-factory gerrit-target jenkins-controller-target jenkins-agent-target; do
  awk -v service="$service" '
    $0 == "  " service ":" { in_service=1; next }
    in_service && /^  [A-Za-z0-9_-]+:/ { exit !found }
    in_service && $0 == "    init: true" { found=1 }
    END { if (in_service) exit !found }
  ' "$repo_root/simulation/docker/compose.yaml" || {
    printf 'Docker compose service %s must enable init: true to reap helper child processes\n' "$service" >&2
    exit 1
  }
done

grep -Fq -- '${HARNESS_PRODUCT_HOME_DIR}/gerrit:/srv/gerrit' "$repo_root/simulation/docker/compose.yaml" || {
  printf 'Docker compose must mount Gerrit product home from HARNESS_PRODUCT_HOME_DIR\n' >&2
  exit 1
}
if grep -Eq 'HARNESS_OPERATOR_(UID|GID)' "$repo_root/simulation/docker/compose.yaml" "$repo_root/simulation/docker/target/Dockerfile" "$repo_root/simulation/docker/simulate.sh"; then
  printf 'Docker simulation must not map target ci-operator to the host operator UID/GID\n' >&2
  exit 1
fi
grep -Fq -- '${HARNESS_PRODUCT_HOME_DIR}/jenkins-controller:/var/lib/jenkins' "$repo_root/simulation/docker/compose.yaml" || {
  printf 'Docker compose must mount Jenkins product home from HARNESS_PRODUCT_HOME_DIR\n' >&2
  exit 1
}
grep -Fq -- '${HARNESS_PRODUCT_HOME_DIR}/jenkins-agent:/var/lib/jenkins-agent' "$repo_root/simulation/docker/compose.yaml" || {
  printf 'Docker compose must mount Jenkins agent remote FS from HARNESS_PRODUCT_HOME_DIR\n' >&2
  exit 1
}
grep -Fq -- '${HARNESS_STATE_DIR}/gerrit:/var/lib/loopforge' "$repo_root/simulation/docker/compose.yaml" || {
  printf 'Docker compose must mount Gerrit helper state at /var/lib/loopforge\n' >&2
  exit 1
}
grep -Fq -- '${HARNESS_STATE_DIR}/jenkins-controller:/var/lib/loopforge' "$repo_root/simulation/docker/compose.yaml" || {
  printf 'Docker compose must mount Jenkins helper state at /var/lib/loopforge\n' >&2
  exit 1
}
grep -Fq -- '${HARNESS_STATE_DIR}/jenkins-agent:/var/lib/loopforge' "$repo_root/simulation/docker/compose.yaml" || {
  printf 'Docker compose must mount agent helper state at /var/lib/loopforge\n' >&2
  exit 1
}
grep -Fq -- '${HARNESS_LOG_DIR}:/var/log/loopforge' "$repo_root/simulation/docker/compose.yaml" || {
  printf 'Docker compose must mount helper logs at /var/log/loopforge\n' >&2
  exit 1
}
grep -Fq -- 'HARNESS_STATE_DIR: "/var/lib/loopforge"' "$repo_root/simulation/docker/compose.yaml" || {
  printf 'Docker compose must expose helper state at /var/lib/loopforge\n' >&2
  exit 1
}
grep -Fq -- 'HARNESS_LOG_DIR: "/var/log/loopforge"' "$repo_root/simulation/docker/compose.yaml" || {
  printf 'Docker compose must expose helper logs at /var/log/loopforge\n' >&2
  exit 1
}
if grep -Eq '\$\{HARNESS_STATE_DIR\}/(gerrit|jenkins-controller|jenkins-agent):/harness/state' "$repo_root/simulation/docker/compose.yaml"; then
  printf 'Docker target helper state/log mounts must not expose /harness paths\n' >&2
  exit 1
fi
if grep -Eq ':/harness/(state|evidence|logs)' "$repo_root/simulation/docker/compose.yaml"; then
  printf 'Docker compose must not mount legacy /harness sideband paths\n' >&2
  exit 1
fi
if grep -Eq '\$\{HARNESS_STATE_DIR\}/[^:]*:(/srv/gerrit|/var/lib/jenkins|/var/lib/jenkins-agent)' "$repo_root/simulation/docker/compose.yaml"; then
  printf 'Product homes must not be backed by HARNESS_STATE_DIR paths\n' >&2
  exit 1
fi
if grep -Eq '\$\{HARNESS_STAGING_DIR\}/[^:]*:/opt/' "$repo_root/simulation/docker/compose.yaml"; then
  printf 'Target artifact bundles must not be host bind-mounted under /opt\n' >&2
  exit 1
fi
grep -Fq -- '${HARNESS_STATE_DIR}/bundle-factory/rendered:/var/lib/loopforge/rendered' "$repo_root/simulation/docker/compose.yaml" || {
  printf 'Bundle-factory rendered inputs must be host-backed under state for debugging\n' >&2
  exit 1
}
grep -Fq -- '${HARNESS_STATE_DIR}/bundle-factory/evidence:/var/lib/loopforge/evidence' "$repo_root/simulation/docker/compose.yaml" || {
  printf 'Bundle-factory evidence must be host-backed under state for debugging\n' >&2
  exit 1
}
grep -Fq -- '${HARNESS_STATE_DIR}/bundle-factory/artifact-bundle-work:/var/lib/loopforge/artifact-bundle-work' "$repo_root/simulation/docker/compose.yaml" || {
  printf 'Bundle-factory artifact workspace must be host-backed under state for debugging\n' >&2
  exit 1
}
if grep -Eq '\$\{HARNESS_PRODUCT_HOME_DIR\}/bundle-factory[^:]*:/var/lib/loopforge' "$repo_root/simulation/docker/compose.yaml"; then
  printf 'Bundle-factory helper state must not be backed by product-homes\n' >&2
  exit 1
fi
for path in \
  '$HARNESS_STATE_DIR/bundle-factory/rendered' \
  '$HARNESS_STATE_DIR/bundle-factory/evidence' \
  '$HARNESS_STATE_DIR/bundle-factory/artifact-bundle-work'
do
  grep -Fq -- "$path" "$repo_root/simulation/docker/simulate.sh" || {
    printf 'Docker harness must create bundle-factory debug backing directory %s\n' "$path" >&2
    exit 1
  }
done

grep -Fq -- 'prepare_product_home_ownership' "$repo_root/simulation/docker/simulate.sh" || {
  printf 'Docker harness must prepare product home ownership inside target containers\n' >&2
  exit 1
}
grep -Fq -- 'prepare_bundle_factory_workspace_ownership' "$repo_root/simulation/docker/simulate.sh" || {
  printf 'Docker harness must prepare bundle-factory workspace ownership\n' >&2
  exit 1
}
grep -Fq -- 'prepare_target_helper_owned_paths' "$repo_root/simulation/docker/simulate.sh" || {
  printf 'Docker harness must prepare target helper-owned path ownership\n' >&2
  exit 1
}
grep -Fq -- 'if ! prepare_all_target_helper_owned_paths "$log" ||' "$repo_root/simulation/docker/simulate.sh" || {
  printf 'Docker harness up must prepare target helper-owned paths\n' >&2
  exit 1
}
grep -Fq -- 'retained_evidence_logs=host-owned-sideband' "$repo_root/simulation/docker/simulate.sh" || {
  printf 'Docker harness must keep retained evidence/log bind roots host-owned sideband\n' >&2
  exit 1
}
if grep -Eq 'owned_directory_command ci-operator ci-operator [0-9]+ "\\$(evidence_root|log_root)"' "$repo_root/simulation/docker/simulate.sh"; then
  printf 'Docker harness must not chown retained evidence/log bind roots to target ci-operator\n' >&2
  exit 1
fi
grep -Fq -- 'if ! prepare_bundle_factory_workspace_ownership "$role" "$log"; then' "$repo_root/simulation/docker/simulate.sh" || {
  printf 'Docker harness must fail closed when bundle-factory workspace prep fails\n' >&2
  exit 1
}
if grep -Fq -- 'owned_directory_command()' "$repo_root/scripts/common.sh"; then
  printf 'scripts/common.sh must not contain Docker harness-only ownership helpers\n' >&2
  exit 1
fi
grep -Fq -- 'owned_directory_command()' "$repo_root/simulation/docker/simulate.sh" || {
  printf 'Docker harness must own its local directory ownership command construction\n' >&2
  exit 1
}
grep -Fq -- 'owned_directory_command "$account" "$group"' "$repo_root/simulation/docker/simulate.sh" || {
  printf 'Docker harness product home preparation must use local ownership helper\n' >&2
  exit 1
}
grep -Fq -- 'bundle_factory_artifact_export' "$repo_root/simulation/docker/simulate.sh" || {
  printf 'Docker harness must explicitly export bundle-factory artifacts to host\n' >&2
  exit 1
}
grep -Fq -- '/var/lib/loopforge/rendered' "$repo_root/simulation/docker/simulate.sh" || {
  printf 'Docker harness must prepare bundle-factory rendered input directory\n' >&2
  exit 1
}
grep -Fq -- 'compose exec -T -u ci-operator "$service" "/workspace/$helper"' "$repo_root/simulation/docker/simulate.sh" || {
  printf 'Docker harness must run bundle-factory helper operations as ci-operator\n' >&2
  exit 1
}
grep -Fq -- 'transfer_mode=docker-cp-waiver' "$repo_root/simulation/docker/simulate.sh" || {
  printf 'Docker harness must label Docker cp transfers as simulation-only waivers\n' >&2
  exit 1
}
grep -Fq -- 'stage_rendered_env_file "$service" "$host_env_file" "$container_env_file" ci-operator ci-operator "$log"' "$repo_root/simulation/docker/simulate.sh" || {
  printf 'Docker harness target env staging must use ci-operator ownership\n' >&2
  exit 1
}
grep -Fq -- 'docker_cp_file_to_service "$archive" "$service" "$container_archive" ci-operator ci-operator 0644 "$log"' "$repo_root/simulation/docker/simulate.sh" || {
  printf 'Docker harness artifact archive staging must use ci-operator ownership\n' >&2
  exit 1
}
grep -Fq -- 'docker_cp_file_to_service "$checksum" "$service" "$container_checksum" ci-operator ci-operator 0644 "$log"' "$repo_root/simulation/docker/simulate.sh" || {
  printf 'Docker harness artifact checksum staging must use ci-operator ownership\n' >&2
  exit 1
}
