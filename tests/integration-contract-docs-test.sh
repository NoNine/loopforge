#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
architecture="$repo_root/docs/architecture/system-model.md"
lifecycle="$repo_root/docs/contracts/lifecycle-contract.md"
integration_contract="$repo_root/docs/contracts/gerrit-trigger-integration.md"
evidence_contract="$repo_root/docs/contracts/validation-and-evidence.md"
native_manual="$repo_root/docs/operations/native/integration.md"
setup_manual="$repo_root/docs/operations/setup/integration.md"

require_text() {
  local file pattern message
  file="${1:?file required}"
  pattern="${2:?pattern required}"
  message="${3:?message required}"
  grep -Fq -- "$pattern" "$file" || {
    printf '%s\n' "$message" >&2
    exit 1
  }
}

reject_text() {
  local file pattern message
  file="${1:?file required}"
  pattern="${2:?pattern required}"
  message="${3:?message required}"
  if grep -Fq -- "$pattern" "$file"; then
    printf '%s\n' "$message" >&2
    exit 1
  fi
}

require_text "$architecture" \
  'uses two Gerrit configuration reviews' \
  'Architecture must require two Gerrit integration reviews'
require_text "$architecture" \
  'The target-project grant must not be moved to `All-Projects`' \
  'Architecture must preserve project-scoped least privilege'
reject_text "$architecture" \
  'uses one Gerrit configuration review in `All-Projects`' \
  'Architecture must not retain the single-review ACL model'

for checkpoint in \
  '| Integration preflight |' \
  '| Reviewed integration access |' \
  '| Shared integration setup |' \
  '| Cross-role validation |' \
  '| End-to-end trigger verification |'; do
  require_text "$lifecycle" "$checkpoint" \
    "Lifecycle contract is missing integration checkpoint: $checkpoint"
done
require_text "$lifecycle" \
  'Treat `validate-integration` as observational cross-role validation.' \
  'Lifecycle must keep integration validation observational'
require_text "$lifecycle" \
  'marker existence alone is not a valid prerequisite.' \
  'Lifecycle must bind integration markers to reviewed state'
require_text "$lifecycle" \
  'add the new credential or public key, prove it, and remove the old' \
  'Lifecycle must require add-and-prove-before-remove rotation'

for contract_rule in \
  'creates two reviewable configuration changes through REST' \
  '`blocked`, and stops without shared-setup success' \
  'without truncating unrelated authorized keys' \
  'disposable Gerrit change. The change emits `patchset-created`' \
  'Normal configuration must not delete or rotate an existing Gerrit token'; do
  require_text "$integration_contract" "$contract_rule" \
    "Integration contract is missing rule: $contract_rule"
done
for failure_class in \
  'Integration state-binding failure.' \
  '`All-Projects` reviewed-state failure.' \
  'Target-project reviewed-access failure.' \
  'Jenkins shared-storage setup failure.' \
  'Gerrit review-state verification failure.'; do
  require_text "$integration_contract" "$failure_class" \
    "Integration contract is missing failure classification: $failure_class"
done

for evidence_field in \
  '`all_projects_review_change_id` or `not-created`' \
  '`target_project_review_change_id` or `not-created`'; do
  require_text "$evidence_contract" "$evidence_field" \
    "Evidence contract is missing review field: $evidence_field"
done
require_text "$evidence_contract" \
  'A constant label or marker existence alone is not a' \
  'Evidence contract must reject unbound integration markers'

require_text "$native_manual" \
  'Create exactly two reviewable Gerrit configuration changes' \
  'Native integration must apply the two-review model'
require_text "$native_manual" \
  '## 8. Cross-Role Validation' \
  'Native integration must expose observational validation'
require_text "$native_manual" \
  'It must not truncate unrelated' \
  'Native integration must preserve unrelated authorized keys'
require_text "$native_manual" \
  '`docs/contracts/gerrit-trigger-integration.md`' \
  'Native integration must link the owning integration contract'

require_text "$setup_manual" \
  'workflow creates two reviewed Gerrit changes.' \
  'Helper manual must apply the two-review model'
require_text "$setup_manual" \
  '`validate-integration` is observational.' \
  'Helper manual must keep validation observational'
require_text "$setup_manual" \
  'returns `blocked` without a setup-success marker.' \
  'Helper manual must document the approval stop'
reject_text "$setup_manual" \
  '`validate-integration` and `prove-integration` must prove real cross-role behavior' \
  'Helper manual must not collapse validation and proof'
reject_text "$setup_manual" \
  '--yes validate-integration' \
  'Observational validation must not require mutation confirmation'

printf 'Integration documentation contract passed\n'
