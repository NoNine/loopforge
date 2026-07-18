#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
docker_harness_sources=("$repo_root/simulation/docker/simulate.sh" "$repo_root/simulation/docker/lib/"*.sh)

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

require_docker_harness_pattern() {
  local pattern message
  pattern="${1:?pattern required}"
  message="${2:?message required}"
  if ! grep -Fq -- "$pattern" "${docker_harness_sources[@]}"; then
    printf '%s\n' "$message" >&2
    exit 1
  fi
}

reject_docker_harness_pattern() {
  local pattern message
  pattern="${1:?pattern required}"
  message="${2:?message required}"
  if grep -Fq -- "$pattern" "${docker_harness_sources[@]}"; then
    printf '%s\n' "$message" >&2
    exit 1
  fi
}

require_pattern scripts/gerrit-setup.sh \
  'GERRIT_SITE_PATH="${GERRIT_SITE_PATH:-$GERRIT_NATIVE_SITE_PATH}"' \
  'Gerrit helper must default GERRIT_SITE_PATH to /srv/gerrit'
require_pattern scripts/gerrit-setup.sh \
  'GERRIT_CANONICAL_WEB_URL="${GERRIT_CANONICAL_WEB_URL:-http://$GERRIT_HOST:$GERRIT_HTTP_PORT/}"' \
  'Gerrit helper must default canonical web URL separately from the internal Gerrit host'
require_pattern scripts/gerrit-setup.sh \
  'text="${text//\{\{GERRIT_CANONICAL_WEB_URL\}\}/$GERRIT_CANONICAL_WEB_URL}"' \
  'Gerrit config rendering must use the reviewed canonical web URL'
require_pattern scripts/jenkins-controller-setup.sh \
  'JENKINS_HOME="${JENKINS_HOME:-$JENKINS_NATIVE_HOME}"' \
  'Jenkins controller helper must default JENKINS_HOME to /var/lib/jenkins'
require_pattern scripts/integration-setup.sh \
  'JENKINS_HOME="${JENKINS_HOME:-/var/lib/jenkins}"' \
  'Integration helper must default JENKINS_HOME to /var/lib/jenkins'

require_docker_harness_pattern \
  'HARNESS_PRODUCT_HOME_DIR="${HARNESS_PRODUCT_HOME_DIR:-$HARNESS_SET_RUNTIME_DIR/product-homes}"' \
  'Docker harness must default product-home backing under the reusable set root'
require_docker_harness_pattern \
  'HARNESS_TARGET_DIR="${HARNESS_TARGET_DIR:-$HARNESS_GENERATED_RUN_DIR/target}"' \
  'Docker harness must group target-dominated generated output under target/'
require_docker_harness_pattern \
  'export HARNESS_PRODUCT_HOME_DIR' \
  'Docker harness must export HARNESS_PRODUCT_HOME_DIR for Compose'
require_docker_harness_pattern \
  '/srv/gerrit' \
  'Docker harness must recognize Gerrit native product-home evidence references'
require_docker_harness_pattern \
  '/var/lib/jenkins' \
  'Docker harness must recognize Jenkins controller native product-home evidence references'
require_docker_harness_pattern \
  '/var/lib/jenkins-agent' \
  'Docker harness must recognize Jenkins agent native product-home evidence references'
require_docker_harness_pattern \
  'set_env_file_value "$gerrit" GERRIT_CANONICAL_WEB_URL "http://127.0.0.1:$HARNESS_GERRIT_HTTP_HOST_PORT/"' \
  'Docker start rendering must set Gerrit canonical web URL to the browser-visible loopback URL'
require_pattern scripts/gerrit-setup.sh \
  '"service_log_reference": $q_service_log' \
  'Gerrit evidence must record runtime service log as metadata'
require_pattern scripts/jenkins-controller-setup.sh \
  '"service_log_reference": $q_service_log' \
  'Jenkins controller evidence must record runtime service log as metadata'
require_pattern scripts/jenkins-agent-setup.sh \
  '"service_log_reference": $q_service_log' \
  'Jenkins agent evidence must record runtime service log as metadata'
reject_docker_harness_pattern \
  'host_product' \
  'Docker harness must not normalize product-home logs as bounded log references'
reject_docker_harness_pattern \
  'product_prefix' \
  'Docker harness must not treat product-home paths as bounded log prefixes'
reject_docker_harness_pattern \
  'copy_product_home_log_reference' \
  'Docker harness must not use temporary product-home log copies to bypass access'
reject_docker_harness_pattern \
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
  'INTEGRATION_STATE_DIR="${INTEGRATION_STATE_DIR:-${HARNESS_STATE_DIR:+$HARNESS_STATE_DIR/integration}}"' \
  'Integration durable host state must default under operator-owned integration state'
reject_pattern scripts/integration-setup.sh \
  "printf '%s/jenkins-controller/integration\n' \"\$HARNESS_STATE_DIR\"" \
  'Integration host state must not live under Jenkins controller helper state'
require_pattern scripts/integration-setup.sh \
  'install -d -m "$LF_MODE_PRIVATE_DIR" "$(integration_host_state_dir)" "$(integration_host_state_dir)/status"' \
  'Integration host state and status directories must use the private directory mode'
require_pattern scripts/integration-setup.sh \
  'install -d -m "$LF_MODE_REVIEW_DIR" "$(integration_log_dir)" "$(integration_evidence_dir)"' \
  'Integration logs and evidence directories must use the review directory mode'
require_pattern scripts/integration-setup.sh \
  "printf '%s/integration-ops\n' \"\$JENKINS_HOME\"" \
  'Jenkins operation custody must live under Jenkins home'
require_pattern scripts/integration-setup.sh \
  'LOOPFORGE_OPERATOR_ACCOUNT="${LOOPFORGE_OPERATOR_ACCOUNT:-ci-operator}"' \
  'Integration helper must default the shared operator account'
require_pattern examples/integration.env.example \
  'LOOPFORGE_OPERATOR_ACCOUNT="ci-operator"' \
  'Integration example env must document the operator account'
require_pattern examples/integration.env.example \
  'LOOPFORGE_OPERATOR_GROUP="ci-operator"' \
  'Integration example env must document the operator group'
require_pattern examples/gerrit.env.example \
  'LOOPFORGE_OPERATOR_ACCOUNT="ci-operator"' \
  'Gerrit example env must document the shared operator account'
require_pattern examples/jenkins-controller.env.example \
  'LOOPFORGE_OPERATOR_ACCOUNT="ci-operator"' \
  'Jenkins controller example env must document the shared operator account'
require_pattern examples/jenkins-agent.env.example \
  'LOOPFORGE_OPERATOR_ACCOUNT="ci-operator"' \
  'Jenkins agent example env must document the shared operator account'
require_pattern scripts/integration-setup.sh \
  'target_write_file gerrit "$project_json" "$target_json" "$LOOPFORGE_OPERATOR_ACCOUNT" "$LOOPFORGE_OPERATOR_GROUP" 0600 "$log"' \
  'Integration helper must write target payloads through the shared operator account and group'
reject_pattern scripts/integration-setup.sh \
  'JENKINS_OPERATOR_ACCOUNT' \
  'Integration helper must not expose a Jenkins-specific operator account'
reject_pattern examples/integration.env.example \
  'JENKINS_OPERATOR_ACCOUNT=' \
  'Integration example env must not expose a Jenkins-specific operator account'
reject_pattern examples/integration.env.example \
  'JENKINS_OPERATOR_GROUP=' \
  'Integration example env must not define an operator group'
require_pattern scripts/integration-setup.sh \
  'target_exec() {' \
  'Integration helper must use target OS SSH execution as its control-plane interface'
require_pattern scripts/integration-setup.sh \
  'target_run_as() {' \
  'Integration helper must run target commands through the configured runtime identity'
require_pattern scripts/integration-setup.sh \
  "sudo install -d -m 700 -o '\$JENKINS_RUNTIME_ACCOUNT' -g '\$JENKINS_RUNTIME_GROUP'" \
  'Jenkins integration operation dirs must be Jenkins-owned private directories'
require_pattern scripts/integration-setup.sh \
  'sudo -u '\''$JENKINS_RUNTIME_ACCOUNT'\'' test -w '\''$(jenkins_ops_keys_dir)'\''' \
  'Integration setup must fail fast when Jenkins runtime cannot write operation keys'
require_pattern scripts/integration-setup.sh \
  'target_script="$(jenkins_ops_payloads_dir)/$script_name"' \
  'Jenkins Groovy payloads must live under Jenkins operation custody'
require_pattern scripts/integration-setup.sh \
  'target_exec jenkins-controller "mktemp $(shell_quote "/tmp/$script_name.XXXXXX.tmp")"' \
  'Jenkins Groovy payloads must stage through transient target /tmp'
require_pattern scripts/integration-setup.sh \
  'target_copy_to jenkins-controller "$script_file" "$target_tmp_script"' \
  'Jenkins Groovy payloads must transfer through the target SSH file interface'
require_pattern scripts/integration-setup.sh \
  'sudo install -m 600 -o '\''$JENKINS_RUNTIME_ACCOUNT'\'' -g '\''$JENKINS_RUNTIME_GROUP'\''' \
  'Jenkins Groovy payloads must be installed as Jenkins-owned files'
require_pattern scripts/integration-setup.sh \
  'sudo install -m 600 -o '\''$JENKINS_RUNTIME_ACCOUNT'\'' -g '\''$JENKINS_RUNTIME_GROUP'\'' '\''$target_tmp_script'\'' '\''$target_script'\''' \
  'Jenkins Groovy payloads must install from transient /tmp to Jenkins custody'
require_pattern scripts/integration-setup.sh \
  'trap '\''rm -f '\''\'\'''\''$target_tmp_script'\''\'\'''\'''\'' EXIT' \
  'Jenkins Groovy payload staging must be removed after install'
reject_pattern scripts/integration-setup.sh \
  'tmp_script="$(mktemp "${TMPDIR:-/tmp}/$(basename "$script_file").XXXXXX.tmp")"' \
  'Jenkins Groovy payloads must not use host temp staging'
require_pattern scripts/integration-setup.sh \
  '"refs/meta/config": {' \
  'Verification project access must grant read on refs/meta/config through All-Projects'
require_pattern scripts/integration-setup.sh \
  'if ! sudo -u '\''$JENKINS_RUNTIME_ACCOUNT'\'' sh -c '\''test -s '\''\'\'''\''$target_private'\''\'\'''\'''\''; then' \
  'Existing Jenkins integration private keys must be probed as the runtime account before generation'
require_pattern scripts/integration-setup.sh \
  "Jenkins runtime account cannot read integration private keys" \
  'Integration validation must fail clearly when Jenkins cannot read private keys'
require_pattern scripts/integration-setup.sh \
  'ensure_target_integration_dirs' \
  'Integration setup must keep the SSH target ops tree creation path available'
validate_impl_start_line="$(
  grep -n '^validate_integration_impl() {' "$repo_root/scripts/integration-setup.sh" | cut -d: -f1 | head -1
)"
validate_impl_ensure_line="$(
  awk -v start="$validate_impl_start_line" 'NR > start && /ensure_target_integration_dirs/ { print NR; exit }' \
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
  'target_read_text jenkins-controller "$public_path"' \
  'Public-key handoff must read controller public keys through target SSH'
require_pattern scripts/integration-setup.sh \
  'target_write_file "$target_role"' \
  'Public-key handoff must write public keys through target SSH'
require_pattern scripts/integration-setup.sh \
  'copy_controller_public_key_to_target' \
  'Agent and Gerrit public-key handoff must use the shared target SSH copy helper'
reject_pattern scripts/integration-setup.sh \
  "install -d -m 700 -o '\$JENKINS_RUNTIME_ACCOUNT' -g '\$JENKINS_RUNTIME_GROUP' /harness/target/helper-state/integration" \
  'Integration setup must not transfer harness integration directory ownership to Jenkins'
reject_pattern scripts/integration-setup.sh \
  '"$(integration_host_state_dir)/keys"' \
  'Integration host state must not contain key directories'
reject_pattern scripts/integration-setup.sh \
  '"$(integration_host_state_dir)/scripts"' \
  'Integration host state must not contain script directories'
reject_pattern scripts/integration-setup.sh \
  'chmod 0770 "$(integration_host_state_dir)" "$(integration_host_state_dir)/keys"' \
  'Host integration dirs must not be made group-writable for Jenkins operations'
reject_pattern scripts/integration-setup.sh \
  'test -d /harness/target/helper-state/integration/keys && test -r /harness/target/helper-state/integration/keys && test -w /harness/target/helper-state/integration/keys' \
  'Integration setup must not validate Jenkins writes to harness-owned keys'
reject_pattern scripts/integration-setup.sh \
  'docker exec' \
  'Integration setup must not call docker exec outside Docker simulation'
reject_pattern scripts/integration-setup.sh \
  'docker cp' \
  'Integration setup must not call docker cp outside Docker simulation'
reject_pattern scripts/integration-setup.sh \
  'jenkins_container' \
  'Integration setup must not derive Jenkins container names'
reject_pattern scripts/integration-setup.sh \
  'gerrit_container' \
  'Integration setup must not derive Gerrit container names'
reject_pattern scripts/integration-setup.sh \
  'agent_container' \
  'Integration setup must not derive Jenkins agent container names'
reject_pattern scripts/integration-setup.sh \
  'copy_controller_public_key_to_container' \
  'Integration setup must not use container-specific public-key copy helpers'
reject_pattern scripts/integration-setup.sh \
  'prepare_generated_file' \
  'Integration setup must not repair stale generated harness scripts before writing them'
reject_pattern scripts/integration-setup.sh \
  'container_script="/tmp/step11-' \
  'Integration setup must not hand generated Jenkins Groovy scripts through /tmp'
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
  'GERRIT_SITE_PATH="/harness/target/helper-state/site"' \
  'Gerrit Docker override must not force product site under /harness/state'
reject_pattern scripts/gerrit-setup.sh \
  'GERRIT_ARTIFACT_OUTPUT_DIR="$GERRIT_BUNDLE_FACTORY_WORK_DIR"' \
  'Gerrit helper must not rewrite artifact output from simulation context'
reject_pattern scripts/gerrit-setup.sh \
  'GERRIT_STAGED_ARTIFACT_DIR="$GERRIT_STAGED_BUNDLE_PAYLOAD_DIR"' \
  'Gerrit helper must not rewrite staged artifact input from simulation context'
reject_pattern scripts/jenkins-controller-setup.sh \
  'JENKINS_HOME="${JENKINS_HOME:-/harness/target/helper-state/jenkins-home}"' \
  'Jenkins helper must not default product home under /harness/state'
reject_pattern scripts/integration-setup.sh \
  'JENKINS_HOME="${JENKINS_HOME:-/harness/target/helper-state/jenkins-home}"' \
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
  '"$GERRIT_RUNTIME_UID" "$GERRIT_RUNTIME_GID"' \
  'Gerrit helper must validate the reviewed numeric runtime identity'
require_pattern scripts/gerrit-setup.sh \
  'identity_action="$(realize_runtime_identity' \
  'Gerrit install must create or reuse the complete runtime identity'
require_pattern scripts/gerrit-setup.sh \
  'sudo -n -u "$GERRIT_RUNTIME_ACCOUNT" sh -c "$command_text"' \
  'Gerrit helper must delegate runtime-account operations when run by the operator'
require_pattern scripts/gerrit-setup.sh \
  'sudo -n sh -c "$command_text"' \
  'Gerrit helper must delegate privileged product-home operations when run by the operator'
require_pattern scripts/gerrit-setup.sh \
  'prepare_gerrit_runtime_directories' \
  'Gerrit helper must prepare product-home runtime dirs through delegated helpers'
require_pattern scripts/gerrit-setup.sh \
  'install_file_as_runtime "$GERRIT_STAGED_ARTIFACT_DIR/gerrit-3.13.6.war" "$GERRIT_SITE_PATH/bin/gerrit.war" 0644' \
  'Gerrit install must place the WAR through delegated runtime-owned install'
require_pattern scripts/gerrit-setup.sh \
  'render_template_as_runtime "$GERRIT_STAGED_ARTIFACT_DIR/gerrit.config.template" "$GERRIT_SITE_PATH/etc/gerrit.config"' \
  'Gerrit configure must render product-home config through delegated runtime-owned install'
require_pattern scripts/gerrit-setup.sh \
  'write_secure_config_as_runtime' \
  'Gerrit configure must write secure config through delegated runtime-owned install'
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
  '"$JENKINS_RUNTIME_UID" "$JENKINS_RUNTIME_GID"' \
  'Jenkins helper must validate the reviewed numeric runtime identity'
require_pattern scripts/jenkins-controller-setup.sh \
  'identity_action="$(realize_runtime_identity' \
  'Jenkins install must create or reuse the complete runtime identity'
require_pattern scripts/jenkins-controller-setup.sh \
  'sudo -n -u "$JENKINS_RUNTIME_ACCOUNT" sh -lc "$command"' \
  'Jenkins controller helper must delegate runtime-account operations when run by the operator'
require_pattern scripts/jenkins-controller-setup.sh \
  'sudo -n sh -c "$command"' \
  'Jenkins controller helper must delegate privileged product-home operations when run by the operator'
require_pattern scripts/jenkins-controller-setup.sh \
  'install_file_as_runtime "$JENKINS_STAGED_ARTIFACT_DIR/jenkins-2.555.3.war" "$JENKINS_HOME/war/jenkins.war" 0644' \
  'Jenkins controller install must place the WAR through delegated runtime-owned install'
reject_pattern scripts/jenkins-controller-setup.sh \
  '$JENKINS_HOME/war/jenkins-plugin-manager.jar' \
  'Jenkins controller runtime must not retain the bundle-factory plugin manager'
require_pattern scripts/jenkins-controller-setup.sh \
  'render_template_as_runtime "$JENKINS_STAGED_ARTIFACT_DIR/templates/jenkins-jcasc.yaml.template" "$CASC_JENKINS_CONFIG"' \
  'Jenkins controller JCasC must render through delegated runtime-owned install'
require_pattern scripts/jenkins-controller-setup.sh \
  'CASC_JENKINS_CONFIG="$JENKINS_HOME/jcasc/jenkins.yaml"' \
  'Jenkins controller helper must derive the JCasC path once from JENKINS_HOME'
require_pattern scripts/jenkins-controller-setup.sh \
  'text="${text//\{\{CASC_JENKINS_CONFIG\}\}/$CASC_JENKINS_CONFIG}"' \
  'Jenkins controller template rendering must use the derived JCasC path'
require_pattern scripts/jenkins-controller-setup.sh \
  'export CASC_JENKINS_CONFIG' \
  'Jenkins controller runtime must export the derived JCasC path'
require_pattern scripts/jenkins-controller-setup.sh \
  'export JAVA_OPTS="-Djava.awt.headless=true -Djenkins.install.runSetupWizard=false"' \
  'Jenkins controller runtime JAVA_OPTS must not duplicate the JCasC path'
reject_pattern scripts/jenkins-controller-setup.sh \
  '-Dcasc.jenkins.config=$JENKINS_HOME/jcasc/jenkins.yaml' \
  'Jenkins controller runtime must not set a duplicate JCasC Java property'
require_pattern templates/jenkins-controller/jenkins.service.template \
  'Environment=CASC_JENKINS_CONFIG={{CASC_JENKINS_CONFIG}}' \
  'Jenkins systemd unit must use CASC_JENKINS_CONFIG as the JCasC path source'
require_pattern templates/jenkins-controller/jenkins.service.template \
  'Environment="JAVA_OPTS=-Djava.awt.headless=true -Djenkins.install.runSetupWizard=false"' \
  'Jenkins systemd unit must quote JAVA_OPTS without duplicating the JCasC path'
reject_pattern templates/jenkins-controller/jenkins.service.template \
  'Environment=JAVA_OPTS=-Djava.awt.headless=true -Djenkins.install.runSetupWizard=false -Dcasc.jenkins.config={{JENKINS_HOME}}/jcasc/jenkins.yaml' \
  'Jenkins systemd unit must not use an unquoted JAVA_OPTS assignment'
reject_pattern templates/jenkins-controller/jenkins.service.template \
  '-Dcasc.jenkins.config={{JENKINS_HOME}}/jcasc/jenkins.yaml' \
  'Jenkins systemd unit must not set a duplicate JCasC Java property'
require_pattern templates/jenkins-controller/jenkins-service.env.template \
  'CASC_JENKINS_CONFIG={{CASC_JENKINS_CONFIG}}' \
  'Jenkins service env template must use CASC_JENKINS_CONFIG as the JCasC path source'
require_pattern templates/jenkins-controller/jenkins-service.env.template \
  'JAVA_ARGS=-Djenkins.install.runSetupWizard=false' \
  'Jenkins service env template JAVA_ARGS must not duplicate the JCasC path'
reject_pattern templates/jenkins-controller/jenkins-service.env.template \
  '-Dcasc.jenkins.config={{JENKINS_HOME}}/jcasc/jenkins.yaml' \
  'Jenkins service env template must not set a duplicate JCasC Java property'
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
  '"$JENKINS_AGENT_UID" "$JENKINS_AGENT_GID"' \
  'Agent helper must validate the reviewed numeric runtime identity'
require_pattern scripts/jenkins-agent-setup.sh \
  'identity_action="$(realize_runtime_identity' \
  'Agent install must create or reuse the complete runtime identity'
require_pattern scripts/jenkins-agent-setup.sh \
  'sudo -n sh -c "$command"' \
  'Jenkins agent helper must delegate privileged target operations when run by the operator'
require_pattern scripts/jenkins-agent-setup.sh \
  'install_file_as_agent "$JENKINS_AGENT_STAGED_ARTIFACT_DIR/jenkins-agent-bootstrap.txt" "$JENKINS_AGENT_STATE_DIR/bootstrap/jenkins-agent-bootstrap.txt" 0644' \
  'Jenkins agent install must place bootstrap files through delegated runtime-owned install'
require_pattern scripts/jenkins-agent-setup.sh \
  'render_template_as_agent "$JENKINS_AGENT_STAGED_ARTIFACT_DIR/templates/agent-runtime-profile.env.template" "$JENKINS_AGENT_STATE_DIR/etc/agent-runtime-profile.env"' \
  'Jenkins agent configure-runtime must render the staged runtime profile through delegated runtime-owned install'
require_pattern scripts/jenkins-agent-setup.sh \
  'render_template_as_root "$JENKINS_AGENT_STAGED_ARTIFACT_DIR/templates/sshd-policy.conf.template" "$JENKINS_AGENT_SSH_POLICY_PATH"' \
  'Jenkins agent configure-runtime must install the staged SSH policy with OS custody'
reject_pattern scripts/jenkins-agent-setup.sh \
  'render_template_as_agent "$JENKINS_AGENT_STATE_DIR/templates/' \
  'Jenkins agent configure-runtime must not read service-owned template copies as the operator'
reject_pattern scripts/jenkins-agent-setup.sh \
  'JENKINS_AGENT_ACCOUNT must be $JENKINS_AGENT_NATIVE_ACCOUNT' \
  'Agent helper must not require a fixed literal runtime account name'
reject_pattern scripts/jenkins-agent-setup.sh \
  'JENKINS_AGENT_GROUP must be $JENKINS_AGENT_NATIVE_GROUP' \
  'Agent helper must not require a fixed literal runtime group name'

require_pattern scripts/common.sh \
  'useradd --uid $(shell_quote "$uid") --gid $(shell_quote "$gid") --home-dir $(shell_quote "$home") --no-create-home' \
  'Role install must create missing runtime accounts from reviewed identity values'
require_pattern scripts/common.sh \
  'groupadd --gid $(shell_quote "$gid") $(shell_quote "$group")' \
  'Role install must create missing runtime groups from reviewed identity values'
require_pattern scripts/common.sh \
  'runtime identity state is partial' \
  'Role preflight must block partial runtime identity state'
reject_pattern scripts/jenkins-agent-setup.sh \
  '/harness/target/helper-state/agent/workspace' \
  'Agent helper must not accept /harness/target/helper-state/agent/workspace as product remote FS'
require_pattern scripts/jenkins-agent-setup.sh \
  'JENKINS_AGENT_REMOTE_FS must be $JENKINS_AGENT_NATIVE_REMOTE_FS, got $value' \
  'Agent helper error must describe the native remote FS boundary'

require_pattern simulation/docker/target/Dockerfile \
  'groupadd --gid 61000 ci-operator' \
  'Docker target image must include a distinct local ci-operator group'
require_pattern simulation/docker/target/Dockerfile \
  'useradd --uid 61000 --create-home --gid 61000 --home-dir /home/ci-operator --shell /bin/bash ci-operator' \
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
  'useradd --uid 61010 --gid 61010 --home-dir /srv/gerrit --shell /bin/bash gerrit' \
  'Gerrit runtime account must remain distinct from ci-operator'
require_pattern simulation/docker/target/Dockerfile \
  'useradd --uid 61020 --gid 61020 --home-dir /var/lib/jenkins --shell /bin/bash jenkins' \
  'Jenkins runtime account must remain distinct from ci-operator'
require_pattern simulation/docker/target/Dockerfile \
  'useradd --uid 61030 --gid 61030 --home-dir /var/lib/jenkins-agent --shell /bin/bash jenkins-agent' \
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
