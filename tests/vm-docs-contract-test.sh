#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

require_doc_text() {
  local file pattern message
  file="${1:?file required}"
  pattern="${2:?pattern required}"
  message="${3:?message required}"
  if ! grep -Fq -- "$pattern" "$repo_root/$file"; then
    printf '%s\n' "$message" >&2
    exit 1
  fi
}

reject_doc_text() {
  local file pattern message
  file="${1:?file required}"
  pattern="${2:?pattern required}"
  message="${3:?message required}"
  if grep -Fq -- "$pattern" "$repo_root/$file"; then
    printf '%s\n' "$message" >&2
    exit 1
  fi
}

reject_mermaid_semicolons() {
  local file
  file="${1:?file required}"
  awk '
    /^```mermaid$/ { in_mermaid = 1; next }
    in_mermaid && /^```$/ { in_mermaid = 0; next }
    in_mermaid && /;/ {
      printf "Mermaid block contains a statement-separating semicolon at line %d\n", NR > "/dev/stderr"
      invalid = 1
    }
    END { exit invalid }
  ' "$repo_root/$file"
}

require_doc_text simulation/docs/shared/simulation-model.md \
  '## Shared Command Semantics' \
  'Shared simulation docs must own command semantics'
require_doc_text simulation/docs/shared/lifecycle-state-model.md \
  'then removes the active-run pointer last.' \
  'Lifecycle state model must own clean review-state behavior'
reject_doc_text simulation/docs/vm/vm-simulation.md \
  'removes the active-run pointer last.' \
  'VM simulation guide must not restate shared clean behavior'
require_doc_text simulation/docs/vm/vm-simulation.md \
  'The ownership-checked `destroy` command removes the transient domain, bake' \
  'VM simulation guide must own failed-bake state cleanup'
reject_doc_text docs/contracts/lifecycle-contract.md \
  '## Simulation Command Relationship' \
  'Product lifecycle contract must not own simulation commands'
reject_doc_text docs/contracts/lifecycle-contract.md \
  'HARNESS_RUN_ID' \
  'Product lifecycle contract must not own simulation run identity'
reject_doc_text docs/contracts/lifecycle-contract.md \
  'restore-baseline' \
  'Product lifecycle contract must not own backend restoration commands'
reject_doc_text docs/contracts/lifecycle-contract.md \
  '| VM command | Lifecycle checkpoint |' \
  'Lifecycle contract must not duplicate the VM command reference table'
reject_doc_text docs/contracts/lifecycle-contract.md \
  '| Docker command | Lifecycle checkpoint |' \
  'Lifecycle contract must not duplicate the Docker command reference table'
reject_doc_text docs/contracts/lifecycle-contract.md \
  'VM simulation infrastructure provisioning for the selected reusable VM set' \
  'Lifecycle contract must not duplicate detailed VM implementation behavior'

require_doc_text simulation/docs/shared/generated-state-layout.md \
  '## VM Realization' \
  'Generated-state layout must own VM simulation backing paths'
require_doc_text simulation/docs/shared/generated-state-layout.md \
  'generated/simulation/<backend>/sets/<set-id>/' \
  'Generated-state layout must document reusable simulation-set state root'
require_doc_text simulation/docs/vm/vm-simulation.md \
  'generated/simulation/vm/<run-id>/' \
  'VM guide must document its concrete run-scoped realization'
require_doc_text simulation/docs/shared/generated-state-layout.md \
  '`sets/<set-id>/libvirt/`' \
  'Generated-state layout must document VM libvirt metadata backing'
require_doc_text simulation/docs/shared/generated-state-layout.md \
  '`sets/<set-id>/snapshots/`' \
  'Generated-state layout must document VM baseline snapshot records'
require_doc_text simulation/docs/shared/generated-state-layout.md \
  'Jenkins-agent-hosted shared storage exported to the controller VM' \
  'Generated-state layout must document Jenkins-agent-hosted VM shared storage'
require_doc_text simulation/docs/shared/generated-state-layout.md \
  '`host/artifacts/exported/`' \
  'Generated-state layout must document VM host-owned artifact review copies'
require_doc_text docs/contracts/directory-model.md \
  '## Operator Input Custody' \
  'Directory model must own operator input custody paths'
require_doc_text docs/contracts/directory-model.md \
  '`/home/<operator-account>/loopforge-inputs/<role>.env`' \
  'Directory model must define the configurable canonical role env path'
require_doc_text docs/contracts/directory-model.md \
  '`/home/ci-operator/loopforge-inputs/<role>.env`' \
  'Directory model must name the default operator role env path'
require_doc_text docs/contracts/directory-model.md \
  '| `0700` |' \
  'Directory model must protect the operator input directory'
require_doc_text docs/contracts/directory-model.md \
  '| `0600` |' \
  'Directory model must protect reviewed role env files'
require_doc_text docs/contracts/directory-model.md \
  '`gerrit`, `jenkins-controller`, or `jenkins-agent`' \
  'Directory model must constrain canonical role env filenames'
require_doc_text docs/contracts/directory-model.md \
  '`bundle-factory/` directory are not part of the canonical path' \
  'Directory model must require a flat factory and target role env layout'
require_doc_text docs/contracts/directory-model.md \
  '## Role Helper Custody' \
  'Directory model must own role-helper execution paths'
require_doc_text docs/contracts/directory-model.md \
  '`/home/<operator-account>/loopforge/`' \
  'Directory model must define the configurable canonical role-helper root'
require_doc_text docs/contracts/directory-model.md \
  '`/home/ci-operator/loopforge/`' \
  'Directory model must name the default role-helper root'
require_doc_text docs/contracts/directory-model.md \
  'Root and directories `0755`; regular files `0644`; role helper scripts `0755`' \
  'Directory model must keep role helpers executable non-secret control-plane input'
require_doc_text docs/contracts/directory-model.md \
  'Loopforge permissions are classified by data sensitivity' \
  'Directory model must document sensitivity-based permission classes'
require_doc_text docs/contracts/directory-model.md \
  'Run IDs and role-specific package directories are not part of the' \
  'Directory model must require one shared role-helper tree'
require_doc_text simulation/docs/shared/generated-state-layout.md \
  'VM artifact staging uses target OS SSH' \
  'Generated-state layout must document VM staging through target OS SSH'
require_doc_text simulation/docs/shared/generated-state-layout.md \
  '`/var/lib/loopforge/staging/<role>/`' \
  'Generated-state layout must document VM guest-local canonical staging'
reject_doc_text simulation/docs/shared/generated-state-layout.md \
  'VM-to-target transfer scratch' \
  'Generated-state layout must not model VM staging as transfer scratch'

require_doc_text docs/baselines/package-requirements.md \
  'Linux host with libvirt/KVM access' \
  'Package requirements must document VM libvirt/KVM host prerequisite'
require_doc_text docs/baselines/package-requirements.md \
  '`virsh`' \
  'Package requirements must document virsh as VM simulation tooling'
require_doc_text docs/baselines/package-requirements.md \
  'cloud-init or seed media tooling' \
  'Package requirements must document VM seed media tooling'
require_doc_text docs/baselines/package-requirements.md \
  'NFS packages for shared Jenkins storage are guest VM dependencies' \
  'Package requirements must place VM NFS packages in guests'
require_doc_text docs/baselines/package-requirements.md \
  '`nfs-kernel-server`' \
  'Package requirements must document Jenkins agent NFS server package'
require_doc_text docs/baselines/package-requirements.md \
  '`nfs-common`' \
  'Package requirements must document Jenkins controller NFS client package'
require_doc_text docs/baselines/package-requirements.md \
  '| VM LDAP guest | `slapd` for the simulation-owned LDAP service' \
  'Package requirements must document the VM LDAP guest service package'
require_doc_text docs/baselines/package-requirements.md \
  '`ldap-utils` for LDAP bind/search readiness and seed proof' \
  'Package requirements must document VM LDAP proof tooling'
require_doc_text docs/baselines/package-requirements.md \
  '`flock` serializes selected VM-set base-image preparation' \
  'Package requirements must document VM-set base-image locking'
require_doc_text docs/baselines/package-requirements.md \
  'VM LDAP guest service' \
  'Package requirements evidence map must include VM LDAP guest service'
require_doc_text docs/baselines/package-requirements.md \
  'VM simulation realizes role target OS dependency baselines during VM' \
  'Package requirements must place VM role OS dependencies in provisioning'
require_doc_text docs/baselines/package-requirements.md \
  'they do not install Ubuntu/OS' \
  'Package requirements must keep role helpers out of OS dependency installation'

require_doc_text docs/contracts/validation-and-evidence.md \
  'an opaque execution-binding fingerprint supplied by the mode coordinator.' \
  'Evidence contract must require opaque execution binding'
require_doc_text docs/contracts/validation-and-evidence.md \
  'Workflow predecessors, run-plan' \
  'Evidence contract must keep orchestration identity out of producer records'
require_doc_text simulation/docs/shared/operation-records.md \
  'Safe resource, baseline, and input fingerprints' \
  'Operation-record contract must bind baseline operations'
require_doc_text simulation/docs/shared/operation-records.md \
  '| `reboot` | `reboot` operation record |' \
  'Operation-record contract must classify reboot as simulation lifecycle'
require_doc_text docs/contracts/validation-and-evidence.md \
  'agent VM hosts the NFS-backed `/data/jenkins-shared` export' \
  'Evidence contract must require VM shared storage proof'
require_doc_text simulation/docs/vm/vm-simulation.md \
  'The harness must prove LDAP' \
  'VM contract must require LDAP service readiness proof'
require_doc_text simulation/docs/vm/vm-simulation.md \
  'service readiness, seeded entry presence, and LDAP bind/search behavior' \
  'VM contract must require seeded LDAP entries and bind/search proof'
require_doc_text docs/contracts/validation-and-evidence.md \
  'must not imply `target-deployment` acceptance' \
  'Evidence contract must keep VM evidence separate from target deployment'

require_doc_text docs/contracts/endpoint-identity.md \
  'VM inventory must not use Docker service names' \
  'Endpoint identity must reject Docker service names in VM inventory'
require_doc_text docs/contracts/endpoint-identity.md \
  'Docker published loopback' \
  'Endpoint identity must reject Docker published loopback ports in VM inventory'
reject_doc_text docs/contracts/endpoint-identity.md \
  '## VM Simulation Endpoint Realization' \
  'Endpoint identity must not duplicate Applied To Loopforge with a VM-only section'

require_doc_text simulation/docs/shared/simulation-model.md \
  'Docker simulation may use explicit simulation-only waivers' \
  'Simulation model must distinguish Docker waivers from VM behavior'
require_doc_text simulation/docs/shared/simulation-model.md \
  'VM simulation is expected to be stricter' \
  'Simulation model must require stricter VM simulation'
require_doc_text simulation/docs/shared/simulation-model.md \
  'near target deployment' \
  'Simulation model must define VM as near target deployment'
require_doc_text simulation/docs/shared/simulation-model.md \
  'realize LDAP as a simulation-owned directory' \
  'Simulation model must require real simulation LDAP behavior'
require_doc_text simulation/docs/shared/simulation-model.md \
  'They must not satisfy LDAP readiness' \
  'Simulation model must reject modeled LDAP readiness'
require_doc_text simulation/docs/shared/simulation-model.md \
  '| `gerrit-admin` | LDAP user | `admin-password` | Gerrit administrator login. |' \
  'Simulation model must document the seeded Gerrit admin account'
require_doc_text simulation/docs/shared/simulation-model.md \
  '| `jenkins-admin` | LDAP user | `admin-password` | Jenkins administrator login. |' \
  'Simulation model must document the seeded Jenkins admin account'
require_doc_text simulation/docs/shared/simulation-model.md \
  '| `test-user` | LDAP user | `test-password` | Disposable Gerrit login and change workflow user. |' \
  'Simulation model must document the seeded test account'
require_doc_text simulation/docs/shared/simulation-model.md \
  '| `readonly` / `cn=readonly,dc=example,dc=test` | LDAP bind account | `readonly-password` | Read-only Gerrit and Jenkins directory search account. |' \
  'Simulation model must document the seeded LDAP bind account'
require_doc_text simulation/docs/shared/simulation-model.md \
  '## Terminal Output Convention' \
  'Simulation model must document the terminal output convention'
require_doc_text simulation/docs/shared/simulation-model.md \
  '`simulation/docs/shared/terminal-output.md` owns shared simulation terminal presentation' \
  'Simulation model must point terminal convention to the companion doc'
require_doc_text simulation/docs/shared/terminal-output.md \
  '# Simulation Terminal Output' \
  'Terminal output companion doc must exist'
require_doc_text simulation/docs/shared/terminal-output.md \
  'Routine command success should use compact summary lines' \
  'Terminal output companion doc must define compact command summaries'
require_doc_text simulation/docs/shared/terminal-output.md \
  'Commands must not claim success when proof is missing.' \
  'Terminal output companion doc must require honest command states'
require_doc_text simulation/docs/shared/terminal-output.md \
  'Failure summaries should start with a compact reason' \
  'Terminal output companion doc must define compact failure summaries'
require_doc_text simulation/docs/shared/terminal-output.md \
  'The `status` command is an operator-facing summary, not an audit report.' \
  'Terminal output companion doc must keep status operator-facing'
require_doc_text simulation/docs/shared/terminal-output.md \
  'Layers must not force identical backend fields when' \
  'Terminal output companion doc must allow layer-specific status fields'
require_doc_text simulation/docs/shared/terminal-output.md \
  'uses the shared `Login accounts` table convention' \
  'Terminal output companion doc must document the login accounts table convention'
require_doc_text simulation/docs/shared/terminal-output.md \
  'integration service accounts as password-backed login accounts' \
  'Terminal output companion doc must prohibit password-backed integration accounts in status'
require_doc_text simulation/docs/shared/terminal-output.md \
  '## Summary Preview' \
  'Terminal output companion doc must include command summary previews'
require_doc_text simulation/docs/shared/terminal-output.md \
  '## Docker Preview' \
  'Terminal output companion doc must include a Docker preview'
require_doc_text simulation/docs/shared/terminal-output.md \
  '## VM Preview' \
  'Terminal output companion doc must include a VM preview'
require_doc_text simulation/docs/shared/terminal-output.md \
  'not print raw libvirt URIs, VM resource marker values, domain dumps, Docker' \
  'Terminal output companion doc must keep backend internals out of normal output'

require_doc_text simulation/docs/vm/vm-simulation.md \
  'The VM layer uses the shared topology, account model, version baseline, source' \
  'VM simulation guide must point to shared simulation authorities'
require_doc_text simulation/docs/vm/vm-simulation.md \
  'The LDAP VM must run a real LDAP service' \
  'VM simulation guide must require a real LDAP service on the LDAP VM'
require_doc_text simulation/docs/vm/vm-simulation.md \
  'simulation-owned directory with the entries defined in `simulation/docs/shared/simulation-model.md`' \
  'VM simulation guide must point seeded LDAP users and groups to the shared simulation model'
require_doc_text simulation/docs/vm/vm-simulation.md \
  'before the clean baseline snapshot is captured' \
  'VM simulation guide must require LDAP seeding before baseline'
require_doc_text simulation/docs/vm/vm-simulation.md \
  'service readiness, seeded entry presence, and LDAP' \
  'VM simulation guide must require LDAP service and seed verification'
require_doc_text simulation/docs/vm/vm-simulation.md \
  '`simulation/vm/ldap/50-harness-seed.ldif`' \
  'VM simulation guide must document the VM LDAP seed source'
require_doc_text simulation/docs/vm/vm-simulation.md \
  'LDAP endpoint is reachable from the Gerrit and Jenkins controller VMs' \
  'VM simulation guide must require LDAP reachability from consuming VMs'
require_doc_text simulation/docs/vm/vm-simulation.md \
  '`simulation/lib/`' \
  'VM simulation guide must point implementation at shared simulation helpers'
require_doc_text simulation/docs/vm/vm-simulation.md \
  '## Near-Target Lifecycle Boundary' \
  'VM simulation guide must define the near-target lifecycle boundary'
require_doc_text simulation/docs/vm/vm-simulation.md \
  'VM simulation is expected to be near target deployment for product checkpoint' \
  'VM simulation guide must require near-target checkpoint execution'
require_doc_text simulation/docs/vm/vm-simulation.md \
  '## Shared Base-Image Service Waiver' \
  'VM simulation guide must document the shared-image service waiver'
require_doc_text simulation/docs/vm/vm-simulation.md \
  'does not apply to target deployment' \
  'VM service waiver must not weaken target deployment'
require_doc_text simulation/docs/vm/milestone-verification.md \
  '## Shared Base-Image Service Waiver Gate' \
  'VM verification must define the shared-image waiver gate'
require_doc_text simulation/docs/vm/milestone-verification.md \
  '`audit-state: ok` is necessary but not sufficient' \
  'VM waiver verification must not rely on audit-state alone'
require_doc_text simulation/docs/vm/vm-simulation.md \
  'VM provisioning must satisfy the role target OS dependency baselines before' \
  'VM simulation guide must place role OS dependencies before baseline snapshot'
require_doc_text simulation/docs/vm/vm-simulation.md \
  'automatic baked base-image' \
  'VM simulation guide must allow create-owned baked base-image preparation'
require_doc_text simulation/docs/vm/vm-simulation.md \
  'successful LDAP operation with no matching entries is a failure' \
  'VM simulation guide must require exact LDAP entry proof'
require_doc_text simulation/docs/vm/vm-simulation.md \
  'set-local base image' \
  'VM simulation guide must document simulation-set-local base-image ownership'
require_doc_text simulation/docs/vm/vm-simulation.md \
  'account-scoped OpenSSH policy' \
  'VM simulation guide must document the operator SSH seed policy'
require_doc_text simulation/docs/vm/vm-simulation.md \
  'failed cloud-init module blocks readiness' \
  'VM simulation guide must require successful cloud-init completion'
require_doc_text simulation/docs/vm/vm-simulation.md \
  '`VM_DEBUG_PRESERVE_FAILED_BAKE=1`' \
  'VM simulation guide must document failed bake debug preservation'
require_doc_text simulation/docs/vm/vm-simulation.md \
  'while the debug marker exists so the next attempt' \
  'VM simulation guide must protect preserved bake evidence from create reruns'
require_doc_text simulation/vm/examples/vm.env.example \
  'VM_DEBUG_PRESERVE_FAILED_BAKE=0' \
  'VM example environment must keep bake debug preservation opt-in'
require_doc_text simulation/docs/vm/vm-simulation.md \
  'become libvirt-managed volumes' \
  'VM simulation guide must define libvirt-managed image ownership'
require_doc_text simulation/docs/vm/vm-simulation.md \
  "libvirt-reported path as a file-backed" \
  'VM simulation guide must use file-backed attachment for managed volumes'
require_doc_text simulation/docs/vm/milestone-verification.md \
  'without requiring direct host file access' \
  'VM verification must avoid operator reads of managed images'
require_doc_text simulation/docs/shared/generated-state-layout.md \
  'Libvirt directory-pool target' \
  'Generated-state layout must identify libvirt-managed VM image paths'
require_doc_text simulation/docs/vm/vm-simulation.md \
  'Legacy or malformed ownership schemas are conflicting state.' \
  'VM simulation guide must reject legacy ownership fallback'
require_doc_text simulation/docs/vm/vm-simulation.md \
  'name-derived recovery, or compatibility cleanup' \
  'VM simulation guide must reject name-derived legacy cleanup'
require_doc_text simulation/docs/vm/vm-simulation.md \
  'size, and VM package matrix' \
  'VM simulation guide must document baked base-image invalidation inputs'
require_doc_text simulation/docs/vm/vm-simulation.md \
  'they do not install Ubuntu/OS dependencies' \
  'VM simulation guide must keep role helpers out of OS dependency installation'
require_doc_text simulation/docs/vm/vm-simulation.md \
  'checkpoint work must use target-like' \
  'VM simulation guide must require target-like checkpoint interfaces'
require_doc_text simulation/docs/vm/vm-simulation.md \
  'target OS SSH as `ci-operator`' \
  'VM simulation guide must use target OS SSH as the checkpoint control plane'
require_doc_text simulation/docs/vm/vm-simulation.md \
  '`/var/lib/loopforge/staging/<role>`' \
  'VM simulation guide must use guest-local canonical staging'
require_doc_text simulation/docs/vm/vm-simulation.md \
  'must not use libvirt console access' \
  'VM simulation guide must prohibit libvirt console checkpoint shortcuts'
require_doc_text simulation/docs/vm/vm-simulation.md \
  'direct guest disk or image' \
  'VM simulation guide must prohibit direct guest image edits'
require_doc_text simulation/docs/vm/vm-simulation.md \
  'post-baseline cloud-init' \
  'VM simulation guide must prohibit post-baseline cloud-init checkpoint shortcuts'
require_doc_text simulation/docs/vm/vm-simulation.md \
  'modeled success without' \
  'VM simulation guide must prohibit modeled VM checkpoint success'
require_doc_text simulation/docs/vm/vm-simulation.md \
  '| `create` | Define the reusable simulation set' \
  'VM simulation guide must document VM create realization'
require_doc_text simulation/docs/vm/vm-simulation.md \
  'LDAP service readiness, and LDAP seed verification' \
  'VM simulation guide must place LDAP readiness before baseline snapshot capture'
require_doc_text simulation/docs/vm/vm-simulation.md \
  'OS dependency fulfillment, LDAP service readiness' \
  'VM simulation guide must place role OS dependency fulfillment before baseline snapshot capture'
require_doc_text simulation/docs/vm/milestone-verification.md \
  '`create` baked a simulation-owned dependency-prepared base image' \
  'VM verification must require baked base-image proof for M4'
require_doc_text simulation/docs/vm/milestone-verification.md \
  'each VM proves the expected packages and commands are available from the' \
  'VM verification must keep per-VM package and command proof after baking'
require_doc_text simulation/docs/vm/vm-simulation.md \
  '| `reboot` | Reboots selected running guests through the guest OS' \
  'VM simulation guide must document VM reboot realization'
require_doc_text simulation/docs/vm/vm-simulation.md \
  '`restore-baseline` is destructive to guest disk changes made after the' \
  'VM simulation guide must document restore-baseline as snapshot rollback, not VM deletion'
require_doc_text simulation/docs/vm/vm-simulation.md \
  '| `clean` | Applies the shared mutable-run cleanup without changing guest disks' \
  'VM simulation guide must document VM clean realization only'
require_doc_text simulation/docs/vm/vm-simulation.md \
  '| `destroy` | Undefine selected VM domains and remove owned storage' \
  'VM simulation guide must document libvirt destroy realization'
require_doc_text simulation/docs/vm/vm-simulation.md \
  '| `destroy` | Removes only ownership-validated selected domains' \
  'VM simulation guide must document VM destroy realization'
require_doc_text simulation/docs/vm/vm-simulation.md \
  'set-local base image' \
  'VM simulation guide must document destroy removes local base image'
require_doc_text simulation/docs/shared/generated-state-layout.md \
  'set-local base image' \
  'Generated-state layout must define simulation-set-local base-image ownership'
require_doc_text simulation/docs/vm/vm-simulation.md \
  'cleanup-libvirt-resources.sh --dry-run' \
  'VM simulation guide must document host cleanup dry-run'
require_doc_text simulation/docs/vm/vm-simulation.md \
  'host-wide recovery tool' \
  'VM simulation guide must distinguish host cleanup from selected VM-set destroy'
require_doc_text simulation/docs/vm/vm-simulation.md \
  'configure-systemd-resolved.sh --dry-run' \
  'VM simulation guide must document the systemd-resolved split-DNS helper'
require_doc_text simulation/docs/vm/vm-simulation.md \
  '`simulation/vm/examples/vm.env.example`, matching the VM simulation CLI' \
  'VM systemd-resolved helper must document default --env behavior'
require_doc_text simulation/docs/vm/vm-simulation.md \
  '`--apply` and `--revert` require non-interactive sudo' \
  'VM systemd-resolved helper must document no-sudo fail-fast behavior'
require_doc_text simulation/docs/vm/vm-simulation.md \
  'mutate only systemd-resolved'\''s temporary per-link runtime' \
  'VM systemd-resolved helper must document temporary-only runtime behavior'
require_doc_text simulation/docs/vm/vm-simulation.md \
  'does not edit `/etc/hosts`' \
  'VM systemd-resolved helper must not be documented as persistent host DNS mutation'
require_doc_text simulation/docs/vm/vm-simulation.md \
  'Exported artifact review copies' \
  'VM simulation guide must document exported artifacts as review copies'
require_doc_text simulation/docs/vm/vm-simulation.md \
  'Artifact staging to service VMs uses target OS SSH' \
  'VM simulation guide must document target OS SSH artifact staging'
reject_doc_text simulation/docs/vm/vm-simulation.md \
  'generated/simulation/vm/<run-id>/target/artifacts/staging' \
  'VM simulation guide must not model VM staging as generated target sideband'

reject_doc_text simulation/docs/vm/vm-simulation.md \
  'Docker service names such as `gerrit-target`' \
  'VM simulation guide must not use Docker service names as VM endpoint identities'

require_doc_text docs/planning/steps/step-13-vm-simulation-harness.md \
  'simulation/docs/vm/vm-simulation.md` for the public VM command contract' \
  'Step 13 plan must point public VM behavior to the VM simulation guide'
require_doc_text docs/planning/steps/step-13-vm-simulation-harness.md \
  'simulation/docs/vm/implementation-design.md` for VM module boundaries and' \
  'Step 13 plan must point internal VM design to the VM design doc'
require_doc_text docs/planning/steps/step-13-vm-simulation-harness.md \
  'simulation/docs/vm/decisions/libvirt-module-refactor.md` for the accepted libvirt, VM-set,' \
  'Step 13 plan must name the accepted libvirt refactor companion'
require_doc_text docs/planning/steps/step-13-vm-simulation-harness.md \
  'simulation/docs/vm/command-sequences.md` for command flow' \
  'Step 13 plan must point VM command flow to the sequence companion doc'
require_doc_text docs/planning/steps/step-13-vm-simulation-harness.md \
  'M2-M8 verification remains milestone-scoped' \
  'Step 13 plan must preserve milestone-scoped verification'
require_doc_text docs/planning/steps/step-13-vm-simulation-harness.md \
  'Local-only milestones must not mutate VM, libvirt, host, guest, Gerrit,' \
  'Step 13 plan must preserve local-only non-mutating scope'
require_doc_text docs/planning/steps/step-13-vm-simulation-harness.md \
  'libvirt preflight and VM-set ownership validation enabled' \
  'Step 13 plan must preserve M2 libvirt preflight and VM-set ownership validation scope'
require_doc_text docs/planning/steps/step-13-vm-simulation-harness.md \
  '| M4 | Add `tests/vm-harness-ldap-seed-test.sh`; verify role OS dependency baseline readiness' \
  'Step 13 M4 must prove role OS dependencies and LDAP before baseline snapshot'
require_doc_text docs/planning/steps/step-13-vm-simulation-harness.md \
  '| M5 | Run `restore-baseline`, `clean`, `destroy`, and `audit-state`; verify rollback' \
  'Step 13 M5 must perform restore/clean/destroy after baseline prerequisites'
require_doc_text simulation/docs/vm/implementation-design.md \
  '| M4 Baseline prerequisites: role OS dependencies and LDAP proof |' \
  'VM design M4 must own baseline prerequisites'
require_doc_text simulation/docs/vm/implementation-design.md \
  '| M5 Baseline snapshot, restore, clean, and destroy |' \
  'VM design M5 must own baseline snapshot restore, clean, and destroy'
require_doc_text simulation/docs/vm/implementation-design.md \
  'simulation/docs/vm/decisions/libvirt-module-refactor.md`' \
  'VM design must name the accepted libvirt refactor companion'
require_doc_text simulation/docs/vm/decisions/libvirt-module-refactor.md \
  'This decision is implemented.' \
  'VM libvirt refactor companion must record its implemented status'
require_doc_text simulation/docs/vm/decisions/libvirt-module-refactor.md \
  '`lifecycle -> vm-set/baseline/snapshots -> libvirt/ssh/state -> config/paths`' \
  'VM libvirt refactor companion must define the target dependency direction'
require_doc_text simulation/docs/vm/decisions/libvirt-module-refactor.md \
  'The public CLI is unchanged.' \
  'VM libvirt refactor companion must preserve the public CLI'
require_doc_text simulation/docs/vm/command-sequences.md \
  'verify role OS dependency baselines' \
  'VM create sequence must verify role OS dependency baselines before snapshot'
require_doc_text simulation/docs/vm/command-sequences.md \
  'participant RUN as lifecycle.sh: vm_cmd_run' \
  'VM command sequences must diagram composite run dispatch'
require_doc_text simulation/docs/vm/command-sequences.md \
  'vm_command_with_lock(lock mode, vm_cmd_phase)' \
  'VM run sequence must reuse phase handlers through their normal locks'
require_doc_text simulation/docs/vm/command-sequences.md \
  'RUN-->>CLI: same nonzero result and stop plan' \
  'VM run sequence must propagate the first command failure'
require_doc_text simulation/docs/vm/command-sequences.md \
  'an already-running completed run uses `status`' \
  'VM run sequence must retain the intentional completed-run status output'
reject_mermaid_semicolons simulation/docs/vm/command-sequences.md
