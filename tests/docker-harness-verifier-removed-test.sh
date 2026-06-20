#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

[ ! -e "$repo_root/simulation/docker/docker-verify.sh" ] || {
  printf 'docker-verify.sh should be removed\n' >&2
  exit 1
}
[ ! -e "$repo_root/simulation/docker/examples/docker-verify.env.example" ] || {
  printf 'docker-verify env example should be removed\n' >&2
  exit 1
}
