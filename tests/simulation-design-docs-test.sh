#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
system_model="$repo_root/docs/architecture/system-model.md"
package_requirements="$repo_root/docs/baselines/package-requirements.md"
simulation_model="$repo_root/simulation/docs/shared/simulation-model.md"
generated_layout="$repo_root/simulation/docs/shared/generated-state-layout.md"
harness_design="$repo_root/simulation/docs/shared/harness-design.md"
state_model="$repo_root/simulation/docs/shared/lifecycle-state-model.md"
protocol="$repo_root/simulation/docs/shared/run-plan-transition-protocol.md"
operations="$repo_root/simulation/docs/shared/operation-records.md"
docker_design="$repo_root/simulation/docs/docker/implementation-design.md"
vm_design="$repo_root/simulation/docs/vm/implementation-design.md"
lifecycle="$repo_root/docs/contracts/lifecycle-contract.md"
docker_guide="$repo_root/simulation/docs/docker/docker-simulation.md"
vm_guide="$repo_root/simulation/docs/vm/vm-simulation.md"
step13c="$repo_root/docs/planning/steps/step-13c-shared-integration-lifecycle.md"

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

require_text "$simulation_model" \
  '`simulation/docs/shared/harness-design.md`' \
  'Simulation model must link the harness design'
require_text "$simulation_model" \
  '`simulation/docs/shared/lifecycle-state-model.md`' \
  'Simulation model must link the exact lifecycle state model'
require_text "$simulation_model" \
  '`simulation/docs/shared/run-plan-transition-protocol.md`' \
  'Simulation model must link run-plan transition protocol'
require_text "$simulation_model" \
  '`simulation/docs/shared/operation-records.md`' \
  'Simulation model must link operation-record authority'
require_text "$simulation_model" \
  '`simulation/docs/shared/generated-state-layout.md`' \
  'Simulation model must link generated-state layout authority'
require_text "$system_model" \
  'This section is authoritative for logical-environment identity and' \
  'System model must own logical-environment identity'
require_text "$simulation_model" \
  'same six logical environments: one host control node' \
  'Simulation model must include the host control-node environment'
require_text "$simulation_model" \
  '| Control node | Docker harness host | VM harness host |' \
  'Simulation model must map the control node outside containers and VMs'
reject_text "$simulation_model" \
  'same five-machine topology' \
  'Simulation model must not omit the host control-node environment'
require_text "$package_requirements" \
  '`docs/architecture/system-model.md`. The system model owns environment identity' \
  'Package authority must consume the system logical-environment model'
reject_text "$package_requirements" \
  '## Logical Environment Model' \
  'Package authority must not duplicate the logical-environment model'
require_text "$simulation_model" \
  '## Lifecycle Documentation Boundary' \
  'Simulation model must route lifecycle documentation ownership'
require_text "$simulation_model" \
  'Backend documents apply these contracts and describe only their realization' \
  'Simulation model must restrict backend lifecycle documentation'
require_text "$simulation_model" \
  '## Shared Operator Interface' \
  'Simulation model must own the shared operator interface'
require_text "$simulation_model" \
  'mapping and composite `run` orchestration design.' \
  'Simulation model must route run implementation design to the shared harness'
require_text "$simulation_model" \
  '`ssh` requires `--role ROLE`.' \
  'Simulation model must own shared role operand syntax'
require_text "$simulation_model" \
  'HARNESS_GERRIT_ENV_FILE=examples/gerrit.env.example' \
  'Simulation model must own the shared bootstrap input schema'
require_text "$generated_layout" \
  'Consumer documents may repeat a path when an operator must type, inspect, or' \
  'Generated-state layout must define the consumer repetition rule'
require_text "$generated_layout" \
  '`docs/contracts/directory-model.md` owns paths visible inside the bundle' \
  'Generated-state layout must preserve the target-path authority boundary'

for removed_heading in \
  '## Output Locations' \
  '## Shared Simulation Backing' \
  '## Docker-Specific Backing' \
  '## VM-Specific Backing'; do
  reject_text "$simulation_model" "$removed_heading" \
    "Public simulation model must not own generated path inventory: $removed_heading"
done

for file in "$docker_guide" "$vm_guide"; do
  require_text "$file" \
    'realization deltas.' \
    "Backend guide must be realization-scoped: $file"
  require_text "$file" \
    '`simulation/docs/shared/generated-state-layout.md`' \
    "Backend guide must link generated-state authority: $file"
  reject_text "$file" \
    '## Output Locations' \
    "Backend guide must not own a shared output inventory: $file"
  reject_text "$file" \
    '| Harness evidence |' \
    "Backend guide must not repeat shared run-tree rows: $file"
  reject_text "$file" \
    '`ssh` requires `--role ROLE`.' \
    "Backend guide must not repeat shared operand syntax: $file"
  reject_text "$file" \
    'HARNESS_GERRIT_ENV_FILE=examples/gerrit.env.example' \
    "Backend guide must not repeat the shared bootstrap schema: $file"
  for shared_term in \
    'already-complete' \
    'state=already-running' \
    'state=already-stopped' \
    'state=already-absent' \
    'restored-pending-clean' \
    'active-incomplete' \
    'writes a marker for later verification' \
    'matching successful validate marker' \
    'Typical flow:'; do
    reject_text "$file" "$shared_term" \
      "Backend guide must not restate shared lifecycle term: $shared_term"
  done
done

require_text "$vm_guide" \
  '## VM Resource Namespace' \
  'VM simulation guide must keep only backend resource identity realization'
reject_text "$vm_guide" \
  '## Simulation Set And Run Identity' \
  'VM simulation guide must not define shared set/run identity'

require_text "$harness_design" \
  '## Architectural Planes' \
  'Shared harness design must define architectural planes'
require_text "$harness_design" \
  '| Backend infrastructure |' \
  'Shared harness design must define backend infrastructure ownership'
require_text "$harness_design" \
  '| Target control plane |' \
  'Shared harness design must define the target control plane'
require_text "$harness_design" \
  '| Loopforge lifecycle |' \
  'Shared harness design must define Loopforge lifecycle ownership'
require_text "$harness_design" \
  'Backend infrastructure may prepare or restore the simulation set' \
  'Shared harness design must prohibit backend checkpoint synthesis'
require_text "$harness_design" \
  '## Shared Helper Boundary' \
  'Shared harness design must define helper promotion rules'
require_text "$harness_design" \
  '## Common Harness Structure' \
  'Shared harness design must own common module roles'
require_text "$harness_design" \
  '| Command orchestration | Own composite run-plan sequencing' \
  'Shared harness design must own command orchestration responsibilities'
require_text "$harness_design" \
  '## Public Command Shape And Run Composition' \
  'Shared harness design must document composite run implementation'
require_text "$harness_design" \
  'Both `run` and the granular phase commands are first-class public commands.' \
  'Shared harness design must keep run and phase commands first-class'
require_text "$harness_design" \
  'the same command handler before capability delegation.' \
  'Run must reuse the directly invocable phase command handlers'
require_text "$harness_design" \
  '| Docker | `simulation/docker/simulate.sh` | `simulation/docker/lib/lifecycle.sh` |' \
  'Shared harness design must bind the Docker orchestration implementation'
require_text "$harness_design" \
  '| VM | `simulation/vm/simulate.sh` | `simulation/vm/lib/lifecycle.sh` |' \
  'Shared harness design must bind the VM orchestration implementation'
require_text "$harness_design" \
  '| Exact completed run, stopped | `start -> status`, then report `already-complete`' \
  'Shared harness design must define completed stopped run composition'
require_text "$harness_design" \
  '| Exact completed run, running | `status`, then report `already-complete`' \
  'Shared harness design must define completed running run composition'
require_text "$harness_design" \
  '`status` is an intentional user-facing observation in each executable plan.' \
  'Shared harness design must explain status in run plans'
require_text "$harness_design" \
  '`run` does not hold the set lock across the whole composite.' \
  'Shared harness design must preserve per-command locking in run'
require_text "$harness_design" \
  'stops at the first nonzero command result' \
  'Shared harness design must require fail-fast run orchestration'
require_text "$harness_design" \
  'Both harnesses source the implemented foundation under `simulation/lib/`:' \
  'Shared harness design must document the implemented shared foundation'
require_text "$harness_design" \
  '| `identity.sh`, `locking.sh` |' \
  'Shared harness design must map shared identity and locking modules'
require_text "$harness_design" \
  '| Persistence | Stable set lock, strict active-run and run-plan records,' \
  'Shared harness design must assign lifecycle persistence ownership'
require_text "$harness_design" \
  '`simulation/docs/shared/run-plan-transition-protocol.md`' \
  'Shared harness design must delegate run-plan transitions'

require_text "$state_model" \
  '## Two Coordinated State Machines' \
  'Lifecycle state model must explicitly separate the two state machines'
require_text "$state_model" \
  '| Simulation resource lifecycle (`R`) |' \
  'Lifecycle state model must define resource lifecycle state'
require_text "$state_model" \
  '## Simulation Resource Lifecycle State Machine' \
  'Lifecycle state model must give resource lifecycle its own section'
require_text "$state_model" \
  '| Product run plan (`P`) |' \
  'Lifecycle state model must define product run-plan state'
require_text "$state_model" \
  '## Product Run-Plan State Machine' \
  'Lifecycle state model must give product progression its own section'
require_text "$state_model" \
  '| Execution coordination state (`C`) |' \
  'Lifecycle state model must keep derived guards as coordination state'
require_text "$state_model" \
  '| Reset gate | `normal`, `restored-pending-clean` |' \
  'Lifecycle state model must define the post-restore gate'
require_text "$state_model" \
  '`exact-bound` means all durable state currently present is complete and bound' \
  'Lifecycle state model must preserve restart at exact checkpoint boundaries'
require_text "$state_model" \
  '## Cross-Machine Coordination Matrix' \
  'Lifecycle state model must define exact cross-machine guards'
require_text "$state_model" \
  '| `clean` | `restored-pending-clean`,' \
  'Clean must require successful baseline restoration'
require_text "$state_model" \
  'The same durable baseline appears in three combinations with different command' \
  'Lifecycle state model must distinguish restored and startable baselines'
require_text "$state_model" \
  '| `preflight`, `status`, `audit-state`, `clean`, `destroy` | `init-run`, `create`, `start`,' \
  'Restored-pending-clean must explicitly block start and workflow commands'
require_text "$state_model" \
  'The reuse path does not call `create`' \
  'Lifecycle state model must skip create for retained-baseline reuse'
require_text "$state_model" \
  '## Persistence And Concurrency' \
  'Lifecycle state model must define persistence and locking'
require_text "$state_model" \
  '## Run-Plan State Transitions' \
  'Lifecycle state model must define run-step state transitions'
require_text "$state_model" \
  '## Product Run-Plan State Machine' \
  'Lifecycle state model must define the product checkpoint realization'
require_text "$state_model" \
  'separate persisted state, transitions, records, and guards' \
  'Lifecycle state model must state its valid-state responsibility'
require_text "$state_model" \
  '`simulation/docs/shared/run-plan-transition-protocol.md` separately owns the' \
  'Lifecycle state model must delegate the transition protocol'
require_text "$state_model" \
  'product-owner postconditions, structured-result content, or transaction steps.' \
  'Lifecycle state model must exclude transition-protocol responsibilities'
require_text "$state_model" \
  '| `open-run-step(<step>, <activity>)` |' \
  'Lifecycle state model must define the run-step-open transition'
require_text "$state_model" \
  '| `commit-run-step(<record>)` |' \
  'Lifecycle state model must define the run-step-commit transition'
require_text "$state_model" \
  '`checkpoint_result_sha256`' \
  'Lifecycle state model must own the checkpoint-result digest field'
require_text "$state_model" \
  'The concrete role expansions and five unqualified identifiers in the final' \
  'Lifecycle state model must own the exact run-step vocabulary'
require_text "$state_model" \
  'Simulation has no Reviewed Access' \
  'Lifecycle state model must exclude Reviewed Access'
reject_text "$state_model" \
  '`idle`, `observing`, `mutating`, `waiting`' \
  'Lifecycle state model must not define waiting activity'
reject_text "$state_model" \
  'reviewed-integration-access' \
  'Lifecycle state model must not define a reviewed-access checkpoint'
reject_text "$state_model" \
  '## Workflow Transaction Protocol' \
  'Lifecycle state model must delegate the cross-layer transaction protocol'
reject_text "$state_model" \
  '## Acceptance Requirements' \
  'Lifecycle state model must not define owned-result acceptance'
reject_text "$state_model" \
  '## Publication Protocol' \
  'Lifecycle state model must not define cross-layer publication order'
require_text "$state_model" \
  '## Exact-Bound Classification' \
  'Lifecycle state model must assign exact-bound classification'
require_text "$state_model" \
  'An interrupted observation may' \
  'Lifecycle state model must separate observational interruption from durable corruption'

require_text "$protocol" \
  '# Simulation Run-Plan Transition Protocol' \
  'Run-plan protocol must be explicitly transition-scoped'
require_text "$protocol" \
  '## Result And Record Ownership' \
  'Run-plan protocol must distinguish record ownership'
require_text "$protocol" \
  '## Run-Plan Result Requirements' \
  'Run-plan protocol must define checkpoint-result verification inputs'
require_text "$protocol" \
  '## Transition Protocol' \
  'Run-plan protocol must define transition ordering'
require_text "$protocol" \
  '## Failure Protocol' \
  'Checkpoint protocol must define proof failure handling'
require_text "$protocol" \
  'Only the run-plan head and its hash-linked run-step chain determine' \
  'Run-plan protocol must preserve one progression authority'
require_text "$protocol" \
  'This protocol invokes `open-run-step` and' \
  'Run-plan protocol must consume state-model transitions'
require_text "$protocol" \
  '`simulation-only direct Gerrit REST apply`' \
  'Checkpoint protocol must bind the simulation ACL realization'
reject_text "$protocol" \
  '## State Dimensions' \
  'Checkpoint protocol must not define persisted state dimensions'
reject_text "$protocol" \
  '## Exact-Bound Classification' \
  'Checkpoint protocol must not define state classification'
reject_text "$protocol" \
  '## Command Guard And Effect Matrix' \
  'Checkpoint protocol must not define command guards or effects'
reject_text "$protocol" \
  '## Product-To-Simulation Checkpoint Mapping' \
  'Checkpoint protocol must not define checkpoint vocabulary or order'
reject_text "$protocol" \
  'activity=waiting' \
  'Checkpoint protocol must not define simulation waiting state'

require_text "$operations" \
  '# Simulation Operation Records' \
  'Operation-record contract must be present'
require_text "$operations" \
  'It cannot supply' \
  'Operation records must not satisfy product run steps'
require_text "$operations" \
  '`checkpoint_result_sha256` for a run-step record.' \
  'Operation records must not supply checkpoint-result digests'

require_text "$lifecycle" \
  '`simulation/docs/shared/lifecycle-state-model.md` owns exact simulation state' \
  'Lifecycle authority must delegate exact simulation state realization'
require_text "$lifecycle" \
  'checkpoint mapping;' \
  'Lifecycle authority must delegate the simulation checkpoint mapping'
require_text "$lifecycle" \
  '`simulation/docs/shared/run-plan-transition-protocol.md` owns structured' \
  'Lifecycle authority must delegate run-plan transitions'
reject_text "$lifecycle" \
  'restored-pending-clean' \
  'Product lifecycle authority must not define a simulation reset gate'
require_text "$state_model" \
  'RestoredPendingClean --> BaselineStopped: clean' \
  'Lifecycle state model must own the cleanup release transition'

require_text "$vm_design" \
  '# VM Simulation Harness Implementation Design' \
  'VM design must be explicitly implementation-scoped'
require_text "$vm_design" \
  '`simulation/docs/shared/harness-design.md` owns the common' \
  'VM implementation design must delegate shared architecture'
require_text "$vm_design" \
  '## Current Module Mapping' \
  'VM implementation design must map current modules to shared roles'
require_text "$vm_design" \
  'No VM module defines an alternate shared identity,' \
  'VM implementation design must reject backend-local shared state models'
require_text "$vm_design" \
  '`simulation/docs/shared/lifecycle-state-model.md` owns simulation-set state' \
  'VM implementation design must delegate shared lifecycle state'
require_text "$vm_design" \
  'structured checkpoint-result capture and verification plus run-step commitment.' \
  'VM implementation design must delegate run-plan transitions'
require_text "$docker_design" \
  'structured checkpoint-result capture and verification plus run-step commitment.' \
  'Docker implementation design must delegate run-plan transitions'
require_text "$docker_design" \
  '`simulation/docs/shared/harness-design.md` owns' \
  'Docker implementation design must delegate common harness structure'
require_text "$docker_design" \
  'inputs.sh' \
  'Docker implementation design must include the implemented input module'
reject_text "$docker_design" \
  '## Shared Extraction Rule' \
  'Docker implementation design must not duplicate the shared extraction rule'
reject_text "$vm_design" \
  '## Initial Module Layout' \
  'VM implementation design must not present the historical layout as current'
reject_text "$vm_design" \
  'Until the accepted refactor is implemented' \
  'VM implementation design must not describe the accepted refactor as pending'
reject_text "$vm_design" \
  'matching `validate-integration` marker' \
  'VM implementation design must not retain a duplicate validation marker'
reject_text "$vm_design" \
  'stateDiagram-v2' \
  'VM implementation design must not define a competing lifecycle state diagram'
reject_text "$vm_design" \
  'BaselineRestored --> Running' \
  'VM implementation design must not permit start directly after restoration'
require_text "$step13c" \
  '## M5: Run-Plan Ledger Cutover, Composite Completion, And Evidence Alignment' \
  'Step 13c must schedule the executable run-plan-ledger cutover'
require_text "$step13c" \
  'M1-M4 bound outputs, accepted Step 13a run planner, and Step 13b role tail' \
  'Step 13c run completion must depend on accepted upstream handoffs'
require_text "$step13c" \
  'tests/docker-harness-integration-wiring-test.sh' \
  'Step 13c ledger cutover must name Docker focused coverage'
require_text "$step13c" \
  'tests/vm-harness-integration-lifecycle-test.sh' \
  'Step 13c ledger cutover must name VM focused coverage'
require_text "$step13c" \
  '## M6: Docker, VM, And Native Runtime Acceptance' \
  'Step 13c must defer runtime acceptance until after ledger cutover'

[ ! -e "$repo_root/simulation/vm/docs/design.md" ] || {
  printf '%s\n' 'Obsolete VM design path must not remain after promotion' >&2
  exit 1
}

printf 'Shared simulation design documentation contract passed\n'
