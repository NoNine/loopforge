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

require_doc_text docs/contracts/account-model.md \
  'local naming standard for the deployment; the examples here describe roles,' \
  'Account model must preserve local naming-standard authority'
require_doc_text docs/contracts/account-model.md \
  'not required literal names.' \
  'Account model must preserve example-name language'
reject_doc_text docs/contracts/account-model.md \
  'This package fixes product runtime' \
  'Account model must not claim product runtime account names are fixed literals'
reject_doc_text docs/contracts/account-model.md \
  'targets must use those runtime identities' \
  'Account model must not claim product runtime account names are fixed literals'

require_doc_text docs/contracts/account-model.md \
  '| Operator account | `ci-operator` | `61000` | `61000` |' \
  'Account model must document the operator example numeric identity'
require_doc_text docs/contracts/account-model.md \
  '| Gerrit runtime account | `gerrit` | `61010` | `61010` |' \
  'Account model must document the Gerrit example numeric identity'
require_doc_text docs/contracts/account-model.md \
  '| Jenkins controller runtime account | `jenkins` | `61020` | `61020` |' \
  'Account model must document the Jenkins controller example numeric identity'
require_doc_text docs/contracts/account-model.md \
  '| Jenkins agent runtime account | `jenkins-agent` | `61030` | `61030` |' \
  'Account model must document the Jenkins agent example numeric identity'
require_doc_text docs/contracts/account-model.md \
  '| Jenkins shared integration group | `jenkins-share` | not applicable | `61040` |' \
  'Account model must document the Jenkins shared group example GID'

require_doc_text docs/contracts/account-model.md \
  'not share a UID in the recommended v1 model.' \
  'Account model must keep Jenkins controller and agent UIDs separate'
require_doc_text docs/contracts/account-model.md \
  'storage access is granted through the dedicated Jenkins shared integration' \
  'Account model must document group-based Jenkins shared storage'
require_doc_text docs/contracts/account-model.md \
  'The shared GID is the cross-host contract for NFS-backed sharing' \
  'Account model must document the shared GID storage contract'
require_doc_text docs/contracts/account-model.md \
  'normally `/data/jenkins-shared`. The Jenkins agent host owns the v1 NFS server' \
  'Account model must document agent-hosted Jenkins shared storage'
require_doc_text docs/contracts/account-model.md \
  'For NFS-backed storage, keep `root_squash` enabled' \
  'Account model must document NFS root_squash guidance'

require_doc_text simulation/README.md \
  'The simulation model derives account roles and numeric identity policy from' \
  'Simulation README must point to the shared account model'
require_doc_text simulation/README.md \
  'default shared group is `jenkins-share` with no UID and GID `61040`.' \
  'Simulation README must document the Jenkins shared group example GID'
require_doc_text simulation/README.md \
  'separate `jenkins-share` integration group from' \
  'Simulation README must document shared storage as group-based access'
require_doc_text simulation/README.md \
  '`scripts/integration-setup.sh` owns creating or' \
  'Simulation README must assign shared storage setup to integration setup'

require_doc_text simulation/docker/README.md \
  'The shared simulation account contract, including seeded LDAP login accounts,' \
  'Docker README must point to the shared simulation account contract'
require_doc_text simulation/docker/README.md \
  'Docker realizes Jenkins shared storage by bind-mounting one run-local' \
  'Docker README must document Docker shared storage realization'
require_doc_text simulation/docker/README.md \
  '`target/shared-jenkins-storage` directory into both the Jenkins controller and' \
  'Docker README must document Docker shared storage bind source'
reject_doc_text simulation/docker/README.md \
  'This local `ci-operator` OS account has' \
  'Docker README must not call target ci-operator the local host account'

require_doc_text simulation/vm/README.md \
  'The shared simulation account contract, including seeded LDAP login accounts,' \
  'VM README must point to the shared simulation account contract'
require_doc_text simulation/vm/README.md \
  'VM simulation models Jenkins shared storage as a Jenkins-agent-hosted' \
  'VM README must document VM shared storage realization'
require_doc_text simulation/vm/README.md \
  'Jenkins runtime home and not a sixth product role.' \
  'VM README must document VM shared storage is not a product role'

for native_reference in \
  docs/operations/native/gerrit.md \
  docs/operations/native/jenkins-controller.md \
  docs/operations/native/jenkins-agent.md; do
  reject_doc_text "$native_reference" \
    '/home/ci-operator' \
    'Native target-deployment references must not hardcode the operator home'
  reject_doc_text "$native_reference" \
    '-o ci-operator -g ci-operator' \
    'Native target-deployment references must not hardcode operator ownership'
  reject_doc_text "$native_reference" \
    'chown -R ci-operator:ci-operator' \
    'Native target-deployment references must not hardcode recursive operator ownership'
done
