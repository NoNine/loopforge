#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
shared_readme="$repo_root/simulation/README.md"
harness_design="$repo_root/simulation/docs/harness-design.md"
state_model="$repo_root/simulation/docs/lifecycle-state-model.md"
coordination="$repo_root/simulation/docs/checkpoint-coordination.md"
docker_design="$repo_root/simulation/docker/docs/implementation-design.md"
vm_design="$repo_root/simulation/vm/docs/implementation-design.md"
lifecycle="$repo_root/docs/contracts/lifecycle-contract.md"

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
  '`simulation/docs/checkpoint-coordination.md`' \
  'Shared simulation README must link checkpoint coordination design'

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
  '`simulation/docs/checkpoint-coordination.md`' \
  'Shared harness design must delegate checkpoint coordination'

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
reject_text "$state_model" \
  '## Workflow Transaction Protocol' \
  'Lifecycle state model must delegate the cross-layer transaction protocol'
require_text "$state_model" \
  '## Exact-Bound Classification' \
  'Lifecycle state model must assign exact-bound classification'
require_text "$state_model" \
  'An interrupted observation may' \
  'Lifecycle state model must separate observational interruption from durable corruption'

require_text "$coordination" \
  '## Ownership Model' \
  'Checkpoint coordination design must assign state ownership'
require_text "$coordination" \
  '## Source-Of-Truth Rules' \
  'Checkpoint coordination design must define one progression authority'
require_text "$coordination" \
  '## Workflow Transaction Protocol' \
  'Checkpoint coordination design must define publication ordering'
require_text "$coordination" \
  '## Existing Marker Disposition' \
  'Checkpoint coordination design must classify historical markers'
require_text "$coordination" \
  'Only `workflow-state.env` and its immutable checkpoint chain authorize' \
  'Checkpoint coordination design must make the ledger authoritative'
require_text "$coordination" \
  'Remove harness-created files whose only meaning is that an orchestration phase' \
  'Checkpoint coordination design must retire duplicate pass markers'

require_text "$lifecycle" \
  '`simulation/docs/lifecycle-state-model.md` owns the exact simulation state' \
  'Lifecycle authority must delegate exact simulation state realization'
require_text "$lifecycle" \
  '`simulation/docs/checkpoint-coordination.md` owns the implementation design' \
  'Lifecycle authority must delegate checkpoint coordination design'
require_text "$lifecycle" \
  'restored-pending-clean -> clean -> baseline-stopped + unclaimed' \
  'Lifecycle authority must include the cleanup release transition'

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
  '`simulation/docs/checkpoint-coordination.md` owns the boundary' \
  'VM implementation design must delegate checkpoint coordination'
require_text "$docker_design" \
  '`simulation/docs/checkpoint-coordination.md` owns the boundary' \
  'Docker implementation design must delegate checkpoint coordination'
reject_text "$vm_design" \
  'matching `validate-integration` marker' \
  'VM implementation design must not retain a duplicate validation marker'
reject_text "$vm_design" \
  'stateDiagram-v2' \
  'VM implementation design must not define a competing lifecycle state diagram'
reject_text "$vm_design" \
  'BaselineRestored --> Running' \
  'VM implementation design must not permit start directly after restoration'

[ ! -e "$repo_root/simulation/vm/docs/design.md" ] || {
  printf '%s\n' 'Obsolete VM design path must not remain after promotion' >&2
  exit 1
}

printf 'Shared simulation design documentation contract passed\n'
