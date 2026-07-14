#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
checklist="$repo_root/docs/operations/native/acceptance-checklist.md"

require_text() {
  local file pattern message
  file="${1:?file required}"
  pattern="${2:?pattern required}"
  message="${3:?message required}"
  grep -Fq -- "$pattern" "$repo_root/$file" || {
    printf '%s\n' "$message" >&2
    exit 1
  }
}

reject_text() {
  local file pattern message
  file="${1:?file required}"
  pattern="${2:?pattern required}"
  message="${3:?message required}"
  if grep -Fq -- "$pattern" "$repo_root/$file"; then
    printf '%s\n' "$message" >&2
    exit 1
  fi
}

[ -f "$checklist" ] || {
  printf 'Native target-deployment acceptance checklist is missing\n' >&2
  exit 1
}

for heading in \
  '## Deployment' \
  '## Preparation' \
  '## Gerrit' \
  '## Jenkins Controller' \
  '## Jenkins Agent' \
  '## Integration' \
  '## End-To-End Result'; do
  grep -Fxq -- "$heading" "$checklist" || {
    printf 'Checklist section is missing: %s\n' "$heading" >&2
    exit 1
  }
done

for reference in \
  'docs/operations/native/gerrit.md' \
  'docs/operations/native/jenkins-controller.md' \
  'docs/operations/native/jenkins-agent.md' \
  'docs/operations/native/integration.md'; do
  grep -Fq -- "$reference" "$checklist" || {
    printf 'Checklist must link to native procedure: %s\n' "$reference" >&2
    exit 1
  }
done

require_text docs/operations/native/acceptance-checklist.md \
  'freshly provisioned target hosts' \
  'Checklist must require fresh target state'
require_text docs/operations/native/acceptance-checklist.md \
  'Change/ticket:' \
  'Checklist must retain the deployment/change ticket reference'
require_text docs/operations/native/acceptance-checklist.md \
  'Gerrit verification change:' \
  'Checklist must retain the Gerrit verification change reference'
require_text docs/operations/native/acceptance-checklist.md \
  'Jenkins verification build:' \
  'Checklist must retain the Jenkins verification build reference'
require_text docs/operations/native/acceptance-checklist.md \
  'Result: ACCEPTED / BLOCKED' \
  'Checklist must have an explicit final decision'
require_text docs/operations/native/acceptance-checklist.md \
  'repair service state during validation.' \
  'Checklist must keep validation non-repairing'

if rg -n 'scripts/[^[:space:]`]+\.sh|simulation/[^[:space:]`]+\.sh|```(bash|sh)|collect-evidence|JSON|evidence package' \
  "$checklist"; then
  printf 'Checklist must not contain helpers, command transcripts, JSON, or evidence packaging\n' >&2
  exit 1
fi

require_text docs/operations/README.md \
  'native/acceptance-checklist.md' \
  'Operations index must link the native acceptance checklist'
require_text docs/contracts/validation-and-evidence.md \
  'Native `target-deployment` installation and configuration are fully manual.' \
  'Evidence contract must define fully manual native target deployment'
require_text docs/contracts/validation-and-evidence.md \
  'It is not required for the native `target-deployment` acceptance checklist.' \
  'Evidence contract must exclude the native checklist from global aggregation'
require_text docs/contracts/operator-execution-contract.md \
  'records the result in the native acceptance checklist' \
  'Operator contract must define checklist-based native acceptance'
require_text docs/contracts/lifecycle-contract.md \
  'Native `target-deployment` records the corresponding role, reboot,' \
  'Lifecycle contract must route native outcomes to the checklist'
require_text docs/architecture/system-model.md \
  'Native `target-deployment` acceptance uses' \
  'System model must distinguish the native checklist from machine evidence'
require_text docs/planning/steps/step-15-final-acceptance.md \
  '`docs/operations/native/acceptance-checklist.md`' \
  'Step 15 must include native target-deployment acceptance'
require_text docs/planning/steps/step-15-final-acceptance.md \
  'deployment/change ticket, disposable Gerrit' \
  'Step 15 must keep native acceptance references minimal'

reject_text docs/operations/native/gerrit.md \
  'Until that workflow is implemented' \
  'Gerrit native handoff must not call the manual integration workflow unimplemented'
reject_text docs/operations/native/jenkins-controller.md \
  'Until that workflow is implemented' \
  'Jenkins native handoff must not call the manual integration workflow unimplemented'
reject_text docs/operations/native/jenkins-agent.md \
  'Until that workflow is implemented' \
  'Agent native handoff must not call the manual integration workflow unimplemented'
require_text docs/operations/native/integration.md \
  '`docs/operations/native/acceptance-checklist.md`' \
  'Native integration must use the single acceptance checklist'
reject_text docs/operations/native/integration.md \
  'Collect an integration evidence record with:' \
  'Native integration must not require a separate evidence record'
