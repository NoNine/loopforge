#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

require_file() {
  local path
  path="${1:?path required}"
  [ -f "$repo_root/$path" ] || {
    printf 'Required documentation file is missing: %s\n' "$path" >&2
    exit 1
  }
}

reject_file() {
  local path
  path="${1:?path required}"
  [ ! -e "$repo_root/$path" ] || {
    printf 'Obsolete documentation path still exists: %s\n' "$path" >&2
    exit 1
  }
}

for path in \
  docs/README.md \
  docs/product/prd.md \
  docs/architecture/system-model.md \
  docs/contracts/lifecycle-contract.md \
  docs/contracts/account-model.md \
  docs/contracts/directory-model.md \
  docs/contracts/endpoint-identity.md \
  docs/contracts/operator-execution-contract.md \
  docs/contracts/artifact-bundle-contract.md \
  docs/contracts/validation-and-evidence.md \
  docs/contracts/gerrit-trigger-integration.md \
  docs/contracts/ci-model.md \
  docs/baselines/version-baseline.md \
  docs/baselines/package-requirements.md \
  docs/operations/README.md \
  docs/operations/setup/gerrit.md \
  docs/operations/setup/jenkins-controller.md \
  docs/operations/setup/jenkins-agent.md \
  docs/operations/setup/integration.md \
  docs/operations/native/gerrit.md \
  docs/operations/native/jenkins-controller.md \
  docs/operations/native/jenkins-agent.md \
  docs/operations/native/integration.md \
  docs/planning/implementation-plan.md \
  docs/planning/steps/step-01-repository-structure.md \
  docs/planning/steps/step-15-final-acceptance.md \
  project-state/execution-status.md \
  simulation/README.md \
  simulation/docs/terminal-output.md \
  simulation/docker/README.md \
  simulation/vm/README.md \
  simulation/vm/docs/design.md \
  simulation/vm/docs/sequences.md \
  simulation/vm/docs/verification.md \
  simulation/vm/docs/decisions/libvirt-module-refactor.md; do
  require_file "$path"
done

for path in \
  docs/docs-management.md \
  docs/execution-status.md \
  docs/implementation-plan.md \
  docs/implementation \
  docs/gerrit-setup-manual.md \
  docs/gerrit-native-operations-reference.md \
  simulation/terminal-output.md \
  simulation/vm/design.md \
  simulation/vm/sequences.md \
  simulation/vm/verification.md \
  simulation/vm/libvirt-refactor.md; do
  reject_file "$path"
done

unexpected_top_level="$(
  find "$repo_root/docs" -mindepth 1 -maxdepth 1 -type f -name '*.md' \
    ! -name README.md -print -quit
)"
[ -z "$unexpected_top_level" ] || {
  printf 'Unexpected top-level documentation file: %s\n' \
    "${unexpected_top_level#"$repo_root/"}" >&2
  exit 1
}

grep -Fq -- '`setup/` documents repository-assisted setup workflows.' \
  "$repo_root/docs/operations/README.md" || {
  printf 'Operations index must define the setup-manual boundary\n' >&2
  exit 1
}

grep -Fq -- '`native/` documents direct OS and application procedures' \
  "$repo_root/docs/operations/README.md" || {
  printf 'Operations index must define the native-reference boundary\n' >&2
  exit 1
}

grep -Fq -- \
  'Never stage or commit `project-state/execution-status.md`' \
  "$repo_root/AGENTS.md" || {
  printf 'AGENTS.md must retain the relocated ledger staging guard\n' >&2
  exit 1
}
