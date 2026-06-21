#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

require_pattern() {
  local file pattern message
  file="${1:?file required}"
  pattern="${2:?pattern required}"
  message="${3:?message required}"
  if ! grep -Fq -- "$pattern" "$repo_root/$file"; then
    printf '%s\n' "$message" >&2
    exit 1
  fi
}

reject_pattern() {
  local file pattern message
  file="${1:?file required}"
  pattern="${2:?pattern required}"
  message="${3:?message required}"
  if grep -Fq -- "$pattern" "$repo_root/$file"; then
    printf '%s\n' "$message" >&2
    exit 1
  fi
}

require_pattern scripts/gerrit-setup.sh \
  'GERRIT_SITE_PATH="${GERRIT_SITE_PATH:-$GERRIT_NATIVE_SITE_PATH}"' \
  'Gerrit helper must default GERRIT_SITE_PATH to /srv/gerrit'
require_pattern scripts/jenkins-controller-setup.sh \
  'JENKINS_HOME="${JENKINS_HOME:-$JENKINS_NATIVE_HOME}"' \
  'Jenkins controller helper must default JENKINS_HOME to /var/lib/jenkins'
require_pattern scripts/integration-setup.sh \
  'JENKINS_HOME="${JENKINS_HOME:-/var/lib/jenkins}"' \
  'Integration helper must default JENKINS_HOME to /var/lib/jenkins'

require_pattern simulation/docker/docker-harness.sh \
  'HARNESS_PRODUCT_HOME_DIR="${HARNESS_PRODUCT_HOME_DIR:-$repo_root/simulation/product-homes/docker/$HARNESS_RUN_ID}"' \
  'Docker harness must default product-home backing outside HARNESS_STATE_DIR'
require_pattern simulation/docker/docker-harness.sh \
  'export HARNESS_PRODUCT_HOME_DIR' \
  'Docker harness must export HARNESS_PRODUCT_HOME_DIR for Compose'
require_pattern simulation/docker/docker-harness.sh \
  '/srv/gerrit' \
  'Docker harness must recognize Gerrit native product-home evidence references'
require_pattern simulation/docker/docker-harness.sh \
  '/var/lib/jenkins' \
  'Docker harness must recognize Jenkins controller native product-home evidence references'
require_pattern simulation/docker/docker-harness.sh \
  '/var/lib/jenkins-agent' \
  'Docker harness must recognize Jenkins agent native product-home evidence references'
require_pattern scripts/gerrit-setup.sh \
  '"service_log_reference": $q_service_log' \
  'Gerrit evidence must record runtime service log as metadata'
require_pattern scripts/jenkins-controller-setup.sh \
  '"service_log_reference": $q_service_log' \
  'Jenkins controller evidence must record runtime service log as metadata'
require_pattern scripts/jenkins-agent-setup.sh \
  '"service_log_reference": $q_service_log' \
  'Jenkins agent evidence must record runtime service log as metadata'
reject_pattern simulation/docker/docker-harness.sh \
  'host_product' \
  'Docker harness must not normalize product-home logs as bounded log references'
reject_pattern simulation/docker/docker-harness.sh \
  'product_prefix' \
  'Docker harness must not treat product-home paths as bounded log prefixes'
reject_pattern simulation/docker/docker-harness.sh \
  'copy_product_home_log_reference' \
  'Docker harness must not use temporary product-home log copies to bypass access'
reject_pattern simulation/docker/docker-harness.sh \
  '$HARNESS_LOG_DIR/product-home/$role' \
  'Docker harness must not relocate product-home bounded log references to snapshots'
require_pattern scripts/jenkins-controller-setup.sh \
  '"runtime_status_reference": $q_runtime_status' \
  'Jenkins controller evidence must record runtime.status as metadata'
reject_pattern scripts/jenkins-controller-setup.sh \
  'q_log="$(json_quote "$bounded_log;$service_log;$runtime_status")"' \
  'Jenkins controller runtime.status must not be a bounded log reference'
reject_pattern scripts/gerrit-setup.sh \
  'q_log="$(json_quote "$bounded_log;$service_log")"' \
  'Gerrit service log must not be a bounded log reference'
reject_pattern scripts/jenkins-controller-setup.sh \
  'q_log="$(json_quote "$bounded_log;$service_log")"' \
  'Jenkins controller service log must not be a bounded log reference'
reject_pattern scripts/jenkins-agent-setup.sh \
  'q_log="$(json_quote "$bounded_log;$service_log")"' \
  'Jenkins agent service log must not be a bounded log reference'
require_pattern scripts/integration-setup.sh \
  "printf '%s/jenkins-controller/integration\n' \"\$HARNESS_STATE_DIR\"" \
  'Integration durable host state must live under Jenkins controller harness state'
require_pattern scripts/integration-setup.sh \
  'mkdir -p "$(integration_host_state_dir)/status" "$(integration_log_dir)" "$(integration_evidence_dir)"' \
  'Integration host state must only create status, logs, and evidence directories'
require_pattern scripts/integration-setup.sh \
  "printf '%s/integration-ops\n' \"\$JENKINS_HOME\"" \
  'Jenkins operation custody must live under Jenkins home'
require_pattern scripts/integration-setup.sh \
  'JENKINS_OPERATOR_ACCOUNT="${JENKINS_OPERATOR_ACCOUNT:-ci-operator}"' \
  'Integration helper must default the Jenkins operator account'
require_pattern examples/integration.env.example \
  'JENKINS_OPERATOR_ACCOUNT="ci-operator"' \
  'Integration example env must document the operator account'
reject_pattern examples/integration.env.example \
  'JENKINS_OPERATOR_GROUP=' \
  'Integration example env must not define an operator group'
require_pattern scripts/integration-setup.sh \
  'docker exec -i -u "$JENKINS_OPERATOR_ACCOUNT" "$(jenkins_container)" sh -s <<EOF >/dev/null' \
  'Jenkins integration operation dirs must pass setup script through operator stdin'
require_pattern scripts/integration-setup.sh \
  'docker exec -u "$JENKINS_OPERATOR_ACCOUNT" "$(jenkins_container)" sh -lc' \
  'Jenkins-owned operation files must be prepared through the configured operator identity'
require_pattern scripts/integration-setup.sh \
  "sudo install -d -m 700 -o '\$JENKINS_RUNTIME_ACCOUNT' -g '\$JENKINS_RUNTIME_GROUP'" \
  'Jenkins integration operation dirs must be Jenkins-owned private directories'
require_pattern scripts/integration-setup.sh \
  'sudo -u '\''$JENKINS_RUNTIME_ACCOUNT'\'' test -w '\''$(jenkins_ops_keys_dir)'\''' \
  'Integration setup must fail fast when Jenkins runtime cannot write operation keys'
require_pattern scripts/integration-setup.sh \
  'container_script="$(jenkins_ops_payloads_dir)/$script_name"' \
  'Jenkins Groovy payloads must live under Jenkins operation custody'
require_pattern scripts/integration-setup.sh \
  'docker exec -u "$JENKINS_OPERATOR_ACCOUNT" "$(jenkins_container)" mktemp "/tmp/$script_name.XXXXXX.tmp"' \
  'Jenkins Groovy payloads must stage through transient container /tmp'
require_pattern scripts/integration-setup.sh \
  'docker exec -i -u "$JENKINS_OPERATOR_ACCOUNT" "$(jenkins_container)" sh -lc "cat >'\''$container_tmp_script'\''" <"$script_file"' \
  'Jenkins Groovy payloads must stream into container /tmp as the operator'
require_pattern scripts/integration-setup.sh \
  'sudo install -m 600 -o '\''$JENKINS_RUNTIME_ACCOUNT'\'' -g '\''$JENKINS_RUNTIME_GROUP'\''' \
  'Jenkins Groovy payloads must be installed as Jenkins-owned files'
require_pattern scripts/integration-setup.sh \
  'sudo install -m 600 -o '\''$JENKINS_RUNTIME_ACCOUNT'\'' -g '\''$JENKINS_RUNTIME_GROUP'\'' '\''$container_tmp_script'\'' '\''$container_script'\''' \
  'Jenkins Groovy payloads must install from transient /tmp to Jenkins custody'
require_pattern scripts/integration-setup.sh \
  'trap '\''rm -f '\''\'\'''\''$container_tmp_script'\''\'\'''\'''\'' EXIT' \
  'Jenkins Groovy payload staging must be removed after install'
reject_pattern scripts/integration-setup.sh \
  'tmp_script="$(mktemp "${TMPDIR:-/tmp}/$(basename "$script_file").XXXXXX.tmp")"' \
  'Jenkins Groovy payloads must not use host temp staging'
require_pattern scripts/integration-setup.sh \
  '"refs/meta/config": {' \
  'Verification project access must grant read on refs/meta/config through All-Projects'
require_pattern scripts/integration-setup.sh \
  'if ! sudo -u '\''$JENKINS_RUNTIME_ACCOUNT'\'' sh -c '\''test -s '\''\'\'''\''$container_private'\''\'\'''\'''\''; then' \
  'Existing Jenkins integration private keys must be probed as the runtime account before generation'
require_pattern scripts/integration-setup.sh \
  "Jenkins runtime account cannot read integration private keys" \
  'Integration validation must fail clearly when Jenkins cannot read private keys'
require_pattern scripts/integration-setup.sh \
  'ensure_container_integration_dirs' \
  'Integration setup must keep the Jenkins ops tree creation path available'
validate_impl_start_line="$(
  grep -n '^validate_integration_impl() {' "$repo_root/scripts/integration-setup.sh" | cut -d: -f1 | head -1
)"
validate_impl_ensure_line="$(
  awk -v start="$validate_impl_start_line" 'NR > start && /ensure_container_integration_dirs/ { print NR; exit }' \
    "$repo_root/scripts/integration-setup.sh"
)"
validate_impl_status_line="$(
  awk -v start="$validate_impl_start_line" 'NR > start && /Missing Jenkins-to-Gerrit key metadata/ { print NR; exit }' \
    "$repo_root/scripts/integration-setup.sh"
)"
[ -n "$validate_impl_ensure_line" ] || {
  printf 'validate integration must create Jenkins ops custody before checking metadata\n' >&2
  exit 1
}
[ -n "$validate_impl_status_line" ] || {
  printf 'validate integration must still check Jenkins key metadata\n' >&2
  exit 1
}
[ "$validate_impl_ensure_line" -lt "$validate_impl_status_line" ] || {
  printf 'validate integration must create Jenkins ops custody before metadata checks\n' >&2
  exit 1
}
require_pattern scripts/integration-setup.sh \
  'docker exec -u "$JENKINS_OPERATOR_ACCOUNT" "$(jenkins_container)" sudo cat "$public_path" |' \
  'Operator account must be used only as privileged simulation operator'
require_pattern scripts/integration-setup.sh \
  "copy_controller_public_key_to_container \"\$public_path\" \"\$(gerrit_container)\" /tmp/jenkins-gerrit.pub" \
  'Gerrit public-key handoff must use the clear target-local /tmp name'
require_pattern scripts/integration-setup.sh \
  "copy_controller_public_key_to_container \"\$public\" \"\$(agent_container)\" /tmp/jenkins-agent.pub" \
  'Agent public-key handoff must use the clear target-local /tmp name'
reject_pattern scripts/integration-setup.sh \
  "install -d -m 700 -o '\$JENKINS_RUNTIME_ACCOUNT' -g '\$JENKINS_RUNTIME_GROUP' /harness/state/integration" \
  'Integration setup must not transfer harness integration directory ownership to Jenkins'
reject_pattern scripts/integration-setup.sh \
  'mkdir -p "$(integration_host_state_dir)/keys"' \
  'Integration host state must not contain key directories'
reject_pattern scripts/integration-setup.sh \
  'mkdir -p "$(integration_host_state_dir)/scripts"' \
  'Integration host state must not contain script directories'
reject_pattern scripts/integration-setup.sh \
  'chmod 0770 "$(integration_host_state_dir)" "$(integration_host_state_dir)/keys"' \
  'Host integration dirs must not be made group-writable for Jenkins operations'
reject_pattern scripts/integration-setup.sh \
  'test -d /harness/state/integration/keys && test -r /harness/state/integration/keys && test -w /harness/state/integration/keys' \
  'Integration setup must not validate Jenkins writes to harness-owned keys'
reject_pattern scripts/integration-setup.sh \
  'docker_exec_sh "$(gerrit_container)" "install -d -m 700 /harness/state/integration' \
  'Integration setup must not create unused Gerrit role-local integration state'
reject_pattern scripts/integration-setup.sh \
  'docker_exec_sh "$(agent_container)" "install -d -m 700 /harness/state/integration' \
  'Integration setup must not create unused Jenkins-agent role-local integration state'
reject_pattern scripts/integration-setup.sh \
  'prepare_generated_file' \
  'Integration setup must not repair stale generated harness scripts before writing them'
reject_pattern scripts/integration-setup.sh \
  'container_script="/tmp/step11-' \
  'Integration setup must not hand generated Jenkins Groovy scripts through /tmp'
reject_pattern scripts/integration-setup.sh \
  'docker cp "$script_file" "$(jenkins_container):$container_script"' \
  'Integration setup must not copy generated Jenkins Groovy scripts to bypass harness state access'
reject_pattern scripts/integration-setup.sh \
  '/tmp/step11-' \
  'Integration setup must not use step11-prefixed transient payload filenames'
reject_pattern scripts/integration-setup.sh \
  'step11-agent-proof.txt' \
  'Integration job payloads must not create step11-prefixed transient proof files'
reject_pattern scripts/integration-setup.sh \
  '$JENKINS_SHARED_STORAGE_PATH/keys' \
  'Jenkins shared storage must not hold harness integration keys'
reject_pattern scripts/integration-setup.sh \
  '$JENKINS_SHARED_STORAGE_PATH/scripts' \
  'Jenkins shared storage must not hold harness integration scripts'
reject_pattern scripts/integration-setup.sh \
  '$JENKINS_SHARED_STORAGE_PATH/status' \
  'Jenkins shared storage must not hold harness integration status'

reject_pattern scripts/gerrit-setup.sh \
  'GERRIT_SITE_PATH="/harness/state/site"' \
  'Gerrit Docker override must not force product site under /harness/state'
reject_pattern scripts/jenkins-controller-setup.sh \
  'JENKINS_HOME="${JENKINS_HOME:-/harness/state/jenkins-home}"' \
  'Jenkins helper must not default product home under /harness/state'
reject_pattern scripts/integration-setup.sh \
  'JENKINS_HOME="${JENKINS_HOME:-/harness/state/jenkins-home}"' \
  'Integration helper must not default Jenkins home under /harness/state'
reject_pattern simulation/docker/compose.yaml \
  '${HARNESS_STATE_DIR}/gerrit/site:/srv/gerrit' \
  'Docker compose must not back Gerrit product home from HARNESS_STATE_DIR'
reject_pattern simulation/docker/compose.yaml \
  '${HARNESS_STATE_DIR}/jenkins-controller/jenkins-home:/var/lib/jenkins' \
  'Docker compose must not back Jenkins product home from HARNESS_STATE_DIR'
reject_pattern simulation/docker/compose.yaml \
  '${HARNESS_STATE_DIR}/jenkins-agent/remote-fs:/var/lib/jenkins-agent' \
  'Docker compose must not back Jenkins agent product home from HARNESS_STATE_DIR'

require_pattern scripts/gerrit-setup.sh \
  'readonly GERRIT_NATIVE_SITE_PATH="/srv/gerrit"' \
  'Gerrit helper must define the native site path separately from operator config'
require_pattern scripts/gerrit-setup.sh \
  'GERRIT_SITE_PATH must be $GERRIT_NATIVE_SITE_PATH, got $GERRIT_SITE_PATH' \
  'Gerrit helper must fail when GERRIT_SITE_PATH is not native'
require_pattern scripts/gerrit-setup.sh \
  'require_runtime_account_home "$GERRIT_RUNTIME_ACCOUNT" "$GERRIT_RUNTIME_GROUP" "$GERRIT_NATIVE_SITE_PATH" "Gerrit"' \
  'Gerrit helper must validate runtime account/group against native home'
require_pattern scripts/gerrit-setup.sh \
  'require_product_home_ownership "$GERRIT_NATIVE_SITE_PATH" "$GERRIT_RUNTIME_ACCOUNT" "$GERRIT_RUNTIME_GROUP" "Gerrit"' \
  'Gerrit helper must validate native product home ownership'
require_pattern scripts/gerrit-setup.sh \
  'chown -R "$GERRIT_RUNTIME_ACCOUNT:$GERRIT_RUNTIME_GROUP" "$GERRIT_SITE_PATH"' \
  'Gerrit install must make product home ownership explicit'
reject_pattern scripts/gerrit-setup.sh \
  'GERRIT_RUNTIME_ACCOUNT must be $GERRIT_NATIVE_RUNTIME_ACCOUNT' \
  'Gerrit helper must not require a fixed literal runtime account name'
reject_pattern scripts/gerrit-setup.sh \
  'GERRIT_RUNTIME_GROUP must be $GERRIT_NATIVE_RUNTIME_GROUP' \
  'Gerrit helper must not require a fixed literal runtime group name'
require_pattern scripts/jenkins-controller-setup.sh \
  'readonly JENKINS_NATIVE_HOME="/var/lib/jenkins"' \
  'Jenkins helper must define the native home separately from operator config'
require_pattern scripts/jenkins-controller-setup.sh \
  'JENKINS_HOME must be $JENKINS_NATIVE_HOME, got $JENKINS_HOME' \
  'Jenkins helper must fail when JENKINS_HOME is not native'
require_pattern scripts/jenkins-controller-setup.sh \
  'require_runtime_account_home "$JENKINS_RUNTIME_ACCOUNT" "$JENKINS_RUNTIME_GROUP" "$JENKINS_NATIVE_HOME" "Jenkins"' \
  'Jenkins helper must validate runtime account/group against native home'
require_pattern scripts/jenkins-controller-setup.sh \
  'require_product_home_ownership "$JENKINS_NATIVE_HOME" "$JENKINS_RUNTIME_ACCOUNT" "$JENKINS_RUNTIME_GROUP" "Jenkins"' \
  'Jenkins helper must validate native product home ownership'
reject_pattern scripts/jenkins-controller-setup.sh \
  'JENKINS_RUNTIME_ACCOUNT must be $JENKINS_NATIVE_RUNTIME_ACCOUNT' \
  'Jenkins helper must not require a fixed literal runtime account name'
reject_pattern scripts/jenkins-controller-setup.sh \
  'JENKINS_RUNTIME_GROUP must be $JENKINS_NATIVE_RUNTIME_GROUP' \
  'Jenkins helper must not require a fixed literal runtime group name'
require_pattern scripts/jenkins-agent-setup.sh \
  'readonly JENKINS_AGENT_NATIVE_REMOTE_FS="/var/lib/jenkins-agent"' \
  'Agent helper must define the native remote FS separately from operator config'
require_pattern scripts/jenkins-agent-setup.sh \
  'JENKINS_AGENT_REMOTE_FS must be $JENKINS_AGENT_NATIVE_REMOTE_FS, got $value' \
  'Agent helper must fail when JENKINS_AGENT_REMOTE_FS is not native'
require_pattern scripts/jenkins-agent-setup.sh \
  'require_runtime_account_home "$JENKINS_AGENT_ACCOUNT" "$JENKINS_AGENT_GROUP" "$JENKINS_AGENT_NATIVE_REMOTE_FS" "Jenkins agent"' \
  'Agent helper must validate runtime account/group against native home'
require_pattern scripts/jenkins-agent-setup.sh \
  'require_product_home_ownership "$JENKINS_AGENT_NATIVE_REMOTE_FS" "$JENKINS_AGENT_ACCOUNT" "$JENKINS_AGENT_GROUP" "Jenkins agent"' \
  'Agent helper must validate native product home ownership'
reject_pattern scripts/jenkins-agent-setup.sh \
  'JENKINS_AGENT_ACCOUNT must be $JENKINS_AGENT_NATIVE_ACCOUNT' \
  'Agent helper must not require a fixed literal runtime account name'
reject_pattern scripts/jenkins-agent-setup.sh \
  'JENKINS_AGENT_GROUP must be $JENKINS_AGENT_NATIVE_GROUP' \
  'Agent helper must not require a fixed literal runtime group name'

reject_pattern scripts/jenkins-agent-setup.sh \
  'useradd --create-home' \
  'Agent helper must not create the product runtime account'
reject_pattern scripts/jenkins-agent-setup.sh \
  'groupadd "$JENKINS_AGENT_GROUP"' \
  'Agent helper must not create the product runtime group'
reject_pattern scripts/jenkins-agent-setup.sh \
  '/harness/state/agent/workspace' \
  'Agent helper must not accept /harness/state/agent/workspace as product remote FS'
require_pattern scripts/jenkins-agent-setup.sh \
  'JENKINS_AGENT_REMOTE_FS must be $JENKINS_AGENT_NATIVE_REMOTE_FS, got $value' \
  'Agent helper error must describe the native remote FS boundary'

require_pattern simulation/docker/target/Dockerfile \
  'groupadd --system ci-operator' \
  'Docker target image must include a distinct local ci-operator group'
require_pattern simulation/docker/target/Dockerfile \
  'useradd --create-home --gid ci-operator --home-dir /home/ci-operator --shell /bin/bash ci-operator' \
  'Docker target image must include a distinct local ci-operator account'
require_pattern simulation/docker/target/Dockerfile \
  'sudo \' \
  'Docker target image must install sudo for ci-operator orchestration'
require_pattern simulation/docker/target/Dockerfile \
  'ci-operator ALL=(ALL) NOPASSWD:ALL' \
  'Docker ci-operator account must have passwordless sudo'
require_pattern simulation/docker/target/Dockerfile \
  'chmod 0440 /etc/sudoers.d/harness-ci-operator' \
  'Docker ci-operator sudoers drop-in must use mode 0440'
require_pattern simulation/docker/target/Dockerfile \
  'useradd --system --gid gerrit --home-dir /srv/gerrit --shell /bin/bash gerrit' \
  'Gerrit runtime account must remain distinct from ci-operator'
require_pattern simulation/docker/target/Dockerfile \
  'useradd --system --gid jenkins --home-dir /var/lib/jenkins --shell /bin/bash jenkins' \
  'Jenkins runtime account must remain distinct from ci-operator'
require_pattern simulation/docker/target/Dockerfile \
  'useradd --system --gid jenkins-agent --home-dir /var/lib/jenkins-agent --shell /bin/bash jenkins-agent' \
  'Jenkins agent runtime account must remain distinct from ci-operator'

reject_pattern scripts/gerrit-setup.sh \
  'refs/meta/config' \
  'Gerrit role-local validation must not mutate refs/meta/config'
reject_pattern scripts/gerrit-setup.sh \
  'Remove deferred integration grants for Step 7' \
  'Gerrit role-local validation must not remove integration config through Git'
reject_pattern scripts/gerrit-setup.sh \
  'git push origin HEAD:refs/meta/config' \
  'Gerrit role-local validation must not push All-Projects config'

require_pattern scripts/integration-setup.sh \
  'PUT "/projects/$all_projects_id/labels/Verified"' \
  'Integration helper must apply Verified label to All-Projects'
require_pattern scripts/integration-setup.sh \
  'GET "/projects/$all_projects_id/labels/Verified"' \
  'Integration helper must validate Verified label on All-Projects'
reject_pattern scripts/integration-setup.sh \
  'PUT "/projects/$project_id/labels/Verified"' \
  'Integration helper must not apply Verified label to disposable project'
