#!/usr/bin/env bash
# shellcheck disable=SC2016

set -euo pipefail

repo_root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
docker_harness_sources=("$repo_root/simulation/docker/simulate.sh" "$repo_root/simulation/docker/lib/"*.sh)

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
grep -Fq -- 'groupadd --gid 61000 ci-operator' "$repo_root/simulation/docker/target/Dockerfile" || {
  printf 'Docker target image must include a distinct ci-operator group\n' >&2
  exit 1
}
grep -Fq -- '--uid 61000 --create-home --gid 61000 --home-dir /home/ci-operator --shell /bin/bash ci-operator' "$repo_root/simulation/docker/target/Dockerfile" || {
  printf 'Docker target image must include a distinct ci-operator account\n' >&2
  exit 1
}
for spec in \
  'groupadd --gid 61010 gerrit' \
  'useradd --uid 61010 --gid 61010 --home-dir /srv/gerrit --shell /bin/bash gerrit' \
  'groupadd --gid 61020 jenkins' \
  'useradd --uid 61020 --gid 61020 --home-dir /var/lib/jenkins --shell /bin/bash jenkins' \
  'groupadd --gid 61030 jenkins-agent' \
  'useradd --uid 61030 --gid 61030 --home-dir /var/lib/jenkins-agent --shell /bin/bash jenkins-agent'
do
  grep -Fq -- "$spec" "$repo_root/simulation/docker/target/Dockerfile" || {
    printf 'Docker target image must use deterministic account ID spec: %s\n' "$spec" >&2
    exit 1
  }
done
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
if grep -Fq -- 'uid=jenkins-gerrit' "$repo_root/simulation/docker/ldap/50-harness-seed.ldif"; then
  printf 'Docker LDAP seed must not create password-backed jenkins-gerrit\n' >&2
  exit 1
fi
if grep -Fq -- 'integration-password' "$repo_root/simulation/docker/ldap/50-harness-seed.ldif"; then
  printf 'Docker LDAP seed must not contain a jenkins-gerrit password\n' >&2
  exit 1
fi
grep -Fq -- "tree \\" "$repo_root/simulation/docker/target/Dockerfile" || {
  printf 'Docker target image must install tree for simulation-only inspection\n' >&2
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
if grep -Eq 'HARNESS_OPERATOR_(UID|GID)' "$repo_root/simulation/docker/compose.yaml" "$repo_root/simulation/docker/target/Dockerfile" "${docker_harness_sources[@]}"; then
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
if grep -Eq ':/var/lib/loopforge(/|$)|:/var/log/loopforge(/|$)' "$repo_root/simulation/docker/compose.yaml"; then
  printf 'Docker compose must not bind-mount container-visible Loopforge roots\n' >&2
  exit 1
fi
if grep -Eq '/var/lib/loopforge|/var/log/loopforge' "$repo_root/simulation/docker/scripts/harness-sleep.sh"; then
  printf 'Docker container entrypoint must not create helper-owned Loopforge roots\n' >&2
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
if grep -Fq -- 'prepare_product_home_ownership' "${docker_harness_sources[@]}" ||
  grep -Fq -- 'prepare_bundle_factory_workspace_ownership' "${docker_harness_sources[@]}" ||
  grep -Fq -- 'prepare_target_bind_mount_ownership' "${docker_harness_sources[@]}" ||
  grep -Fq -- 'prepare_all_target_bind_mount_ownership' "${docker_harness_sources[@]}" ||
  grep -Fq -- 'target_bind_mounts_prepared' "${docker_harness_sources[@]}" ||
  grep -Fq -- 'bundle_factory_bind_mount_prepared' "${docker_harness_sources[@]}"; then
  printf 'Docker harness must not own container-visible Loopforge/product ownership prep\n' >&2
  exit 1
fi
grep -Fq -- '.runtime-identity-pending' "$repo_root/simulation/docker/lib/config.sh" || {
  printf 'Fresh Docker runs must mark product homes for one-time identity initialization\n' >&2
  exit 1
}
grep -Fq -- 'initialize_or_validate_product_homes' "$repo_root/simulation/docker/lib/commands.sh" || {
  printf 'Docker up must initialize fresh homes and validate ownership on later starts\n' >&2
  exit 1
}
grep -Fq -- 'run explicit cleanup and use a fresh run' "$repo_root/simulation/docker/lib/commands.sh" || {
  printf 'Docker product-home ownership drift must require explicit cleanup\n' >&2
  exit 1
}
if grep -Fq -- '/var/lib/loopforge/rendered' "${docker_harness_sources[@]}"; then
  printf 'Docker harness must not stage helper env files under Loopforge rendered state\n' >&2
  exit 1
fi
if grep -Fq -- '/var/lib/loopforge/target-ssh' "${docker_harness_sources[@]}" ||
  grep -Fq -- '/var/lib/loopforge/target-ssh' "$repo_root/simulation/docker/scripts/harness-sleep.sh"; then
  printf 'Docker target SSH inputs must not use Loopforge helper state paths\n' >&2
  exit 1
fi
grep -Fq -- '/home/ci-operator/loopforge-inputs' "${docker_harness_sources[@]}" || {
  printf 'Docker harness must transfer helper env files to operator input custody\n' >&2
  exit 1
}
grep -Fq -- 'transfer_mode=docker-cp-input-waiver' "${docker_harness_sources[@]}" || {
  printf 'Docker harness must label helper env input transfers as simulation-only waivers\n' >&2
  exit 1
}
grep -Fq -- 'prepare-target-workspace' "${docker_harness_sources[@]}" || {
  printf 'Docker harness must invoke helper-owned target workspace preparation before staging artifacts\n' >&2
  exit 1
}
if grep -Fq -- 'owned_directory_command ci-operator ci-operator 0750 "$evidence_root" 1' "${docker_harness_sources[@]}" ||
  grep -Fq -- 'owned_directory_command ci-operator ci-operator 0750 "$log_root" 1' "${docker_harness_sources[@]}" ||
  grep -Fq -- 'owned_directory_command ci-operator ci-operator 0700 "$work_root" 1' "${docker_harness_sources[@]}"; then
  printf 'Docker harness must not recursively prepare helper-owned Loopforge dirs\n' >&2
  exit 1
fi
if grep -Fq -- 'secret_input_root' "${docker_harness_sources[@]}"; then
  printf 'Docker harness must not prepare LDAP secret input directories\n' >&2
  exit 1
fi
grep -Fq -- 'HARNESS_LDAP_BIND_PASSWORD="${HARNESS_LDAP_BIND_PASSWORD:-readonly-password}"' "${docker_harness_sources[@]}" || {
  printf 'Docker simulation must keep a fake LDAP bind password default for simulation-owned LDAP\n' >&2
  exit 1
}
grep -Fq -- 'HARNESS_LDAP_BIND_PASSWORD=$(shell_quote "$HARNESS_LDAP_BIND_PASSWORD")' "${docker_harness_sources[@]}" || {
  printf 'Docker runtime env files must preserve the simulation-owned LDAP bind password\n' >&2
  exit 1
}
grep -Fq -- 'HARNESS_LDAP_BIND_PASSWORD=readonly-password' "$repo_root/simulation/docker/examples/docker.env.example" || {
  printf 'Docker env example must document the fake simulation LDAP bind password\n' >&2
  exit 1
}
grep -Fq -- 'real organization LDAP secret' "$repo_root/simulation/docker/examples/docker.env.example" || {
  printf 'Docker env example must forbid real organization LDAP secrets\n' >&2
  exit 1
}
grep -Fq -- '/home/ci-operator/loopforge-inputs/target-ssh/ci-operator.pub' "${docker_harness_sources[@]}" || {
  printf 'Docker harness must stage target SSH public key through operator input custody\n' >&2
  exit 1
}
grep -Fq -- 'target_ssh_authorized_key_installed' "${docker_harness_sources[@]}" || {
  printf 'Docker harness must label target SSH authorized_keys installation\n' >&2
  exit 1
}
grep -Fq -- 'custody=docker-simulation-control-plane' "${docker_harness_sources[@]}" || {
  printf 'Docker target SSH public key staging must be labeled as simulation control-plane custody\n' >&2
  exit 1
}
grep -Fq -- 'compose_exec_with_ldap_password "$service" "$helper_path" --env "$role_env_file" --yes collect-evidence' "${docker_harness_sources[@]}" || {
  printf 'Gerrit collect-evidence must run as ci-operator\n' >&2
  exit 1
}
grep -Fq -- 'compose_exec_with_ldap_password "$service" "$helper_path" --env "$role_env_file" --yes install' "${docker_harness_sources[@]}" || {
  printf 'Gerrit install must run as ci-operator\n' >&2
  exit 1
}
grep -Fq -- 'compose_exec_with_ldap_password "$service" "$helper_path" --env "$role_env_file" --yes configure' "${docker_harness_sources[@]}" || {
  printf 'Gerrit configure must run as ci-operator\n' >&2
  exit 1
}
grep -Fq -- 'compose_exec_with_ldap_password "$service" "$helper_path" --env "$role_env_file" collect-evidence' "${docker_harness_sources[@]}" || {
  printf 'Jenkins controller collect-evidence must run as ci-operator\n' >&2
  exit 1
}
grep -Fq -- 'compose_exec_with_ldap_password "$service" "$helper_path" --env "$role_env_file" --yes install' "${docker_harness_sources[@]}" || {
  printf 'Jenkins controller install must run as ci-operator\n' >&2
  exit 1
}
grep -Fq -- 'compose_exec_with_ldap_password "$service" "$helper_path" --env "$role_env_file" --yes configure-service' "${docker_harness_sources[@]}" || {
  printf 'Jenkins controller configure-service must run as ci-operator\n' >&2
  exit 1
}
grep -Fq -- 'compose_exec_with_ldap_password "$service" "$helper_path" --env "$role_env_file" --yes install-plugins' "${docker_harness_sources[@]}" || {
  printf 'Jenkins controller install-plugins must run as ci-operator\n' >&2
  exit 1
}
grep -Fq -- 'compose_exec_with_ldap_password "$service" "$helper_path" --env "$role_env_file" --yes configure-jcasc' "${docker_harness_sources[@]}" || {
  printf 'Jenkins controller configure-jcasc must run as ci-operator\n' >&2
  exit 1
}
grep -Fq -- 'compose exec -T -u ci-operator -e LDAP_BIND_PASSWORD "$service" "$@"' "${docker_harness_sources[@]}" || {
  printf 'LDAP bind password must be injected by env name, not command-line value\n' >&2
  exit 1
}
grep -Fq -- 'compose exec -T -u ci-operator "$service" "$helper_path" --env "$role_env_file" collect-evidence' "${docker_harness_sources[@]}" || {
  printf 'Jenkins agent collect-evidence must run as ci-operator\n' >&2
  exit 1
}
grep -Fq -- 'compose exec -T -u ci-operator "$service" "$helper_path" --env "$role_env_file" --yes install' "${docker_harness_sources[@]}" || {
  printf 'Jenkins agent install must run as ci-operator\n' >&2
  exit 1
}
grep -Fq -- 'compose exec -T -u ci-operator "$service" "$helper_path" --env "$role_env_file" --yes configure-runtime' "${docker_harness_sources[@]}" || {
  printf 'Jenkins agent configure-runtime must run as ci-operator\n' >&2
  exit 1
}
for script in \
  "$repo_root/scripts/gerrit-setup.sh" \
  "$repo_root/scripts/jenkins-controller-setup.sh" \
  "$repo_root/scripts/jenkins-agent-setup.sh"
do
  grep -Fq -- 'prepare_artifact_bundle_workspace()' "$script" || {
    printf 'Role helper must own artifact bundle workspace preparation: %s\n' "$script" >&2
    exit 1
  }
  grep -Fq -- 'prepare_loopforge_helper_dirs "$preparing_dir"' "$script" ||
    grep -Fq -- 'run_with_privilege "install -d -m 0750 -o $(shell_quote "$LOOPFORGE_OPERATOR_ACCOUNT") -g $(shell_quote "$LOOPFORGE_OPERATOR_GROUP") $(shell_quote "$preparing_dir")"' "$script" || {
    printf 'Role helper must create the Loopforge preparing root: %s\n' "$script" >&2
    exit 1
  }
  grep -Fq -- 'prepare-target-workspace' "$script" || {
    printf 'Role helper must expose prepare-target-workspace: %s\n' "$script" >&2
    exit 1
  }
  grep -Fq -- 'prepare_loopforge_helper_dirs /var/lib/loopforge /var/log/loopforge /var/lib/loopforge/staging' "$script" || {
    printf 'Role helper must create Loopforge target roots and staging: %s\n' "$script" >&2
    exit 1
  }
  grep -Fq -- 'rm -rf "$bundle_dir"' "$script" || {
    printf 'Role helper must clean its own artifact bundle tree: %s\n' "$script" >&2
    exit 1
  }
done
grep -Fq -- 'reset_agent_state_for_install()' "$repo_root/scripts/jenkins-agent-setup.sh" || {
  printf 'Jenkins agent helper must own install-time state reset\n' >&2
  exit 1
}
grep -Fq -- '  reset_agent_state_for_install' "$repo_root/scripts/jenkins-agent-setup.sh" || {
  printf 'Jenkins agent install must call its helper-owned reset\n' >&2
  exit 1
}
grep -Fq -- 'rm -rf -- $(shell_quote "$JENKINS_AGENT_STATE_DIR/bootstrap")' "$repo_root/scripts/jenkins-agent-setup.sh" || {
  printf 'Jenkins agent reset must clear only child helper paths\n' >&2
  exit 1
}
if grep -Fq -- 'rm -rf -- $(shell_quote "$JENKINS_AGENT_STATE_DIR")' "$repo_root/scripts/jenkins-agent-setup.sh"; then
  printf 'Jenkins agent reset must not remove the state/root bind mount\n' >&2
  exit 1
fi
if grep -Fq -- 'owned_directory_command()' "$repo_root/scripts/common.sh"; then
  printf 'scripts/common.sh must not contain Docker harness-only ownership helpers\n' >&2
  exit 1
fi
grep -Fq -- 'owned_directory_command()' "${docker_harness_sources[@]}" || {
  printf 'Docker harness must own its local directory ownership command construction\n' >&2
  exit 1
}
grep -Fq -- 'command="test -d $(shell_quote "$dest_dir")"' "${docker_harness_sources[@]}" || {
  printf 'Docker harness artifact staging must require helper-created destination dirs\n' >&2
  exit 1
}
grep -Fq -- 'bundle_factory_artifact_export' "${docker_harness_sources[@]}" || {
  printf 'Docker harness must explicitly export bundle-factory artifacts to host\n' >&2
  exit 1
}
grep -Fq -- 'compose exec -T -u ci-operator "$service" "$helper_path"' "${docker_harness_sources[@]}" || {
  printf 'Docker harness must run bundle-factory helper operations as ci-operator\n' >&2
  exit 1
}
grep -Fq -- 'role_helpers_root_for_operator ci-operator' "${docker_harness_sources[@]}" || {
  printf 'Docker harness must resolve the canonical role-helper root\n' >&2
  exit 1
}
grep -Fq -- 'stage_role_helpers_for_all_services "$log"' "${docker_harness_sources[@]}" || {
  printf 'Docker up must stage the shared role-helper tree\n' >&2
  exit 1
}
grep -Fq -- 'find $(shell_quote "$tmp") -type d -exec chmod $LF_MODE_PUBLIC_DIR' "${docker_harness_sources[@]}" || {
  printf 'Docker role-helper directories must be public/read-only staged control-plane input\n' >&2
  exit 1
}
grep -Fq -- 'find $(shell_quote "$tmp") -type f -exec chmod $LF_MODE_PUBLIC_FILE' "${docker_harness_sources[@]}" || {
  printf 'Docker role-helper files must be public/read-only staged control-plane input\n' >&2
  exit 1
}
if grep -Fq -- '"/workspace/$helper"' "${docker_harness_sources[@]}"; then
  printf 'Docker harness must not execute role helpers from the source mount\n' >&2
  exit 1
fi
grep -Fq -- 'transfer_mode=docker-cp-waiver' "${docker_harness_sources[@]}" || {
  printf 'Docker harness must label Docker cp transfers as simulation-only waivers\n' >&2
  exit 1
}
grep -Fq -- 'stage_operator_env_file()' "${docker_harness_sources[@]}" &&
  grep -Fq -- 'stage_operator_env_file "$service" "$host_env_file"' "${docker_harness_sources[@]}" || {
  printf 'Docker harness target env staging must use operator input custody\n' >&2
  exit 1
}
grep -Fq -- 'docker_cp_file_to_service "$archive" "$service" "$container_archive" ci-operator ci-operator 0644 "$log"' "${docker_harness_sources[@]}" || {
  printf 'Docker harness artifact archive staging must use ci-operator ownership\n' >&2
  exit 1
}
grep -Fq -- 'docker_cp_file_to_service "$checksum" "$service" "$container_checksum" ci-operator ci-operator 0644 "$log"' "${docker_harness_sources[@]}" || {
  printf 'Docker harness artifact checksum staging must use ci-operator ownership\n' >&2
  exit 1
}
grep -Fq -- 'compose exec -T -u ci-operator "$service" sh -c "$extract_script"' "${docker_harness_sources[@]}" || {
  printf 'Docker harness artifact extraction must run as ci-operator\n' >&2
  exit 1
}
grep -Fq -- 'tar --no-same-owner -xzf "$archive_name" -C "$staging_root"' "${docker_harness_sources[@]}" || {
  printf 'Docker harness artifact extraction must not preserve archive owners\n' >&2
  exit 1
}
if grep -Fq -- 'chown -R ci-operator:ci-operator "$target_bundle_dir"' "${docker_harness_sources[@]}" ||
  grep -Fq -- 'find "$target_bundle_dir" -type d -exec chmod 0755 {} +' "${docker_harness_sources[@]}" ||
  grep -Fq -- 'find "$target_bundle_dir" -type f -exec chmod 0644 {} +' "${docker_harness_sources[@]}"; then
  printf 'Docker harness must not recursively repair extracted helper-owned bundle ownership\n' >&2
  exit 1
fi
