#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
manual="$repo_root/docs/operations/native/jenkins-agent.md"
integration="$repo_root/docs/operations/native/integration.md"
prd="$repo_root/docs/product/prd.md"
system_model="$repo_root/docs/architecture/system-model.md"
lifecycle="$repo_root/docs/contracts/lifecycle-contract.md"
operator_contract="$repo_root/docs/contracts/operator-execution-contract.md"
review_guide="$repo_root/docs/operations/native/review-guide.md"
step_plan="$repo_root/docs/planning/steps/step-09-jenkins-agent-manual-and-helper.md"

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

for input in \
  'JENKINS_AGENT_HOST' \
  'JENKINS_AGENT_SSH_PORT' \
  'JENKINS_AGENT_UID' \
  'JENKINS_AGENT_GID' \
  'LOOPFORGE_OPERATOR_ACCOUNT' \
  'LOOPFORGE_OPERATOR_GROUP'; do
  require_text "$manual" "$input" "Native agent input is missing: $input"
done

for subsection in \
  '### 2.1 Install Ubuntu Dependencies' \
  '### 2.2 Create The Agent Artifact Bundle' \
  '### 2.3 Stage And Verify The Agent Artifact Bundle'; do
  require_text "$manual" "$subsection" \
    "Native agent Section 2 is missing the ordered step: $subsection"
done

require_text "$manual" \
  '| Agent runtime user | `jenkins-agent`, local OS account |' \
  'Native agent procedure must use the baseline runtime account'
require_text "$manual" \
  '| Agent runtime group | `jenkins-agent`, local OS group |' \
  'Native agent procedure must use the baseline runtime group'
require_text "$manual" \
  'The native baseline runtime account and group are' \
  'Native agent procedure must identify jenkins-agent as the baseline identity'
require_text "$manual" \
  'substitute the reviewed name' \
  'Native agent procedure must allow consistent reviewed site identity substitution'
for native_identity_doc in "$manual" "$integration"; do
  reject_text "$native_identity_doc" \
    'JENKINS_AGENT_ACCOUNT' \
    'Native procedures must not expose a configurable agent account name'
  reject_text "$native_identity_doc" \
    'JENKINS_AGENT_GROUP' \
    'Native procedures must not expose a configurable agent group name'
done

require_text "$manual" \
  'The product home remains' \
  'Native agent procedure must keep the canonical product home'
require_text "$manual" \
  $'cat /etc/os-release\nhostnamectl\ntimedatectl\ndf -h /var/lib\nfree -h\nsystemctl --failed\ngetent hosts JENKINS_AGENT_HOST' \
  'Native agent preflight must remain concise and operator-first'
require_text "$manual" \
  'stop and correct endpoint identity if it does not.' \
  'Native agent preflight must define the host-resolution stop condition'

for freshness_check in \
  'test ! -e "$HOME/jenkins-agent-artifacts-bundle"' \
  'test ! -e "$HOME/jenkins-agent-artifacts-bundle.tar.gz"' \
  'test ! -e "$HOME/jenkins-agent-artifacts-bundle.tar.gz.sha256"' \
  'sudo test ! -e /var/lib/loopforge/staging/jenkins-agent' \
  'test ! -e /var/lib/jenkins-agent' \
  'sudo test ! -e /etc/ssh/sshd_config.d/40-jenkins-agent.conf'; do
  require_text "$manual" "$freshness_check" \
    "Native agent procedure must require fresh selected state: $freshness_check"
done

require_text "$manual" \
  'sha256sum jenkins-agent-artifacts-bundle.tar.gz' \
  'Native agent archive checksum must use the transferable basename'
require_text "$manual" \
  $'cd /var/lib/loopforge/staging/jenkins-agent\nsha256sum -c checksums.sha256' \
  'Native agent staging must verify payload checksums before mutation'
reject_text "$manual" \
  'harness_manifest_version' \
  'Native agent payload must not copy the helper manifest schema'
reject_text "$manual" \
  'template_count=' \
  'Native agent payload must not claim helper templates'
reject_text "$manual" \
  'JENKINS_BUILD_EXTRA_PACKAGES' \
  'Native agent procedure must not expose an unused package variable'
reject_text "$manual" \
  'rm -rf' \
  'Native agent procedure must not clean selected state inside setup'
reject_text "$manual" \
  '|| true' \
  'Native agent procedure must not mask command failures'
reject_text "$manual" \
  'sha256sum ~/jenkins-agent-artifacts-bundle.tar.gz' \
  'Native agent checksum must not contain the bundle-factory absolute path'

for heading in \
  '## 1. Operator Inputs and Current Status' \
  '## 2. Dependencies And Jenkins Agent Artifact Bundle' \
  '## 3. Jenkins Agent Installation' \
  '## 4. Shared Integration Handoff' \
  '## 5. Agent-Only Validation' \
  '## 6. Backup and Operations' \
  '## 7. References'; do
  require_text "$manual" "$heading" \
    "Native agent procedure is missing the aligned section: $heading"
done

require_text "$manual" \
  'sudo apt update' \
  'Native agent dependency installation must use delegated privilege'
require_text "$manual" \
  'sudo apt install -y' \
  'Native agent package installation must use delegated privilege'
require_text "$manual" \
  'sudo groupadd --gid JENKINS_AGENT_GID jenkins-agent' \
  'Native agent group creation must use the baseline group and reviewed GID'
require_text "$manual" \
  'sudo useradd --uid JENKINS_AGENT_UID --gid JENKINS_AGENT_GID' \
  'Native agent account creation must use the reviewed numeric identity'
require_text "$manual" \
  "sudo usermod -p '*' jenkins-agent" \
  'Native agent account must accept public-key SSH without a password'
require_text "$manual" \
  'jenkins-agent:jenkins-agent' \
  'Native agent ownership checks must use the baseline runtime identity'

require_text "$manual" \
  '/etc/ssh/sshd_config.d/40-jenkins-agent.conf' \
  'Native agent procedure must install the selected role-owned SSH policy'
reject_text "$manual" \
  '/etc/ssh/sshd_config.d/40-loopforge-jenkins-agent.conf' \
  'Native agent SSH policy filename must not include the product name'
require_text "$manual" \
  $'# Port and ListenAddress are site-owned.\nMatch User jenkins-agent\n    AuthenticationMethods publickey\n    PubkeyAuthentication yes\n    PasswordAuthentication no\n    KbdInteractiveAuthentication no\n    PermitEmptyPasswords no\nMatch all' \
  'Native agent SSH fragment must be account-scoped and public-key only'
if grep -Eq '^[[:space:]]*(Port|ListenAddress|AllowUsers)[[:space:]]' "$manual"; then
  printf 'Native agent role must not install global listener or allow-list directives\n' >&2
  exit 1
fi
require_text "$manual" \
  'sudo sshd -t' \
  'Native agent procedure must syntax-check effective sshd configuration'
require_text "$manual" \
  'sudo sshd -T -C' \
  'Native agent procedure must inspect account-specific effective SSH policy'
require_text "$manual" \
  'site SSH/network provisioning stop condition' \
  'Native agent procedure must fail clearly for a missing site listener'
require_text "$manual" \
  'sudo systemctl enable --now ssh' \
  'Native agent procedure must enable and start the Ubuntu SSH service'
require_text "$manual" \
  'sudo systemctl reload ssh' \
  'Native agent procedure must load the validated account policy'

for validation_check in \
  'systemctl is-enabled ssh' \
  'systemctl is-active ssh' \
  '--property=ActiveState --property=MainPID --no-pager' \
  'ssh-keyscan -T 5 -p JENKINS_AGENT_SSH_PORT JENKINS_AGENT_HOST' \
  'sudo systemctl status ssh --no-pager --lines=20'; do
  require_text "$manual" "$validation_check" \
    "Native agent validation is missing: $validation_check"
done

validation_section="$(
  sed -n '/^## 5\. Agent-Only Validation$/,/^## 6\. Backup and Operations$/p' \
    "$manual"
)"
for replayed_operation in \
  'sha256sum' \
  'getent passwd' \
  'getent group' \
  'getent shadow' \
  'stat -c' \
  'sshd -t' \
  'sshd -T'; do
  if printf '%s\n' "$validation_section" | grep -Fq -- "$replayed_operation"; then
    printf 'Native agent validation must not replay earlier operation: %s\n' \
      "$replayed_operation" >&2
    exit 1
  fi
done
require_text "$manual" \
  'Do not replay those earlier checkpoint operations' \
  'Native agent validation must preserve earlier checkpoint ownership'

require_text "$prd" \
  'OS dependency provisioning is a separate' \
  'PRD must separate OS dependency provisioning from application artifacts'
require_text "$prd" \
  'before runtime identity, product-home, application, or service mutation' \
  'PRD must define the application artifact mutation gate precisely'
require_text "$system_model" \
  'This prerequisite provisioning may occur before application' \
  'System model must allow dependency-first provisioning'
require_text "$lifecycle" \
  'must not replay their setup or verification commands' \
  'Lifecycle contract must preserve completed checkpoint ownership'
require_text "$lifecycle" \
  'Readiness combines successful dependency, identity, filesystem, artifact,' \
  'Lifecycle contract must compose Jenkins agent readiness from checkpoints'
require_text "$lifecycle" \
  'This checkpoint changes staging state only; role-local setup owns' \
  'Lifecycle contract must separate staging from role-local runtime mutation'
require_text "$operator_contract" \
  'OS dependency provisioning' \
  'Operator contract must distinguish OS dependency provisioning'
require_text "$review_guide" \
  'Do not replay completed checkpoint operations during role validation.' \
  'Native review guide must reject validation replay'
require_text "$step_plan" \
  'Validation must not replay completed checkpoint' \
  'Jenkins agent step plan must preserve validation ownership'

apt_line="$(grep -n -m1 'sudo apt update' "$manual" | cut -d: -f1)"
bundle_line="$(grep -n -m1 '^### 2.2 Create The Agent Artifact Bundle$' "$manual" | cut -d: -f1)"
stage_line="$(grep -n -m1 'sha256sum -c jenkins-agent-artifacts-bundle.tar.gz.sha256' "$manual" | cut -d: -f1)"
identity_line="$(grep -n -m1 'sudo groupadd --gid JENKINS_AGENT_GID jenkins-agent' "$manual" | cut -d: -f1)"
policy_line="$(grep -n -m1 'sudoedit /etc/ssh/sshd_config.d/40-jenkins-agent.conf' "$manual" | cut -d: -f1)"
handoff_line="$(grep -n -m1 '^## 4. Shared Integration Handoff$' "$manual" | cut -d: -f1)"
validation_line="$(grep -n -m1 '^## 5. Agent-Only Validation$' "$manual" | cut -d: -f1)"
[ "$apt_line" -lt "$bundle_line" ] &&
  [ "$bundle_line" -lt "$stage_line" ] &&
  [ "$stage_line" -lt "$identity_line" ] &&
  [ "$identity_line" -lt "$policy_line" ] &&
  [ "$policy_line" -lt "$handoff_line" ] &&
  [ "$handoff_line" -lt "$validation_line" ] || {
  printf 'Native agent lifecycle must install dependencies, prepare and stage artifacts, configure SSH, hand off, then validate\n' >&2
  exit 1
}

require_text "$integration" \
  '| Jenkins agent runtime group | `jenkins-agent`, local OS group |' \
  'Native integration must inventory the baseline agent runtime group'
for integration_pattern in \
  '-o jenkins-agent -g jenkins-agent' \
  'jenkins-agent:jenkins-agent' \
  'jenkins-agent@JENKINS_AGENT_HOST' \
  'sudo usermod -a -G jenkins-share jenkins-agent' \
  'sudo -u jenkins-agent'; do
  require_text "$integration" "$integration_pattern" \
    "Native integration must consume reviewed agent identity: $integration_pattern"
done

require_text "$manual" \
  'Do not reinstall the artifact bundle to repair an account, key, product home,' \
  'Native agent recovery must not claim that artifacts repair runtime state'
require_text "$manual" \
  'reprovision a fresh agent target' \
  'Native agent recovery must require explicit fresh-state reprovisioning'
require_text "$manual" \
  'Jenkins-to-agent key replacement and rotation' \
  'Native agent recovery must leave key operations to integration'

printf 'Native Jenkins agent documentation contract passed\n'
