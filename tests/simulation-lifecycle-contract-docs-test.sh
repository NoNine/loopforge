#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
prd="$repo_root/docs/product/prd.md"
lifecycle="$repo_root/docs/contracts/lifecycle-contract.md"
directory="$repo_root/docs/contracts/directory-model.md"
evidence="$repo_root/docs/contracts/validation-and-evidence.md"
endpoint="$repo_root/docs/contracts/endpoint-identity.md"
shared="$repo_root/simulation/README.md"
state_model="$repo_root/simulation/docs/lifecycle-state-model.md"
docker="$repo_root/simulation/docker/README.md"
vm="$repo_root/simulation/vm/README.md"
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

require_text "$prd" \
  '`create`, `start`, `stop`, `restore-baseline`, `clean`,' \
  'PRD must define the reusable simulation lifecycle'
require_text "$prd" \
  'Both simulation backends use `HARNESS_SET_ID` for the reusable simulation' \
  'PRD must define shared simulation-set identity'
require_text "$lifecycle" \
  '`up` and `down` are not Loopforge simulation commands.' \
  'Lifecycle contract must remove up/down commands'
require_text "$lifecycle" \
  '`HARNESS_RUN_ID` identifies exactly one setup and validation attempt.' \
  'Lifecycle contract must define immutable run identity'
require_text "$lifecycle" \
  'operator omits it, `init-run` generates a collision-resistant immutable value;' \
  'Lifecycle contract must generate a run ID when omitted'
require_text "$lifecycle" \
  'an explicitly supplied value must not already exist.' \
  'Lifecycle contract must reject reused explicit run IDs'
require_text "$lifecycle" \
  '`stop` and `start` preserve that pointer and run ID.' \
  'Lifecycle contract must preserve run identity across restart'
require_text "$lifecycle" \
  '## Simulation Input Rendering Contract' \
  'Lifecycle contract must separate simulation rendering from target review'
require_text "$lifecycle" \
  'The temporary file is not retained input state, evidence, or a' \
  'Lifecycle contract must keep ephemeral integration transport outside input authority'
require_text "$lifecycle" \
  'The harness owns this invocation adapter; the shared helper' \
  'Lifecycle contract must keep the simulation adapter outside the shared helper'
require_text "$lifecycle" \
  'continues to consume its existing env-file interface without adapter-specific' \
  'Lifecycle contract must preserve the shared helper env-file interface'
require_text "$lifecycle" \
  '`HARNESS_SET_ID` selects one simulation' \
  'Lifecycle contract must define shared simulation-set identity'
require_text "$lifecycle" \
  'Both values are stable across runs of the same simulation set and must not' \
  'Lifecycle contract must keep backend namespaces independent of run identity'
require_text "$directory" \
  '## Simulation Baselines And Run Identity' \
  'Directory contract must define baseline and run identity custody'
require_text "$directory" \
  '## Simulation Input Custody' \
  'Directory contract must define source and effective simulation input custody'
require_text "$directory" \
  '`host/state/effective-inputs.env`' \
  'Directory contract must define the effective-input binding record'
require_text "$evidence" \
  'Docker and VM harness checkpoint evidence must identify the immutable' \
  'Evidence contract must bind checkpoint evidence to immutable run ID'
require_text "$evidence" \
  'Docker and VM harness checkpoint evidence must identify the selected `set_id`.' \
  'Evidence contract must bind checkpoints to shared simulation-set identity'
require_text "$evidence" \
  'simulation source and effective input fingerprints.' \
  'Evidence contract must bind both simulation input layers'
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
  'the immutable run marker, checkpoint records, evidence, artifacts, and logs,' \
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

for file in "$shared" "$docker" "$vm"; do
  require_text "$file" '`up` and `down` are' \
    "Simulation documentation must reject removed commands: $file"
done

for command in create start stop restore-baseline clean destroy; do
  require_text "$shared" "| \`$command\` |" \
    "Shared simulation contract is missing command: $command"
done

require_text "$docker" \
  'then stops the exact containers without removing them.' \
  'Docker stop must preserve exact containers'
require_text "$docker" \
  '`restore-baseline` is the only normal selected-run command that may remove and' \
  'Docker restore must own container recreation'
require_text "$docker" \
  'generated/simulation/docker/sets/<set-id>/' \
  'Docker docs must separate reusable simulation-set state from run output'
require_text "$vm" \
  '`HARNESS_RUN_ID` | Immutable identity for exactly one setup and validation attempt.' \
  'VM docs must define immutable attempt identity'
require_text "$vm" \
  'Each simulation set stores one non-secret `active-run.env` pointer.' \
  'VM docs must define simulation-set active-run ownership'
require_text "$vm" \
  'generated/simulation/vm/sets/<set-id>/' \
  'VM docs must separate reusable simulation-set state from run output'
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
  '## M5: VM Start/Stop Migration And Effective-Input Adoption' \
  '## M6: Cleanup, Evidence, Composite Workflows, And Acceptance'; do
  require_text "$step" "$milestone" \
    "Step 13a is missing milestone: $milestone"
done

require_text "$agents" \
  '`stop` followed by `start` continues the same' \
  'Repository guardrail must preserve run ID across restart'
require_text "$agents" \
  '`init-run` generate a fresh run ID.' \
  'Repository guardrail must require a fresh run after reset'
reject_text "$agents" \
  'use a fresh `HARNESS_RUN_ID`/generated run root' \
  'Repository guardrail must not require manual Docker run ID churn'

for file in "$agents" "$prd" "$lifecycle" "$directory" "$evidence" \
  "$shared" "$docker" "$vm" "$plan" "$step"; do
  reject_text "$file" 'HARNESS_RUN_GENERATION' \
    "Generation identity must not be part of the contract: $file"
done

for file in "$lifecycle" "$directory" "$evidence" "$endpoint" "$shared" "$state_model" "$docker" "$vm"; do
  reject_text "$file" 'LOOPFORGE_VM_SET_ID' \
    "Current simulation contracts must not expose the old VM set identity: $file"
  reject_text "$file" 'HARNESS_PROJECT_NAME' \
    "Current simulation contracts must not expose the old Docker identity: $file"
done

printf 'Simulation lifecycle documentation contract passed\n'
