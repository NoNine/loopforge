#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

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
grep -Fq -- 'sudo \' "$repo_root/simulation/docker/target/Dockerfile" || {
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

grep -Fq -- '${HARNESS_PRODUCT_HOME_DIR}/gerrit:/srv/gerrit' "$repo_root/simulation/docker/compose.yaml" || {
  printf 'Docker compose must mount Gerrit product home from HARNESS_PRODUCT_HOME_DIR\n' >&2
  exit 1
}
grep -Fq -- '${HARNESS_PRODUCT_HOME_DIR}/jenkins-controller:/var/lib/jenkins' "$repo_root/simulation/docker/compose.yaml" || {
  printf 'Docker compose must mount Jenkins product home from HARNESS_PRODUCT_HOME_DIR\n' >&2
  exit 1
}
grep -Fq -- '${HARNESS_PRODUCT_HOME_DIR}/jenkins-agent:/var/lib/jenkins-agent' "$repo_root/simulation/docker/compose.yaml" || {
  printf 'Docker compose must mount Jenkins agent remote FS from HARNESS_PRODUCT_HOME_DIR\n' >&2
  exit 1
}
if grep -Eq '\$\{HARNESS_STATE_DIR\}/[^:]*:(/srv/gerrit|/var/lib/jenkins|/var/lib/jenkins-agent)' "$repo_root/simulation/docker/compose.yaml"; then
  printf 'Product homes must not be backed by HARNESS_STATE_DIR paths\n' >&2
  exit 1
fi

grep -Fq -- 'prepare_product_home_ownership' "$repo_root/simulation/docker/simulate.sh" || {
  printf 'Docker harness must prepare product home ownership inside target containers\n' >&2
  exit 1
}
grep -Fq -- 'chown -R $(shell_quote "$account:$group") $(shell_quote "$path")' "$repo_root/simulation/docker/simulate.sh" || {
  printf 'Docker harness product home preparation must chown configured account/group\n' >&2
  exit 1
}
