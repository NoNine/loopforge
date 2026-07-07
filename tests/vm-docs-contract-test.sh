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

require_doc_text docs/lifecycle-contract.md \
  '## Simulation Command Relationship' \
  'Lifecycle contract must describe simulation command relationship'
require_doc_text docs/lifecycle-contract.md \
  '`simulation/README.md` owns shared simulation command semantics.' \
  'Lifecycle contract must point to shared simulation command semantics'
require_doc_text docs/lifecycle-contract.md \
  '`simulation/docker/README.md` and `simulation/vm/README.md` own the concrete' \
  'Lifecycle contract must point concrete command references to layer docs'
require_doc_text docs/lifecycle-contract.md \
  'outside the checkpoint progression' \
  'Lifecycle contract must keep utility commands outside checkpoint progression'
require_doc_text docs/lifecycle-contract.md \
  '`clean` must preserve review artifacts' \
  'Lifecycle contract must preserve VM clean review artifacts'
require_doc_text docs/lifecycle-contract.md \
  'must not delete the reusable VM set' \
  'Lifecycle contract must separate VM clean from destroy'
require_doc_text docs/lifecycle-contract.md \
  'Only `destroy` removes' \
  'Lifecycle contract must define VM destroy as resource deletion'
require_doc_text docs/lifecycle-contract.md \
  'simulation-owned VM resources.' \
  'Lifecycle contract must identify deleted VM resources'
reject_doc_text docs/lifecycle-contract.md \
  '| VM command | Lifecycle checkpoint |' \
  'Lifecycle contract must not duplicate the VM command reference table'
reject_doc_text docs/lifecycle-contract.md \
  '| Docker command | Lifecycle checkpoint |' \
  'Lifecycle contract must not duplicate the Docker command reference table'
reject_doc_text docs/lifecycle-contract.md \
  'VM simulation infrastructure provisioning for the selected reusable VM set' \
  'Lifecycle contract must not duplicate detailed VM implementation behavior'

require_doc_text docs/directory-model.md \
  '## VM Simulation Backing' \
  'Directory model must own VM simulation backing paths'
require_doc_text docs/directory-model.md \
  'generated/simulation/vm/vm-sets/<vm-set-id>/' \
  'Directory model must document reusable VM-set state root'
require_doc_text docs/directory-model.md \
  'generated/simulation/vm/<run-id>/' \
  'Directory model must document VM run-scoped output root'
require_doc_text docs/directory-model.md \
  '`vm-sets/<vm-set-id>/libvirt/`' \
  'Directory model must document VM libvirt metadata backing'
require_doc_text docs/directory-model.md \
  '`vm-sets/<vm-set-id>/snapshots/`' \
  'Directory model must document VM baseline snapshot records'
require_doc_text docs/directory-model.md \
  'VM-set-owned Jenkins shared storage' \
  'Directory model must document VM-set-owned Jenkins shared storage'
require_doc_text docs/directory-model.md \
  '`host/artifacts/exported/`' \
  'Directory model must document VM host-owned artifact review copies'
require_doc_text docs/directory-model.md \
  'VM artifact staging uses target OS SSH' \
  'Directory model must document VM staging through target OS SSH'
require_doc_text docs/directory-model.md \
  '`/var/lib/loopforge/staging/<role>/`' \
  'Directory model must document VM guest-local canonical staging'
reject_doc_text docs/directory-model.md \
  'VM-to-target transfer scratch' \
  'Directory model must not model VM staging as generated transfer scratch'

require_doc_text docs/package-requirements.md \
  'Linux host with libvirt/KVM access' \
  'Package requirements must document VM libvirt/KVM host prerequisite'
require_doc_text docs/package-requirements.md \
  '`virsh`' \
  'Package requirements must document virsh as VM simulation tooling'
require_doc_text docs/package-requirements.md \
  'cloud-init or seed media tooling' \
  'Package requirements must document VM seed media tooling'
require_doc_text docs/package-requirements.md \
  'NFS utilities for shared Jenkins storage' \
  'Package requirements must document VM shared-storage tooling'

require_doc_text docs/validation-and-evidence.md \
  'VM simulation evidence must identify the selected `vm_set_id` and `run_id`' \
  'Evidence contract must require VM set and run identity'
require_doc_text docs/validation-and-evidence.md \
  'baseline snapshot' \
  'Evidence contract must require VM baseline snapshot evidence'
require_doc_text docs/validation-and-evidence.md \
  '`reboot` evidence' \
  'Evidence contract must require VM reboot evidence'
require_doc_text docs/validation-and-evidence.md \
  'NFS-backed Jenkins shared storage' \
  'Evidence contract must require VM shared storage proof'
require_doc_text docs/validation-and-evidence.md \
  'must not imply `target-deployment` acceptance' \
  'Evidence contract must keep VM evidence separate from target deployment'

require_doc_text docs/endpoint-identity.md \
  'VM inventory must not use Docker service names' \
  'Endpoint identity must reject Docker service names in VM inventory'
require_doc_text docs/endpoint-identity.md \
  'Docker published loopback' \
  'Endpoint identity must reject Docker published loopback ports in VM inventory'
reject_doc_text docs/endpoint-identity.md \
  '## VM Simulation Endpoint Realization' \
  'Endpoint identity must not duplicate Applied To Loopforge with a VM-only section'

require_doc_text simulation/README.md \
  'Docker simulation may use explicit simulation-only waivers' \
  'Shared simulation README must distinguish Docker waivers from VM behavior'
require_doc_text simulation/README.md \
  'VM simulation is expected to be stricter' \
  'Shared simulation README must require stricter VM simulation'
require_doc_text simulation/README.md \
  'near target deployment' \
  'Shared simulation README must define VM as near target deployment'

require_doc_text simulation/vm/README.md \
  'The VM layer uses the shared topology, account model, version baseline, source' \
  'VM README must point to shared simulation authorities'
require_doc_text simulation/vm/README.md \
  '`simulation/lib/`' \
  'VM README must point implementation at shared simulation helpers'
require_doc_text simulation/vm/README.md \
  '## Near-Target Lifecycle Boundary' \
  'VM README must define the near-target lifecycle boundary'
require_doc_text simulation/vm/README.md \
  'VM simulation is expected to be near target deployment for lifecycle' \
  'VM README must require near-target checkpoint execution'
require_doc_text simulation/vm/README.md \
  'checkpoint work must use target-like' \
  'VM README must require target-like checkpoint interfaces'
require_doc_text simulation/vm/README.md \
  'target OS SSH as `ci-operator`' \
  'VM README must use target OS SSH as the checkpoint control plane'
require_doc_text simulation/vm/README.md \
  '`/var/lib/loopforge/staging/<role>`' \
  'VM README must use guest-local canonical staging'
require_doc_text simulation/vm/README.md \
  'must not use libvirt console access' \
  'VM README must prohibit libvirt console checkpoint shortcuts'
require_doc_text simulation/vm/README.md \
  'direct guest disk or image' \
  'VM README must prohibit direct guest image edits'
require_doc_text simulation/vm/README.md \
  'post-baseline cloud-init' \
  'VM README must prohibit post-baseline cloud-init checkpoint shortcuts'
require_doc_text simulation/vm/README.md \
  'modeled success without' \
  'VM README must prohibit modeled VM checkpoint success'
require_doc_text simulation/vm/README.md \
  '`create [--env FILE]` | Defines or verifies the selected reusable libvirt/KVM VM set' \
  'VM README must document create behavior'
require_doc_text simulation/vm/README.md \
  '`reboot [--env FILE] [--role ROLE\|--all]` | Reboots selected running VM targets through the guest OS' \
  'VM README must document reboot behavior'
require_doc_text simulation/vm/README.md \
  '`clean` is destructive to guest disk changes made after the baseline snapshot' \
  'VM README must document clean as snapshot rollback, not VM deletion'
require_doc_text simulation/vm/README.md \
  'Use `destroy` only when the reusable VM set should be permanently removed.' \
  'VM README must document destroy as permanent VM-set removal'
require_doc_text simulation/vm/README.md \
  'Exported artifact review copies' \
  'VM README must document exported artifacts as review copies'
require_doc_text simulation/vm/README.md \
  'Artifact staging to service VMs uses target OS SSH' \
  'VM README must document target OS SSH artifact staging'
reject_doc_text simulation/vm/README.md \
  'generated/simulation/vm/<run-id>/target/artifacts/staging' \
  'VM README must not model VM staging as generated target sideband'

reject_doc_text simulation/vm/README.md \
  'Docker service names such as `gerrit-target`' \
  'VM README must not use Docker service names as VM endpoint identities'
