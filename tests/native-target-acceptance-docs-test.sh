#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
checklist="$repo_root/docs/operations/native/acceptance-checklist.md"

require_text() {
  local file pattern message
  file="${1:?file required}"
  pattern="${2:?pattern required}"
  message="${3:?message required}"
  grep -Fq -- "$pattern" "$repo_root/$file" || {
    printf '%s\n' "$message" >&2
    exit 1
  }
}

reject_text() {
  local file pattern message
  file="${1:?file required}"
  pattern="${2:?pattern required}"
  message="${3:?message required}"
  if grep -Fq -- "$pattern" "$repo_root/$file"; then
    printf '%s\n' "$message" >&2
    exit 1
  fi
}

[ -f "$checklist" ] || {
  printf 'Native target-deployment acceptance checklist is missing\n' >&2
  exit 1
}

for heading in \
  '## Deployment' \
  '## Preparation' \
  '## Gerrit' \
  '## Jenkins Controller' \
  '## Jenkins Agent' \
  '## Integration' \
  '## End-To-End Result'; do
  grep -Fxq -- "$heading" "$checklist" || {
    printf 'Checklist section is missing: %s\n' "$heading" >&2
    exit 1
  }
done

for reference in \
  'docs/operations/native/gerrit.md' \
  'docs/operations/native/jenkins-controller.md' \
  'docs/operations/native/jenkins-agent.md' \
  'docs/operations/native/integration.md'; do
  grep -Fq -- "$reference" "$checklist" || {
    printf 'Checklist must link to native procedure: %s\n' "$reference" >&2
    exit 1
  }
done

require_text docs/operations/native/acceptance-checklist.md \
  'freshly provisioned target hosts' \
  'Checklist must require fresh target state'
require_text docs/operations/native/acceptance-checklist.md \
  'Change/ticket:' \
  'Checklist must retain the deployment/change ticket reference'
require_text docs/operations/native/acceptance-checklist.md \
  'Gerrit verification change:' \
  'Checklist must retain the Gerrit verification change reference'
require_text docs/operations/native/acceptance-checklist.md \
  'Jenkins verification build:' \
  'Checklist must retain the Jenkins verification build reference'
require_text docs/operations/native/acceptance-checklist.md \
  'Result: ACCEPTED / BLOCKED' \
  'Checklist must have an explicit final decision'
require_text docs/operations/native/acceptance-checklist.md \
  'repair service state during validation.' \
  'Checklist must keep validation non-repairing'
require_text docs/operations/native/acceptance-checklist.md \
  'Reboot checks are optional and may be left unchecked when not' \
  'Checklist must allow reboot checks to be skipped'
require_text docs/operations/native/acceptance-checklist.md \
  'a failed optional reboot check makes the run `BLOCKED`.' \
  'Checklist must block an attempted reboot check that fails'
if [ "$(grep -Fc -- '- [ ] Optional reboot check:' "$checklist")" -ne 3 ]; then
  printf 'Checklist must contain exactly three optional reboot checks\n' >&2
  exit 1
fi
require_text docs/operations/native/acceptance-checklist.md \
  'reviewed JCasC or UI-driven configuration.' \
  'Checklist must accept reviewed JCasC and UI-driven configuration'
reject_text docs/operations/native/acceptance-checklist.md \
  'required build tools' \
  'Checklist must not require unspecified agent build tools'

if rg -n 'scripts/[^[:space:]`]+\.sh|simulation/[^[:space:]`]+\.sh|```(bash|sh)|collect-evidence|JSON|evidence package' \
  "$checklist"; then
  printf 'Checklist must not contain helpers, command transcripts, JSON, or evidence packaging\n' >&2
  exit 1
fi

require_text docs/operations/README.md \
  'native/acceptance-checklist.md' \
  'Operations index must link the native acceptance checklist'
require_text docs/contracts/validation-and-evidence.md \
  'Native `target-deployment` installation and configuration are fully manual.' \
  'Evidence contract must define fully manual native target deployment'
require_text docs/contracts/validation-and-evidence.md \
  'It is not required for the native `target-deployment` acceptance checklist.' \
  'Evidence contract must exclude the native checklist from global aggregation'
require_text docs/contracts/operator-execution-contract.md \
  'records the result in the native acceptance checklist' \
  'Operator contract must define checklist-based native acceptance'
require_text docs/contracts/lifecycle-contract.md \
  'Native `target-deployment` records the corresponding role, reboot,' \
  'Lifecycle contract must route native outcomes to the checklist'
require_text docs/architecture/system-model.md \
  'Native `target-deployment` acceptance uses' \
  'System model must distinguish the native checklist from machine evidence'
require_text docs/planning/steps/step-15-final-acceptance.md \
  '`docs/operations/native/acceptance-checklist.md`' \
  'Step 15 must include native target-deployment acceptance'
require_text docs/planning/steps/step-15-final-acceptance.md \
  'deployment/change ticket, disposable Gerrit' \
  'Step 15 must keep native acceptance references minimal'

reject_text docs/operations/native/gerrit.md \
  'Until that workflow is implemented' \
  'Gerrit native handoff must not call the manual integration workflow unimplemented'
reject_text docs/operations/native/jenkins-controller.md \
  'Until that workflow is implemented' \
  'Jenkins native handoff must not call the manual integration workflow unimplemented'
reject_text docs/operations/native/jenkins-agent.md \
  'Until that workflow is implemented' \
  'Agent native handoff must not call the manual integration workflow unimplemented'
require_text docs/operations/native/jenkins-controller.md \
  '<JENKINS_URL>/api/json' \
  'Jenkins native validation must check the required API endpoint'
require_text docs/operations/native/jenkins-controller.md \
  'authenticated browser session' \
  'Jenkins API validation must use the authenticated browser session'
for role_doc in \
  docs/operations/native/gerrit.md \
  docs/operations/native/jenkins-controller.md \
  docs/operations/native/jenkins-agent.md; do
  require_text "$role_doc" \
    'freshly provisioned' \
    'Native role procedure must require a freshly provisioned target'
  require_text "$role_doc" \
    'stop and reprovision the target' \
    'Native role procedure must stop when clean-install prerequisites fail'
  reject_text "$role_doc" \
    'fully matching' \
    'Native clean-install procedure must not describe helper state reuse'
  reject_text "$role_doc" \
    'partial runtime identity state' \
    'Native clean-install procedure must not copy helper state classification'
  reject_text "$role_doc" \
    'elif getent' \
    'Native clean-install procedure must not contain helper-style account branches'
  require_text "$role_doc" \
    'The reboot check is optional.' \
    'Native role procedure must mark its reboot check optional'
  require_text "$role_doc" \
    'mark the run `BLOCKED`.' \
    'Native role procedure must block an attempted reboot check that fails'
done
require_text docs/operations/native/gerrit.md \
  'sudo groupadd --gid 61010 gerrit' \
  'Gerrit native procedure must create its reviewed runtime group directly'
require_text docs/operations/native/gerrit.md \
  'sudo useradd --uid 61010 --gid 61010 --home-dir /srv/gerrit --no-create-home' \
  'Gerrit native procedure must create its reviewed runtime account directly'
require_text docs/operations/native/jenkins-controller.md \
  'sudo groupadd --gid 61020 jenkins' \
  'Jenkins native procedure must create its reviewed runtime group directly'
require_text docs/operations/native/jenkins-controller.md \
  'sudo useradd --uid 61020 --gid 61020 --home-dir /var/lib/jenkins --no-create-home' \
  'Jenkins native procedure must create its reviewed runtime account directly'
require_text docs/operations/native/jenkins-agent.md \
  'sudo groupadd --gid JENKINS_AGENT_GID jenkins-agent' \
  'Agent native procedure must create its reviewed runtime group directly'
require_text docs/operations/native/jenkins-agent.md \
  'sudo useradd --uid JENKINS_AGENT_UID --gid JENKINS_AGENT_GID' \
  'Agent native procedure must create its reviewed runtime account directly'
require_text docs/operations/native/jenkins-agent.md \
  'getent passwd JENKINS_AGENT_UID' \
  'Agent native preflight must check the reviewed numeric identity directly'
require_text docs/operations/native/jenkins-agent.md \
  "sudo usermod -p '*' jenkins-agent" \
  'Agent native procedure must make the runtime account public-key capable without a password'
require_text docs/operations/native/jenkins-agent.md \
  'sudo systemctl enable --now ssh' \
  'Agent native procedure must enable the Ubuntu SSH service directly'
reject_text docs/operations/native/jenkins-agent.md \
  'sudo bash -s' \
  'Agent native procedure must not hide direct operations in a privileged heredoc'
reject_text docs/operations/native/jenkins-agent.md \
  'if getent' \
  'Agent native preflight must remain a direct operator command sequence'
reject_text docs/operations/native/jenkins-agent.md \
  'systemctl enable --now sshd || true' \
  'Agent native procedure must not mask SSH service activation failure'

for checksum_spec in \
  'docs/operations/native/gerrit.md:gerrit-artifacts-bundle.tar.gz' \
  'docs/operations/native/jenkins-controller.md:jenkins-artifacts-bundle.tar.gz' \
  'docs/operations/native/jenkins-agent.md:jenkins-agent-artifacts-bundle.tar.gz'; do
  checksum_doc="${checksum_spec%%:*}"
  checksum_archive="${checksum_spec#*:}"
  require_text "$checksum_doc" \
    "sha256sum $checksum_archive" \
    "Native archive checksum must use the transferable basename: $checksum_archive"
  reject_text "$checksum_doc" \
    "sha256sum ~/$checksum_archive" \
    "Native archive checksum must not record a bundle-factory absolute path: $checksum_archive"
done
require_text docs/operations/native/integration.md \
  '`docs/operations/native/acceptance-checklist.md`' \
  'Native integration must use the single acceptance checklist'
reject_text docs/operations/native/integration.md \
  'Collect an integration evidence record with:' \
  'Native integration must not require a separate evidence record'
reject_text docs/operations/native/integration.md \
  'role-local readiness evidence' \
  'Native integration must consume checklist outcomes, not role evidence records'

for native_doc in \
  docs/operations/native/gerrit.md \
  docs/operations/native/jenkins-controller.md \
  docs/operations/native/jenkins-agent.md \
  docs/operations/native/integration.md; do
  reject_text "$native_doc" \
    'Evidence may record' \
    'Native procedures must not define a separate evidence record'
  reject_text "$native_doc" \
    'Evidence should record' \
    'Native procedures must not require separate evidence details'
  reject_text "$native_doc" \
    'role-local evidence' \
    'Native procedures must record role outcomes in the acceptance checklist'
done
