#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

matches="$(
  git -C "$repo_root" ls-files docs scripts simulation tests |
  grep -v '^tests/docker-harness-no-legacy-evidence-test.sh$' |
  grep -v '^tests/docker-harness-layout-test.sh$' |
  grep -v '^simulation/docker/docker-verify.sh$' |
  grep -v '^simulation/docker/harness/' |
  xargs -r rg -n 'HARNESS_LEGACY_EVIDENCE_DIR|simulation/docker/target/helper-state/evidence|simulation/docker/logs/|simulation/target/helper-state/docker|simulation/staging/docker|simulation/evidence/docker|simulation/target/product-homes/docker|logs/docker/<run-id>|simulation/target/helper-state/docker/harness/<run-id>|simulation/target/helper-state/docker/harness/|simulation/docker/harness|harness.env.example|DOCKER_VERIFY_' || true
)"
if [ -n "$matches" ]; then
  printf '%s\n' "$matches"
  printf 'tracked source/docs still reference stale Docker generated output paths\n' >&2
  exit 1
fi
