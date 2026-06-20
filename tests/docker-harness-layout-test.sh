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
