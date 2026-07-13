#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
helper="$repo_root/scripts/integration-setup.sh"

grep -Fq "findmnt -n -M '\$JENKINS_SHARED_STORAGE_PATH' -o SOURCE" "$helper" || {
  printf 'VM shared storage mount checks must inspect the exact mountpoint\n' >&2
  exit 1
}

if grep -Fq "findmnt -n -T '\$JENKINS_SHARED_STORAGE_PATH'" "$helper"; then
  printf 'VM shared storage mount checks must not treat the containing filesystem as a wrong mount\n' >&2
  exit 1
fi
