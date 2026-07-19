#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
checklist="$repo_root/docs/operations/setup/acceptance-checklist.md"

require_text() {
  local file pattern message
  file="$1"
  pattern="$2"
  message="$3"
  grep -Fq -- "$pattern" "$repo_root/$file" || {
    printf '%s\n' "$message" >&2
    exit 1
  }
}

[ -f "$checklist" ] || {
  printf 'Helper target acceptance checklist is missing\n' >&2
  exit 1
}

for family in \
  'Input review or source selection' \
  'OS dependency provisioning' \
  'Artifact preparation' \
  'Artifact staging' \
  'Role-local setup' \
  'Role-local validation' \
  'Integration preflight' \
  'Reviewed integration access' \
  'Shared integration setup' \
  'Cross-role validation' \
  'End-to-end trigger verification' \
  'Evidence audit'; do
  require_text docs/operations/setup/acceptance-checklist.md "$family" \
    "Helper checklist is missing checkpoint family: $family"
done

require_text docs/operations/setup/acceptance-checklist.md \
  'human operator or reviewer is the checkpoint acceptance authority' \
  'Helper checklist must assign acceptance to a human'
require_text docs/operations/setup/acceptance-checklist.md \
  'none is an acceptance record by itself' \
  'Helper checklist must keep evidence separate from acceptance'
require_text docs/operations/setup/acceptance-checklist.md \
  'global evidence package is required supporting material' \
  'Helper checklist must require final global collection without making it acceptance'
require_text docs/operations/setup/integration.md \
  'human operator has accepted each applicable role-local' \
  'Integration manual must require accepted role handoffs'
require_text docs/contracts/validation-and-evidence.md \
  'docs/operations/setup/acceptance-checklist.md' \
  'Evidence contract must route helper target acceptance to its checklist'

printf 'helper target acceptance documentation: ok\n'
