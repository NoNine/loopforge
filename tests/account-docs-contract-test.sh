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
  '`ci-operator` local OS account has passwordless sudo' \
  'Account model must document ci-operator passwordless sudo'
require_doc_text docs/account-model.md \
  'Gerrit or Jenkins runtime account, application admin account, integration' \
  'Account model must keep ci-operator separate from product accounts'
require_doc_text simulation/docker/README.md \
  'local `ci-operator` OS account with' \
  'Docker README must document ci-operator passwordless sudo'
require_doc_text simulation/docker/README.md \
  'passwordless sudo for simulation orchestration and privileged helper' \
  'Docker README must document ci-operator passwordless sudo'
require_doc_text simulation/docker/README.md \
  'The `ci-operator` account does not own `/srv/gerrit`,' \
  'Docker README must document ci-operator is not a product runtime owner'
require_doc_text simulation/docker/README.md \
  'controller, or Jenkins agent runtime account.' \
  'Docker README must document ci-operator is not a product runtime owner'

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
