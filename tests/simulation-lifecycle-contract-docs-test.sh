#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
prd="$repo_root/docs/product/prd.md"
lifecycle="$repo_root/docs/contracts/lifecycle-contract.md"
directory="$repo_root/docs/contracts/directory-model.md"
layout="$repo_root/simulation/docs/shared/generated-state-layout.md"
evidence="$repo_root/docs/contracts/validation-and-evidence.md"
endpoint="$repo_root/docs/contracts/endpoint-identity.md"
shared="$repo_root/simulation/docs/shared/simulation-model.md"
state_model="$repo_root/simulation/docs/shared/lifecycle-state-model.md"
protocol="$repo_root/simulation/docs/shared/checkpoint-acceptance-protocol.md"
docker="$repo_root/simulation/docs/docker/docker-simulation.md"
vm="$repo_root/simulation/docs/vm/vm-simulation.md"
plan="$repo_root/docs/planning/implementation-plan.md"
step="$repo_root/docs/planning/steps/step-13a-reusable-simulation-lifecycle.md"
agents="$repo_root/AGENTS.md"

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

require_occurrences() {
  local file pattern expected message actual
  file="${1:?file required}"
  pattern="${2:?pattern required}"
  expected="${3:?expected count required}"
  message="${4:?message required}"
  actual="$(awk -v needle="$pattern" '
    {
      line = $0
      while ((position = index(line, needle)) > 0) {
        count++
        line = substr(line, position + length(needle))
      }
    }
    END { print count + 0 }
  ' "$file")"
  [ "$actual" -eq "$expected" ] || {
    printf '%s (expected=%s actual=%s)\n' \
      "$message" "$expected" "$actual" >&2
    exit 1
  }
}

require_text "$prd" \
  '`create`, `start`, `stop`, `restore-baseline`, `clean`,' \
  'PRD must define the reusable simulation lifecycle'
require_text "$prd" \
  'Both simulation backends use `HARNESS_SET_ID` for the reusable simulation' \
  'PRD must define shared simulation-set identity'
require_text "$lifecycle" \
  '# Loopforge Product Lifecycle Contract' \
  'Lifecycle contract must be explicitly product-level'
require_text "$lifecycle" \
  'This contract does not define concrete command syntax, backend resource' \
  'Lifecycle contract must delegate realization details'
require_text "$lifecycle" \
  '## Checkpoint Terminology' \
  'Lifecycle contract must define the shared checkpoint terminology'
require_text "$lifecycle" \
  'A **phase** is one invocation or activity performed by an owner.' \
  'Lifecycle contract must distinguish phases from checkpoints'
require_text "$lifecycle" \
  'A **product checkpoint family** is one semantic milestone category' \
  'Lifecycle contract must define product checkpoint families'
require_text "$lifecycle" \
  'A **workflow checkpoint record** is the simulation ledger' \
  'Lifecycle contract must distinguish simulation workflow records'
require_text "$lifecycle" \
  '## Product Checkpoint Families' \
  'Lifecycle contract must own the canonical checkpoint family vocabulary'
require_text "$lifecycle" \
  'Environment provisioning, power control, baseline restoration, generated-state' \
  'Lifecycle contract must keep environment lifecycle outside product progress'
require_text "$lifecycle" \
  'checkpoint mapping;' \
  'Lifecycle contract must delegate the simulation checkpoint mapping'
require_text "$shared" \
  '`up` and `down` are removed command names.' \
  'Shared simulation contract must reject removed commands'
require_text "$shared" \
  'generate a collision-resistant immutable `HARNESS_RUN_ID` when omitted' \
  'Shared simulation contract must own automatic run identity'
require_text "$shared" \
  'It rejects an active set or existing run root.' \
  'Shared simulation contract must reject active or reused run state'
require_text "$shared" \
  'through its existing env-file' \
  'Shared simulation contract must preserve the helper input interface'
require_text "$shared" \
  'That invocation adapter is not' \
  'Shared simulation contract must exclude the adapter from retained state'
require_text "$shared" \
  'source/effective input custody, and review output; live target access' \
  'Shared simulation stop must preserve bound inputs and drop live access'
require_text "$shared" \
  'Input rendering and publication change host-side generated state only.' \
  'Shared simulation input publication must not claim product progress'
require_text "$shared" \
  'It has no Reviewed Access product checkpoint, wait, or resume' \
  'Shared simulation contract must exclude Reviewed Access'
require_text "$shared" 'simulation-only direct Gerrit REST apply' \
  'Shared simulation contract must define direct ACL apply'
require_text "$protocol" 'simulation-only direct Gerrit REST apply' \
  'Checkpoint protocol must bind direct ACL apply evidence'
for file in "$docker" "$vm"; do
  reject_text "$file" 'simulation-only direct Gerrit REST apply' \
    "Backend docs must not redefine direct ACL apply: $file"
done
require_text "$state_model" \
  'Backend resource namespaces are derived from the backend and set ID and never' \
  'Lifecycle state model must keep resource namespaces independent of run ID'
require_text "$state_model" \
  '## Product-To-Simulation Checkpoint Mapping' \
  'Lifecycle state model must map product checkpoints to simulation state'
require_text "$state_model" \
  '| Product checkpoint family | Workflow checkpoint identifier |' \
  'Lifecycle state model must distinguish families from workflow identifiers'
require_text "$state_model" \
  'These operations are workflow prerequisites, not workflow' \
  'Lifecycle state model must keep run and baseline readiness outside the chain'
require_text "$state_model" \
  'commands never advance this chain.' \
  'Lifecycle state model must separate backend lifecycle from workflow progress'
require_text "$state_model" \
  'each role-qualified family, `<role>` expands in order to `gerrit`,' \
  'Lifecycle state model must define the fixed role expansion order'
require_text "$state_model" \
  '`jenkins-controller`, then `jenkins-agent`.' \
  'Lifecycle state model must preserve the final role expansion order'
require_text "$state_model" \
  'A family is fully expanded before' \
  'Lifecycle state model must define checkpoint family ordering'
require_text "$state_model" \
  'the next family begins, and each expansion advances independently.' \
  'Lifecycle state model must define independent family expansion'

actual_checkpoint_families="$(awk -F'`' '
  /^## Product-To-Simulation Checkpoint Mapping$/ { mapping = 1; next }
  mapping && /^## / { exit }
  mapping && /^\|/ && NF >= 5 { print $4; next }
  mapping && /^\|/ && NF >= 3 { print $2 }
' "$state_model")"
expected_checkpoint_families='prepare-artifacts-<role>
stage-artifacts-<role>
configure-role-<role>
validate-role-<role>
integration-preflight
configure-integration
validate-integration
prove-integration
evidence-audit'
[ "$actual_checkpoint_families" = "$expected_checkpoint_families" ] || {
  printf '%s\nexpected:\n%s\nactual:\n%s\n' \
    'Lifecycle state model has the wrong checkpoint family order' \
    "$expected_checkpoint_families" "$actual_checkpoint_families" >&2
  exit 1
}
for realization_term in \
  'HARNESS_RUN_ID' \
  'HARNESS_SET_ID' \
  '## Simulation Input Rendering Contract' \
  '## Simulation Command Relationship' \
  'restored-pending-clean' \
  'active-run.env' \
  'restore-baseline'; do
  reject_text "$lifecycle" "$realization_term" \
    "Product lifecycle contract must not own simulation realization: $realization_term"
done
require_text "$layout" \
  '## Canonical Roots' \
  'Generated-state layout must define set, lock, and run roots'
require_text "$layout" \
  '## Input Custody' \
  'Generated-state layout must define source and effective input custody'
require_text "$layout" \
  '`host/state/effective-inputs.env`' \
  'Generated-state layout must locate the effective-input binding record'
require_text "$layout" \
  '## Docker Realization' \
  'Generated-state layout must isolate Docker-specific generated paths'
require_text "$layout" \
  '## VM Realization' \
  'Generated-state layout must isolate VM-specific generated paths'
require_occurrences "$layout" \
  '| `sets/<set-id>/active-run.env` |' 1 \
  'Generated-state layout must not duplicate the shared active-run row'
require_occurrences "$layout" \
  '| `host/source-inputs/` |' 1 \
  'Generated-state layout must not duplicate the shared source-input row'
require_occurrences "$layout" \
  '| `host/state/workflow-state.env` |' 1 \
  'Generated-state layout must not duplicate the shared workflow-state row'
require_occurrences "$layout" \
  '| `host/evidence/integration/` |' 1 \
  'Generated-state layout must not duplicate shared integration evidence'
for simulation_heading in \
  '## Simulation Baselines And Run Identity' \
  '## Simulation Input Custody' \
  '## Shared Simulation Backing' \
  '## Docker-Specific Backing' \
  '## VM-Specific Backing'; do
  reject_text "$directory" "$simulation_heading" \
    "Target directory contract must not own simulation layout: $simulation_heading"
done
require_text "$evidence" \
  'Docker and VM harness product-checkpoint evidence must identify the immutable' \
  'Evidence contract must bind checkpoint evidence to immutable run ID'
require_text "$evidence" \
  'Docker and VM harness product-checkpoint evidence must identify the selected' \
  'Evidence contract must bind checkpoints to shared simulation-set identity'
require_text "$evidence" \
  'simulation source and effective input fingerprints.' \
  'Evidence contract must bind both simulation input layers'
require_text "$evidence" \
  '## Product Checkpoint Evidence' \
  'Evidence contract must apply the canonical product checkpoint vocabulary'
require_text "$evidence" \
  'Do not create evidence-only checkpoint names:' \
  'Evidence contract must reject a competing checkpoint vocabulary'
reject_text "$evidence" \
  'Recommended checkpoints:' \
  'Evidence contract must not maintain a second checkpoint list'
reject_text "$evidence" \
  'checkpoint-level evidence' \
  'Evidence contract must identify evidence without treating it as a checkpoint'
reject_text "$directory" \
  'run/checkpoint markers' \
  'Directory contract must distinguish run markers from checkpoint records'
reject_text "$repo_root/docs/operations/setup/jenkins-agent.md" \
  'checkpoint markers' \
  'Jenkins agent manual must not conflate status records with checkpoints'
require_text "$endpoint" \
  'Current DHCP address resolved after `start`; supplied only as simulation invocation transport' \
  'Endpoint contract must keep VM DHCP as ephemeral helper transport'
require_text "$endpoint" \
  'excluded from stable effective inputs' \
  'Endpoint contract must exclude VM DHCP from effective input authority'
require_text "$shared" \
  '## Shared Terminology And Backend Mapping' \
  'Shared simulation docs must define recommended lifecycle terms'
require_text "$shared" \
  '| Simulation set | One reusable backend environment selected by `HARNESS_SET_ID`.' \
  'Shared simulation docs must define simulation set'
require_text "$shared" \
  '| Resource namespace | `loopforge-docker-<set-id>` Compose project | `loopforge-vm-<set-id>` libvirt prefix |' \
  'Shared simulation docs must define exact backend namespaces'
require_text "$state_model" \
  '^[a-z0-9]([a-z0-9-]{0,22}[a-z0-9])?$' \
  'Lifecycle state model must define the canonical set-ID grammar'
require_text "$state_model" \
  'generated/simulation/<backend>/locks/<set-id>.lock' \
  'Lifecycle state model must define the stable set lock'
require_text "$state_model" \
  'The set-scoped `active-run.env` is the authoritative ownership and reset-gate' \
  'Lifecycle state model must define active-run pointer ownership'
require_text "$state_model" \
  'The run-scoped `workflow-state.env` is authoritative only for progression' \
  'Lifecycle state model must keep workflow state run-scoped'
require_text "$state_model" \
  'input_state=pending' \
  'Lifecycle state model must represent pending effective inputs'
require_text "$state_model" \
  'effective_inputs_fingerprint=none' \
  'Lifecycle state model must defer effective input binding until start'
require_text "$state_model" \
  'A repeated `start` verifies' \
  'Lifecycle state model must forbid stable input rewrites on restart'
require_text "$state_model" \
  'Unknown, duplicate, missing, malformed, or' \
  'Lifecycle records must use strict fail-closed parsing'
require_text "$state_model" \
  'before pointer publication consumes the run ID but does not claim the set.' \
  'Initialization must publish the active pointer last'
require_text "$state_model" \
  'the immutable run marker, workflow checkpoint records, evidence, artifacts, and logs,' \
  'Clean must retain immutable workflow evidence'
require_text "$state_model" \
  'A retry may find any known mutable cleanup target' \
  'Interrupted cleanup must be explicitly retryable'
require_text "$state_model" \
  'returns `state=existing` without mutation' \
  'Create must verify an exact existing set without mutation'
require_text "$state_model" \
  'reports `mode=resume`' \
  'Run must report active-run resume mode'
require_text "$state_model" \
  '`state=already-running`' \
  'Start must define idempotent already-running success'
require_text "$state_model" \
  '`state=already-stopped`' \
  'Stop must define idempotent already-stopped success'
require_text "$state_model" \
  '`state=already-absent`' \
  'Destroy must define idempotent already-absent success'
require_text "$protocol" \
  '| Evidence audit | Collector result that validates, but does not create,' \
  'Checkpoint protocol must keep aggregation separate from runtime truth'
require_text "$protocol" \
  'Their owning utilities still produce completion state and evidence' \
  'Checkpoint protocol must preserve target-deployment utility ownership'
require_text "$evidence" \
  '`simulation/docs/shared/checkpoint-acceptance-protocol.md` defines how producer-owned' \
  'Evidence authority must delegate checkpoint acceptance'
require_text "$step" \
  '`simulation/docs/shared/checkpoint-acceptance-protocol.md` for accepting the' \
  'Step 13a must read checkpoint acceptance protocol'

require_text "$shared" '`up` and `down` are' \
  'Shared simulation contract must reject removed commands'
for file in "$docker" "$vm"; do
  reject_text "$file" '`up` and `down` are' \
    "Backend docs must not restate removed shared commands: $file"
done

for command in create start stop restore-baseline clean destroy; do
  require_text "$shared" "| \`$command\` |" \
    "Shared simulation contract is missing command: $command"
done

require_text "$docker" \
  '`stop` must not remove containers or the selected network.' \
  'Docker stop must preserve exact containers'
require_text "$docker" \
  'Docker baseline restoration rejects running containers, image or Compose' \
  'Docker restore must own container recreation'
require_text "$layout" \
  'generated/simulation/<backend>/sets/<set-id>/' \
  'Shared layout must separate reusable simulation-set state from run output'
require_text "$vm" \
  'Set/run identity and active-run ownership are shared state-model contracts.' \
  'VM docs must delegate shared identity behavior'
reject_text "$vm" \
  'by exact selected resource names during recovery' \
  'VM destroy must not delete by derived names without ownership metadata'

require_text "$plan" \
  '`docs/planning/steps/step-13a-reusable-simulation-lifecycle.md`' \
  'Roadmap must link the reusable simulation lifecycle step'
for milestone in \
  '## M1: Shared Identity, Lock, Records, And Classifier' \
  '## M2: Simulation Input Lifecycle And Start-Owned Access' \
  '## M3: Docker Create, Start, And Stop' \
  '## M4: Docker Baseline Capture And Restore' \
  '## M5: VM Reusable-Set Lifecycle And Effective-Input Parity' \
  '## M6: Cross-Backend Reset, Cleanup, Status, And Lifecycle Evidence' \
  '## M7: First-Class Command Convergence And State-Aware Run Planning' \
  '## M8: Reusable Lifecycle Acceptance And Downstream Handoff'; do
  require_text "$step" "$milestone" \
    "Step 13a is missing milestone: $milestone"
done
require_text "$step" \
  '## Downstream Correlation And Handoff' \
  'Step 13a must correlate reusable lifecycle work with downstream tails'
require_text "$step" \
  'can accept end-to-end `run`' \
  'Step 13a must defer full composite acceptance until all tails exist'
require_text "$step" \
  'Keep the `run` handler state-passive:' \
  'Step 13a must keep composite-owned state out of run orchestration'

require_text "$agents" \
  '`stop` followed by `start` continues the same' \
  'Repository guardrail must preserve run ID across restart'
require_text "$agents" \
  '`init-run` generate a fresh run ID.' \
  'Repository guardrail must require a fresh run after reset'
reject_text "$agents" \
  'use a fresh `HARNESS_RUN_ID`/generated run root' \
  'Repository guardrail must not require manual Docker run ID churn'

for file in "$agents" "$prd" "$lifecycle" "$directory" "$layout" "$evidence" \
  "$shared" "$docker" "$vm" "$plan" "$step"; do
  reject_text "$file" 'HARNESS_RUN_GENERATION' \
    "Generation identity must not be part of the contract: $file"
done

for file in "$lifecycle" "$directory" "$evidence" "$endpoint" "$shared" "$state_model" "$protocol" "$docker" "$vm"; do
  reject_text "$file" 'LOOPFORGE_VM_SET_ID' \
    "Current simulation contracts must not expose the old VM set identity: $file"
  reject_text "$file" 'HARNESS_PROJECT_NAME' \
    "Current simulation contracts must not expose the old Docker identity: $file"
done

printf 'Simulation lifecycle documentation contract passed\n'
