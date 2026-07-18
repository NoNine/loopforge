#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
shared_readme="$repo_root/simulation/README.md"
harness_design="$repo_root/simulation/docs/harness-design.md"
state_model="$repo_root/simulation/docs/lifecycle-state-model.md"
protocol="$repo_root/simulation/docs/checkpoint-acceptance-protocol.md"
docker_design="$repo_root/simulation/docker/docs/implementation-design.md"
vm_design="$repo_root/simulation/vm/docs/implementation-design.md"
lifecycle="$repo_root/docs/contracts/lifecycle-contract.md"
docker_readme="$repo_root/simulation/docker/README.md"
vm_readme="$repo_root/simulation/vm/README.md"
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

require_text "$shared_readme" \
  '`simulation/docs/harness-design.md`' \
  'Shared simulation README must link the harness design'
require_text "$shared_readme" \
  '`simulation/docs/lifecycle-state-model.md`' \
  'Shared simulation README must link the exact lifecycle state model'
require_text "$shared_readme" \
  '`simulation/docs/checkpoint-acceptance-protocol.md`' \
  'Shared simulation README must link checkpoint acceptance protocol'
require_text "$shared_readme" \
  '## Lifecycle Documentation Boundary' \
  'Shared simulation README must route lifecycle documentation ownership'
require_text "$shared_readme" \
  'Backend documents apply these contracts and describe only their realization' \
  'Shared simulation README must restrict backend lifecycle documentation'

for file in "$docker_readme" "$vm_readme"; do
  require_text "$file" \
    'realization deltas.' \
    "Backend README must be realization-scoped: $file"
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
      "Backend README must not restate shared lifecycle term: $shared_term"
  done
done

require_text "$vm_readme" \
  '## VM Resource Namespace' \
  'VM README must keep only backend resource identity realization'
reject_text "$vm_readme" \
  '## Simulation Set And Run Identity' \
  'VM README must not define shared set/run identity'

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
  '| Persistence | Stable set lock, strict active-run and workflow records,' \
  'Shared harness design must assign lifecycle persistence ownership'
require_text "$harness_design" \
  '`simulation/docs/checkpoint-acceptance-protocol.md`' \
  'Shared harness design must delegate checkpoint acceptance'

require_text "$state_model" \
  '## State Dimensions' \
  'Lifecycle state model must separate state dimensions'
require_text "$state_model" \
  '| Reset gate | `normal`, `restored-pending-clean` |' \
  'Lifecycle state model must define the post-restore gate'
require_text "$state_model" \
  '`exact-bound` means all durable state currently present is complete and bound' \
  'Lifecycle state model must preserve restart at exact checkpoint boundaries'
require_text "$state_model" \
  '## Command Guard And Effect Matrix' \
  'Lifecycle state model must define exact command guards'
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
  '`init-run -> create -> start`.' \
  'Lifecycle state model must distinguish reuse from post-destroy creation'
require_text "$state_model" \
  '## Persistence And Concurrency' \
  'Lifecycle state model must define persistence and locking'
require_text "$state_model" \
  '## Checkpoint State Transitions' \
  'Lifecycle state model must define checkpoint state transitions'
require_text "$state_model" \
  '## Product-To-Simulation Checkpoint Mapping' \
  'Lifecycle state model must define the product checkpoint realization'
require_text "$state_model" \
  'It answers which ledger state' \
  'Lifecycle state model must state its valid-state responsibility'
require_text "$state_model" \
  '`simulation/docs/checkpoint-acceptance-protocol.md` separately owns the' \
  'Lifecycle state model must delegate the acceptance protocol'
require_text "$state_model" \
  'does not define owning-layer postconditions, evidence acceptance, or transaction' \
  'Lifecycle state model must exclude acceptance-protocol responsibilities'
require_text "$state_model" \
  '| `open-checkpoint(<checkpoint>, <activity>)` |' \
  'Lifecycle state model must define the checkpoint-open transition'
require_text "$state_model" \
  '| `commit-checkpoint(<record>)` |' \
  'Lifecycle state model must define the checkpoint-commit transition'
require_text "$state_model" \
  '`evidence_sha256`' \
  'Lifecycle state model must own the workflow evidence-digest field'
require_text "$state_model" \
  'The concrete role expansions and five unqualified identifiers in the final' \
  'Lifecycle state model must own the exact workflow vocabulary'
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
  '# Simulation Checkpoint Acceptance Protocol' \
  'Checkpoint protocol must be explicitly acceptance-scoped'
require_text "$protocol" \
  '## Accepted Records' \
  'Checkpoint protocol must distinguish accepted record types'
require_text "$protocol" \
  '## Acceptance Requirements' \
  'Checkpoint protocol must define owned-result acceptance'
require_text "$protocol" \
  '## Publication Protocol' \
  'Checkpoint protocol must define publication ordering'
require_text "$protocol" \
  '## Failure Protocol' \
  'Checkpoint protocol must define proof failure handling'
require_text "$protocol" \
  'Only the workflow head and its immutable checkpoint chain authorize' \
  'Checkpoint protocol must preserve one progression authority'
require_text "$protocol" \
  'This protocol invokes `open-checkpoint` and `commit-checkpoint`' \
  'Checkpoint protocol must consume state-model transitions'
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

require_text "$lifecycle" \
  '`simulation/docs/lifecycle-state-model.md` owns exact simulation state' \
  'Lifecycle authority must delegate exact simulation state realization'
require_text "$lifecycle" \
  'checkpoint mapping;' \
  'Lifecycle authority must delegate the simulation checkpoint mapping'
require_text "$lifecycle" \
  '`simulation/docs/checkpoint-acceptance-protocol.md` owns acceptance and' \
  'Lifecycle authority must delegate checkpoint acceptance'
reject_text "$lifecycle" \
  'restored-pending-clean' \
  'Product lifecycle authority must not define a simulation reset gate'
require_text "$state_model" \
  'RestoredPendingClean --> BaselineStoppedUnclaimed: clean' \
  'Lifecycle state model must own the cleanup release transition'

require_text "$vm_design" \
  '# VM Simulation Harness Implementation Design' \
  'VM design must be explicitly implementation-scoped'
require_text "$vm_design" \
  '`simulation/docs/harness-design.md` owns shared harness architecture' \
  'VM implementation design must delegate shared architecture'
require_text "$vm_design" \
  '`simulation/docs/lifecycle-state-model.md` owns simulation-set state' \
  'VM implementation design must delegate shared lifecycle state'
require_text "$vm_design" \
  '`simulation/docs/checkpoint-acceptance-protocol.md` owns result' \
  'VM implementation design must delegate checkpoint acceptance'
require_text "$docker_design" \
  '`simulation/docs/checkpoint-acceptance-protocol.md` owns result' \
  'Docker implementation design must delegate checkpoint acceptance'
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
  '## M5: Workflow-Ledger Cutover And Evidence Alignment' \
  'Step 13c must schedule the executable workflow-ledger cutover'
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
