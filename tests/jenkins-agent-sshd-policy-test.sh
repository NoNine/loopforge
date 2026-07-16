#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

template="$repo_root/templates/jenkins-agent/sshd-policy.conf.template"
for expected in \
  '# Port and ListenAddress are site-owned.' \
  'Match User {{JENKINS_AGENT_ACCOUNT}}' \
  'AuthenticationMethods publickey' \
  'PubkeyAuthentication yes' \
  'PasswordAuthentication no' \
  'KbdInteractiveAuthentication no' \
  'PermitEmptyPasswords no' \
  'Match all'; do
  grep -Fq "$expected" "$template"
done
if grep -Eq '^[[:space:]]*(Port|ListenAddress|AllowUsers)[[:space:]]' "$template"; then
  printf 'Agent role policy must not own global listener or allow-list directives\n' >&2
  exit 1
fi

grep -Fq 'readonly JENKINS_AGENT_SSH_POLICY_PATH="/etc/ssh/sshd_config.d/40-jenkins-agent.conf"' \
  "$repo_root/scripts/jenkins-agent-setup.sh"
grep -Fq 'render_template_as_root "$JENKINS_AGENT_STAGED_ARTIFACT_DIR/templates/sshd-policy.conf.template" "$JENKINS_AGENT_SSH_POLICY_PATH"' \
  "$repo_root/scripts/jenkins-agent-setup.sh"
grep -Fq 'install -m $(shell_quote "$mode") -o root -g root' \
  "$repo_root/scripts/jenkins-agent-setup.sh"
grep -Fq 'validate_reviewed_sshd_listener "$log_file"' \
  "$repo_root/scripts/jenkins-agent-setup.sh"
grep -Fq 'validate_effective_agent_sshd_policy "$log_file"' \
  "$repo_root/scripts/jenkins-agent-setup.sh"
grep -Fq 'systemctl enable --now' "$repo_root/scripts/jenkins-agent-setup.sh"
grep -Fq 'systemctl reload' "$repo_root/scripts/jenkins-agent-setup.sh"
grep -Fq 'kill -HUP' "$repo_root/scripts/jenkins-agent-setup.sh"
for privileged_log_command in \
  'run_with_privilege "$(shell_quote "$sshd_bin") -T 2>>$(shell_quote "$log_file")"' \
  'run_with_privilege "$(shell_quote "$sshd_bin") -t >>$(shell_quote "$log_file") 2>&1"' \
  'addr=127.0.0.1 2>>$(shell_quote "$log_file")" >"$effective"'; do
  grep -Fq "$privileged_log_command" \
    "$repo_root/scripts/jenkins-agent-setup.sh"
done
if grep -Eq 'run_with_privilege .*" (2>>|>>).*\$log_file' \
  "$repo_root/scripts/jenkins-agent-setup.sh"; then
  printf 'Privileged SSH validation must open the agent-owned log after privilege delegation\n' >&2
  exit 1
fi

validation_body="$(sed -n '/^check_runtime_readiness() {/,/^}/p' "$repo_root/scripts/jenkins-agent-setup.sh")"
for replayed in \
  verify_staged_artifacts \
  check_os_dependency_expectations \
  check_runtime_account \
  check_remote_fs_ownership \
  validate_effective_agent_sshd_policy; do
  if printf '%s\n' "$validation_body" | grep -Fq "$replayed"; then
    printf 'Agent validation must not replay setup check: %s\n' "$replayed" >&2
    exit 1
  fi
done

printf 'Jenkins agent SSH policy contract passed\n'
