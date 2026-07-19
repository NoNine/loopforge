#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
prd="$repo_root/docs/product/prd.md"
architecture="$repo_root/docs/architecture/system-model.md"
lifecycle="$repo_root/docs/contracts/lifecycle-contract.md"
operator_contract="$repo_root/docs/operations/README.md"
integration_contract="$repo_root/docs/contracts/gerrit-trigger-integration.md"
evidence_contract="$repo_root/docs/contracts/validation-and-evidence.md"
native_manual="$repo_root/docs/operations/native/integration.md"
setup_manual="$repo_root/docs/operations/setup/integration.md"
implementation_plan="$repo_root/docs/planning/implementation-plan.md"
role_step_plan="$repo_root/docs/planning/steps/step-13b-fresh-state-role-lifecycle.md"
integration_step_plan="$repo_root/docs/planning/steps/step-13c-shared-integration-lifecycle.md"
boundary_plan="$repo_root/docs/planning/steps/step-14-boundary-checks.md"
final_acceptance="$repo_root/docs/planning/steps/step-15-final-acceptance.md"

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
require_text "$architecture" \
  '`simulation-only direct Gerrit REST apply`' \
  'Architecture must define the simulation ACL realization'
require_text "$architecture" \
  'Reviewed Access is unsupported and `not-applicable`.' \
  'Architecture must exclude Reviewed Access from simulation'
reject_text "$architecture" \
  'auto-submit them as simulation test automation' \
  'Architecture must not claim simulation review submission'
reject_text "$architecture" \
  'uses one Gerrit configuration review in `All-Projects`' \
  'Architecture must not retain the single-review ACL model'

for checkpoint in \
  '| Integration preflight |' \
  '| Reviewed integration access (`target-deployment` only) |' \
  '| Shared integration setup |' \
  '| Cross-role validation |' \
  '| End-to-end trigger verification |'; do
  require_text "$lifecycle" "$checkpoint" \
    "Lifecycle contract is missing integration checkpoint: $checkpoint"
done
require_text "$lifecycle" \
  'Observe effective access, SSH paths, key custody, storage, node state,' \
  'Lifecycle must keep integration validation observational'
require_text "$lifecycle" \
  'existence alone is not a valid prerequisite.' \
  'Lifecycle must bind integration completion state to reviewed state'
require_text "$lifecycle" \
  'the only resumable mutation boundary' \
  'Lifecycle must limit mutation resume to Gerrit external review'
require_text "$lifecycle" \
  'Simulation has no Reviewed Access wait or resume.' \
  'Lifecycle must exclude the target review wait from simulation'
require_text "$lifecycle" \
  'state returns `already-complete` without mutation.' \
  'Lifecycle must define exact completed-state no-op behavior'
require_text "$lifecycle" \
  'role helpers do not reinstall or reconfigure it.' \
  'Lifecycle must reject role reinstall and reconfiguration'

for non_goal in \
  'Reinstalling or reconfiguring an existing Gerrit' \
  'Helper-driven SSH key, Gerrit HTTP token, or Jenkins credential rotation'; do
  require_text "$prd" "$non_goal" "PRD is missing v1 non-goal: $non_goal"
done
require_text "$operator_contract" \
  'returns non-mutating `already-complete` for exact input-bound completed state.' \
  'Operator contract must define the exact completed-state no-op'
reject_text "$operator_contract" \
  'idempotent target operations' \
  'Operator contract must not promise generic idempotent operations'

for contract_rule in \
  'creates two reviewable configuration changes through' \
  '`blocked`, and stops without shared-setup success' \
  'Docker and VM simulation omit Reviewed Access.' \
  '`simulation-only direct Gerrit REST apply`' \
  'without truncating unrelated authorized keys' \
  'disposable Gerrit change. The change emits `patchset-created`' \
  'Loopforge v1 does not perform rotation.'; do
  require_text "$integration_contract" "$contract_rule" \
    "Integration contract is missing rule: $contract_rule"
done
for failure_class in \
  'Integration state-binding failure.' \
  'Global Gerrit access-state failure.' \
  'Project/ref Gerrit access-state failure.' \
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
  'marker existence alone is not an input fingerprint' \
  'Evidence contract must reject unbound integration markers'
for simulation_field in \
  '`reviewed_access.status`' \
  '`reviewed_access.reason=unsupported-in-simulation`' \
  '`acl_realization=simulation-only-direct-rest-apply`'; do
  require_text "$evidence_contract" "$simulation_field" \
    "Evidence contract is missing simulation field: $simulation_field"
done

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
require_text "$native_manual" \
  '## 11. Existing State And Site Administration' \
  'Native integration must keep rotation outside initial setup'
reject_text "$native_manual" \
  'For Jenkins-to-Gerrit key rotation:' \
  'Native integration must not provide a v1 rotation procedure'

require_text "$setup_manual" \
  'workflow creates two reviewed Gerrit changes.' \
  'Helper manual must apply the two-review model'
require_text "$setup_manual" \
  '`validate-integration` is observational.' \
  'Helper manual must keep validation observational'
require_text "$setup_manual" \
  'returns `blocked` without a setup-success marker.' \
  'Helper manual must document the approval stop'
require_text "$setup_manual" \
  '| `apply-direct` | `docker-simulation`, `vm-simulation` |' \
  'Helper manual must select direct ACL application for simulation'
reject_text "$setup_manual" \
  '`create-review-and-submit`' \
  'Helper manual must not support simulation review submission'
reject_text "$setup_manual" \
  '`validate-integration` and `prove-integration` must prove real cross-role behavior' \
  'Helper manual must not collapse validation and proof'
reject_text "$setup_manual" \
  '--yes validate-integration' \
  'Observational validation must not require mutation confirmation'

require_text "$implementation_plan" \
  '`docs/planning/steps/step-13b-fresh-state-role-lifecycle.md`' \
  'Roadmap must link the fresh-state role lifecycle step'
require_text "$implementation_plan" \
  '`docs/planning/steps/step-13c-shared-integration-lifecycle.md`' \
  'Roadmap must link the shared integration lifecycle step'
for milestone in \
  '## M1: Shared State Authority And Marker Semantics' \
  '## M2: Gerrit Role Lifecycle' \
  '## M3: Jenkins Controller Role Lifecycle' \
  '## M4: Jenkins Agent Role Lifecycle' \
  '## M5: Role Gates, Run-Plan Tail, Evidence, And Runtime Acceptance'; do
  require_text "$role_step_plan" "$milestone" \
    "Step 13b is missing milestone: $milestone"
done
require_text "$role_step_plan" \
  'through the role tail without committing the integration tail.' \
  'Step 13b must not claim full composite integration completion'
require_text "$role_step_plan" \
  '## Role Correlation And Consumers' \
  'Step 13b must map independent role results to cross-role consumers'
require_text "$role_step_plan" \
  'No role helper consumes another role helper' \
  'Step 13b must not invent cross-role helper dependencies'
require_text "$role_step_plan" \
  '| M4 | Jenkins agent role lifecycle | M1 shared semantics |' \
  'Step 13b agent implementation must depend on shared role semantics'
for milestone in \
  '## M1: State, Preflight, And Gerrit ACL Realization' \
  '## M2: Jenkins Controller And Agent SSH Custody' \
  '## M3: Shared Storage, Node, And Gerrit Trigger Setup' \
  '## M4: Observational Validation And Active Proof' \
  '## M5: Run-Plan Ledger Cutover, Composite Completion, And Evidence Alignment' \
  '## M6: Docker, VM, And Native Runtime Acceptance'; do
  require_text "$integration_step_plan" "$milestone" \
    "Step 13c is missing milestone: $milestone"
done
require_text "$integration_step_plan" \
  'Do not add compatibility fallbacks for old generated integration state.' \
  'Step 13c must require explicit stale-state recovery'
require_text "$integration_step_plan" \
  'M1-M4 bound outputs, accepted Step 13a run planner, and Step 13b role tail' \
  'Step 13c composite completion must depend on earlier planner and role work'
require_text "$integration_step_plan" \
  'never publish composite-owned run-plan state.' \
  'Step 13c must preserve harness-owned run-plan commitment'
require_text "$integration_step_plan" \
  '`tests/vm-harness-run-workflow-test.sh`' \
  'Step 13c must add focused VM composite run coverage'
require_text "$integration_step_plan" \
  '## Integration Correlation And Cutover' \
  'Step 13c must map checkpoint results to sequential integration consumers'
require_text "$integration_step_plan" \
  'M5 is one fail-closed harness cutover after every result contract exists' \
  'Step 13c must defer ledger cutover until result contracts exist'
reject_text "$integration_step_plan" \
  'native rotation procedure' \
  'Step 13c must not depend on a Loopforge rotation procedure'
require_text "$boundary_plan" \
  'fresh-state role lifecycle, and Step 13c shared integration lifecycle' \
  'Boundary checks must depend on Steps 13a through 13c'
require_text "$boundary_plan" \
  'with only the target-deployment Gerrit' \
  'Boundary checks must scope the review wait to target deployment'
require_text "$final_acceptance" \
  '13a, 13b, and 13c are accepted and Step 14 boundary checks pass.' \
  'Final acceptance must depend on Steps 13a through 13c'
reject_text "$final_acceptance" \
  '--yes validate-integration' \
  'Final acceptance must keep integration validation observational'

printf 'Integration documentation contract passed\n'
