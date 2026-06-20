#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

matches="$(
  git -C "$repo_root" ls-files docs scripts simulation tests |
  grep -v '^tests/docker-harness-no-legacy-evidence-test.sh$' |
  grep -v '^tests/docker-harness-layout-test.sh$' |
  grep -v '^simulation/docker/docker-verify.sh$' |
  grep -v '^simulation/docker/harness/' |
  xargs -r rg -n 'HARNESS_LEGACY_EVIDENCE_DIR|simulation/docker/state/evidence|simulation/docker/state/|simulation/docker/logs/|simulation/state/docker/harness/<run-id>|simulation/state/docker/harness/|simulation/docker/harness|harness.env.example|DOCKER_VERIFY_' || true
)"
if [ -n "$matches" ]; then
  printf '%s\n' "$matches"
  printf 'tracked source/docs still reference stale Docker generated output paths\n' >&2
  exit 1
fi
