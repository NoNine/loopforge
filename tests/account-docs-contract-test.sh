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

require_doc_text docs/account-model.md \
  'local naming standard for the deployment; the examples here describe roles,' \
  'Account model must preserve local naming-standard authority'
require_doc_text docs/account-model.md \
  'not required literal names.' \
  'Account model must preserve example-name language'
reject_doc_text docs/account-model.md \
  'This package fixes product runtime' \
  'Account model must not claim product runtime account names are fixed literals'
reject_doc_text docs/account-model.md \
  'targets must use those runtime identities' \
  'Account model must not claim product runtime account names are fixed literals'

require_doc_text docs/account-model.md \
  'The operator account is configurable through `LOOPFORGE_OPERATOR_ACCOUNT`.' \
  'Account model must document configurable operator account'
require_doc_text docs/account-model.md \
  'The default example account and' \
  'Account model must document ci-operator as the default example'
require_doc_text docs/account-model.md \
  'group are `ci-operator:ci-operator` for all modes.' \
  'Account model must document ci-operator as the default example'
require_doc_text docs/account-model.md \
  'In Docker simulation, the target-local `ci-operator` OS account has' \
  'Account model must document Docker ci-operator passwordless sudo'
require_doc_text docs/account-model.md \
  'not mean the local host account running `simulate.sh` is named' \
  'Account model must distinguish target ci-operator from host account'
require_doc_text docs/account-model.md \
  'not mapped to the local host username, UID, or GID.' \
  'Account model must forbid mapping target ci-operator to host identity'
require_doc_text docs/account-model.md \
  'The operator account is not a Gerrit or Jenkins runtime account' \
  'Account model must keep the operator account separate from product accounts'
require_doc_text docs/account-model.md \
  '## Numeric Identity Policy' \
  'Account model must document numeric identity policy'
require_doc_text docs/account-model.md \
  'The example target-local identity range is `61000-61999`.' \
  'Account model must document the example numeric identity range'
require_doc_text docs/account-model.md \
  '| Jenkins shared integration group | `jenkins-share` | not applicable | `61040` |' \
  'Account model must document Jenkins shared group example GID'
require_doc_text docs/account-model.md \
  'The Jenkins controller runtime account and Jenkins agent runtime account must' \
  'Account model must reject shared Jenkins controller/agent UID'
require_doc_text docs/account-model.md \
  'not share a UID in the recommended v1 model.' \
  'Account model must reject shared Jenkins controller/agent UID'
require_doc_text docs/account-model.md \
  'The shared GID is the cross-host contract for NFS-backed sharing' \
  'Account model must document NFS shared group numeric contract'
require_doc_text docs/account-model.md \
  'For NFS-backed storage, keep `root_squash` enabled' \
  'Account model must document NFS root_squash guidance'
require_doc_text simulation/docker/README.md \
  'This target-local `ci-operator` OS account has' \
  'Docker README must document ci-operator passwordless sudo'
require_doc_text simulation/docker/README.md \
  'The local host account that invokes `simulate.sh` may have any site-local name' \
  'Docker README must not imply host account is ci-operator'
require_doc_text simulation/docker/README.md \
  'environment as the target-local `ci-operator` through SSH from the host.' \
  'Docker README must document target-local SSH operator login'
require_doc_text simulation/docker/README.md \
  'passwordless sudo for simulation orchestration and privileged helper' \
  'Docker README must document ci-operator passwordless sudo'
require_doc_text simulation/docker/README.md \
  'The operator account does not own `/srv/gerrit`,' \
  'Docker README must document operator account is not a product runtime owner'
require_doc_text simulation/docker/README.md \
  'controller, or Jenkins agent runtime account.' \
  'Docker README must document operator account is not a product runtime owner'
require_doc_text docs/directory-model.md \
  'Host-side generated backing paths use the local host account that runs the simulation' \
  'Directory model must separate host generated ownership from target operator ownership'

reject_doc_text simulation/docker/README.md \
  'This local `ci-operator` OS account has' \
  'Docker README must not call target ci-operator the local host account'

require_doc_text docs/jenkins-agent-native-operations-reference.md \
  'The Jenkins agent role helper requires this account and group to already exist' \
  'Native agent reference must document helper missing-account behavior'
require_doc_text docs/jenkins-agent-native-operations-reference.md \
  'and fails clearly if either is missing or if the passwd HOME is not' \
  'Native agent reference must document helper missing-account behavior'
require_doc_text docs/jenkins-agent-setup-manual.md \
  'The helper requires the configured local runtime account and group to already' \
  'Agent setup manual must document pre-existing runtime account requirement'
require_doc_text docs/jenkins-agent-setup-manual.md \
  'exist.' \
  'Agent setup manual must document pre-existing runtime account requirement'
require_doc_text docs/jenkins-agent-setup-manual.md \
  'provisioning is outside the helper.' \
  'Agent setup manual must document account provisioning is outside helper'

reject_doc_text docs/jenkins-agent-setup-manual.md \
  'Creates or verifies the dedicated local runtime account.' \
  'Agent setup manual must not say the helper creates the runtime account'
reject_doc_text docs/jenkins-agent-setup-manual.md \
  'Creates or verifies the role-local runtime group' \
  'Agent setup manual must not say the helper creates the runtime group'
