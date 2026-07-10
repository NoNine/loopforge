#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

. "$repo_root/simulation/lib/common.sh"
. "$repo_root/simulation/lib/quote.sh"
. "$repo_root/simulation/lib/roles.sh"
. "$repo_root/simulation/lib/artifacts.sh"
. "$repo_root/simulation/lib/env.sh"
. "$repo_root/simulation/lib/logs.sh"
. "$repo_root/simulation/lib/evidence.sh"
. "$repo_root/simulation/vm/lib/paths.sh"
. "$repo_root/simulation/vm/lib/artifacts.sh"
. "$repo_root/simulation/vm/lib/lifecycle.sh"

HARNESS_MODE=vm-simulation
HARNESS_RUN_ID=vm-m6-test
LOOPFORGE_VM_SET_ID=m6-test
HARNESS_PUBLIC_INTERNET_FALLBACK_LABEL=simulation-only
HARNESS_UBUNTU_BASELINE_RELEASE=24.04
HARNESS_UBUNTU_BASELINE_CODENAME=noble
HARNESS_JAVA_BASELINE=21
HARNESS_GERRIT_BASELINE=3.13.6
HARNESS_JENKINS_BASELINE=2.555.3
HARNESS_JENKINS_PLUGIN_MANAGER_BASELINE=2.15.0
VM_OPERATOR_USER=ci-operator
HARNESS_GENERATED_RUN_DIR="$tmp_dir/run"
HARNESS_HOST_DIR="$HARNESS_GENERATED_RUN_DIR/host"
HARNESS_EVIDENCE_DIR="$HARNESS_HOST_DIR/evidence/harness"
HARNESS_LOG_DIR="$HARNESS_HOST_DIR/logs/harness"
HARNESS_EXPORTED_ARTIFACT_DIR="$HARNESS_HOST_DIR/artifacts/exported"
HARNESS_GERRIT_ENV_FILE="$HARNESS_HOST_DIR/runtime-inputs/gerrit.env"
HARNESS_JENKINS_CONTROLLER_ENV_FILE="$HARNESS_HOST_DIR/runtime-inputs/jenkins-controller.env"
HARNESS_JENKINS_AGENT_ENV_FILE="$HARNESS_HOST_DIR/runtime-inputs/jenkins-agent.env"
calls="$tmp_dir/calls.log"
guests="$tmp_dir/guests"
mkdir -p "$HARNESS_HOST_DIR/runtime-inputs" "$HARNESS_EVIDENCE_DIR" \
  "$HARNESS_LOG_DIR" "$HARNESS_EXPORTED_ARTIFACT_DIR" "$guests"

cat >"$HARNESS_GERRIT_ENV_FILE" <<'EOF'
GERRIT_VERIFICATION_MODE="docker-simulation"
EOF
cat >"$HARNESS_JENKINS_CONTROLLER_ENV_FILE" <<'EOF'
JENKINS_VERIFICATION_MODE="docker-simulation"
EOF
cat >"$HARNESS_JENKINS_AGENT_ENV_FILE" <<'EOF'
JENKINS_AGENT_VERIFICATION_MODE="docker-simulation"
EOF
chmod 0600 "$HARNESS_HOST_DIR"/runtime-inputs/*.env

roles=(gerrit jenkins-controller jenkins-agent)

guest_path() {
  printf '%s/%s%s\n' "$guests" "${1:?machine required}" "${2:?path required}"
}

translate_guest_script() {
  local machine script root user group
  machine="${1:?machine required}"
  script="${2:?script required}"
  root="$guests/$machine"
  user="$(id -un)"
  group="$(id -gn)"
  script="${script//\/home\/ci-operator/$root/home/ci-operator}"
  script="${script//\/var\/lib\/loopforge/$root/var/lib/loopforge}"
  script="${script//\/var\/log\/loopforge/$root/var/log/loopforge}"
  script="${script//\/etc\/loopforge-source-boundary/$root/etc/loopforge-source-boundary}"
  script="${script//ci-operator:ci-operator/$user:$group}"
  printf '%s\n' "$script"
}

vm_config_load_runtime() { :; }
vm_set_verify_run_and_set() { :; }
vm_libvirt_require_running() {
  [ ! -f "$tmp_dir/stopped-${1:?machine required}" ] || return 1
}
vm_ssh_verify_known_host() { :; }
vm_ssh_role_machine() { printf '%s\n' "${1:?role required}"; }
vm_path_bounded_log() { bounded_log_path_in_dir "$HARNESS_LOG_DIR" "${1:?name required}"; }

vm_ssh_run_machine() {
  local machine script translated root
  machine="${1:?machine required}"
  script="${2:?script required}"
  vm_libvirt_require_running "$machine" || return $?
  root="$guests/$machine"
  mkdir -p "$root/home/ci-operator" "$root/etc"
  printf 'public_internet_fallback=simulation-only\n' >"$root/etc/loopforge-source-boundary"
  printf 'ssh machine=%s script=%s\n' "$machine" "$script" >>"$calls"
  translated="$(translate_guest_script "$machine" "$script")"
  FAKE_GUEST_ROOT="$root" bash -c "$translated"
}

vm_ssh_copy_file_to_machine_atomic() {
  local machine source target mode mapped
  machine="${1:?machine required}"
  source="${2:?source required}"
  target="${3:?target required}"
  mode="${4:-0600}"
  mapped="$(guest_path "$machine" "$target")"
  mkdir -p "$(dirname "$mapped")"
  cp -- "$source" "$mapped.tmp"
  chmod "$mode" "$mapped.tmp"
  mv -f -- "$mapped.tmp" "$mapped"
  printf 'copy-to machine=%s source=%s target=%s mode=%s\n' \
    "$machine" "$source" "$target" "$mode" >>"$calls"
}

vm_ssh_copy_file_from_machine() {
  local machine source target
  machine="${1:?machine required}"
  source="${2:?source required}"
  target="${3:?target required}"
  cp -- "$(guest_path "$machine" "$source")" "$target"
  chmod 0600 "$target"
  printf 'copy-from machine=%s source=%s target=%s\n' \
    "$machine" "$source" "$target" >>"$calls"
}

vm_ssh_stage_role_helpers() {
  local machine role helper root mapped
  machine="${1:?machine required}"
  root="$(vm_path_guest_role_helpers_root)"
  mapped="$(guest_path "$machine" "$root")"
  rm -rf -- "$mapped"
  mkdir -p "$mapped/scripts" "$mapped/templates/gerrit" \
    "$mapped/templates/jenkins-controller" "$mapped/templates/jenkins-agent"
  printf 'shared role helper library\n' >"$mapped/scripts/common.sh"
  for role in "${roles[@]}"; do
    helper="$(helper_for_role "$role")"
    cat >"$mapped/$helper" <<'HELPER'
#!/usr/bin/env bash
set -euo pipefail
helper="$(basename "$0")"
env_file=""
command=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --env) env_file="$2"; shift 2 ;;
    --yes) shift ;;
    *) command="$1"; shift ;;
  esac
done
case "$helper" in
  gerrit-setup.sh) role=gerrit; payload=gerrit; bundle=gerrit-artifacts-bundle ;;
  jenkins-controller-setup.sh) role=jenkins-controller; payload=jenkins; bundle=jenkins-artifacts-bundle ;;
  jenkins-agent-setup.sh) role=jenkins-agent; payload=jenkins-agent; bundle=jenkins-agent-artifacts-bundle ;;
esac
grep -Fq 'vm-simulation' "$env_file"
if [ "$command" = prepare-target-workspace ]; then
  mkdir -p "$FAKE_GUEST_ROOT/var/lib/loopforge/staging" "$FAKE_GUEST_ROOT/var/log/loopforge"
  exit 0
fi
[ "$command" = prepare-artifacts ]
preparing="$FAKE_GUEST_ROOT/var/lib/loopforge/preparing"
dir="$preparing/$bundle/$payload"
rm -rf "$preparing/$bundle"
mkdir -p "$dir"
printf 'payload role=%s\n' "$role" >"$dir/payload.txt"
case "$role" in
  gerrit)
    gerrit=3.13.6; jenkins=not-applicable; manager=not-applicable
    printf 'war\n' >"$dir/gerrit-3.13.6.war"
    extra='war=gerrit-3.13.6.war'
    ;;
  jenkins-controller)
    gerrit=not-applicable; jenkins=2.555.3; manager=2.15.0
    printf 'war\n' >"$dir/jenkins-2.555.3.war"
    printf 'manager\n' >"$dir/jenkins-plugin-manager-2.15.0.jar"
    extra=$'war=jenkins-2.555.3.war\nplugin_manager=jenkins-plugin-manager-2.15.0.jar'
    ;;
  jenkins-agent)
    gerrit=not-applicable; jenkins=not-applicable; manager=not-applicable
    printf 'bootstrap\n' >"$dir/jenkins-agent-bootstrap.txt"
    mkdir -p "$dir/templates"
    printf 'runtime profile template\n' >"$dir/templates/agent-runtime-profile.env.template"
    printf 'SSH policy template\n' >"$dir/templates/sshd-policy.conf.template"
    chmod 0600 "$dir/templates/agent-runtime-profile.env.template" \
      "$dir/templates/sshd-policy.conf.template"
    extra='bootstrap=jenkins-agent-bootstrap.txt'
    ;;
esac
cat >"$dir/manifest.txt" <<EOF
harness_manifest_version=1
role=$role
bundle_name=$bundle
ubuntu_release=24.04
ubuntu_codename=noble
java_version=21
gerrit_version=$gerrit
jenkins_version=$jenkins
jenkins_plugin_manager_version=$manager
$extra
EOF
(cd "$dir" && find . -type f ! -name checksums.sha256 -print0 | sort -z | xargs -0 sha256sum >checksums.sha256)
(cd "$preparing/$bundle" && tar -czf "$preparing/$bundle.tar.gz" "$payload")
(cd "$preparing" && sha256sum "$bundle.tar.gz" >"$bundle.tar.gz.sha256")
HELPER
    chmod 0700 "$mapped/$helper"
  done
  find "$mapped" -type d -exec chmod 0700 {} +
  find "$mapped" -type f ! -name '*-setup.sh' -exec chmod 0600 {} +
  printf 'role-helpers machine=%s path=%s\n' "$machine" "$root" >>"$calls"
}

vm_ssh_stage_role_helpers_all() {
  local machine
  for machine in bundle-factory gerrit jenkins-controller jenkins-agent; do
    vm_ssh_stage_role_helpers "$machine"
  done
}

for machine in bundle-factory gerrit jenkins-controller jenkins-agent; do
  mkdir -p "$guests/$machine/home/ci-operator" "$guests/$machine/etc"
done

vm_ssh_stage_role_helpers_all
vm_cmd_prepare_artifacts "" >"$tmp_dir/prepare.out"
vm_cmd_stage_artifacts "" >"$tmp_dir/stage.out"

for machine in bundle-factory gerrit jenkins-controller jenkins-agent; do
  helper_root="$(guest_path "$machine" "$(vm_path_guest_role_helpers_root)")"
  [ "$(stat -c %a "$helper_root")" = 700 ]
  [ "$(stat -c %a "$helper_root/scripts/common.sh")" = 600 ]
  for role in "${roles[@]}"; do
    [ "$(stat -c %a "$helper_root/$(helper_for_role "$role")")" = 700 ]
  done
done

for role in "${roles[@]}"; do
  bundle="$(bundle_name_for_role "$role")"
  payload="$(bundle_payload_dir_for_role "$role")"
  machine="$role"
  grep -Fxq "prepare-artifacts[$role]: ok artifact-export=$bundle.tar.gz" "$tmp_dir/prepare.out"
  grep -Fxq "stage-artifacts[$role]: ok" "$tmp_dir/stage.out"
  [ -f "$HARNESS_EXPORTED_ARTIFACT_DIR/$bundle.tar.gz" ]
  [ -f "$HARNESS_EXPORTED_ARTIFACT_DIR/$bundle.tar.gz.sha256" ]
  [ -f "$guests/$machine/var/lib/loopforge/staging/$payload/manifest.txt" ]
  grep -Fq "role=$role" "$guests/$machine/var/lib/loopforge/staging/$payload/manifest.txt"
  if [ "$role" = jenkins-agent ]; then
    for template in agent-runtime-profile.env.template sshd-policy.conf.template; do
      staged_template="$guests/$machine/var/lib/loopforge/staging/$payload/templates/$template"
      [ -r "$staged_template" ] || {
        printf 'VM staged Jenkins agent template must remain operator-readable: %s\n' "$template" >&2
        exit 1
      }
      [ "$(stat -c %a "$staged_template")" = 600 ]
    done
  fi
  for env_machine in bundle-factory "$machine"; do
    env_path="$guests/$env_machine/home/ci-operator/loopforge-inputs/$role.env"
    [ -f "$env_path" ]
    [ "$(stat -c %a "$env_path")" = 600 ]
    grep -Fq 'vm-simulation' "$env_path"
    [ -x "$(guest_path "$env_machine" "$(vm_path_guest_role_helper "$role")")" ]
  done
  prepare_evidence="$(find "$HARNESS_EVIDENCE_DIR" -name "prepare-artifacts-$role-*.json" | sort | tail -1)"
  stage_evidence="$(find "$HARNESS_EVIDENCE_DIR" -name "stage-artifacts-$role-*.json" | sort | tail -1)"
  grep -Fq '"verification_mode": "vm-simulation"' "$prepare_evidence"
  grep -Fq '"source_boundary": "simulation-only"' "$prepare_evidence"
  grep -Fq '"transfer_mode": "target-os-ssh"' "$stage_evidence"
  grep -Fq "\"artifact_manifest_references\": \"/var/lib/loopforge/staging/$payload/manifest.txt\"" "$stage_evidence"
done

grep -Fq -- \
  'render_template_as_agent "$JENKINS_AGENT_STAGED_ARTIFACT_DIR/templates/agent-runtime-profile.env.template"' \
  "$repo_root/scripts/jenkins-agent-setup.sh"
grep -Fq -- \
  'render_template_as_agent "$JENKINS_AGENT_STAGED_ARTIFACT_DIR/templates/sshd-policy.conf.template"' \
  "$repo_root/scripts/jenkins-agent-setup.sh"
if grep -Fq -- \
  'render_template_as_agent "$JENKINS_AGENT_STATE_DIR/templates/' \
  "$repo_root/scripts/jenkins-agent-setup.sh"; then
  printf 'VM-staged Jenkins agent helper must not read service-owned template copies\n' >&2
  exit 1
fi

grep -Fq 'target=/home/ci-operator/loopforge-inputs/gerrit.env mode=0600' "$calls"
if grep -Eq '/home/ci-operator/loopforge-inputs/(bundle-factory|vm-m6-test)/' "$calls"; then
  printf 'VM role envs must use the selected flat guest input layout\n' >&2
  exit 1
fi
if grep -Fq -- '.loopforge-package-' "$calls"; then
  printf 'VM role helpers must not use run-scoped package directories\n' >&2
  exit 1
fi
if grep -Fq 'target/artifacts/staging' "$calls"; then
  printf 'VM artifact staging must not use a generated target sideband\n' >&2
  exit 1
fi

cp "$HARNESS_EXPORTED_ARTIFACT_DIR/gerrit-artifacts-bundle.tar.gz" "$tmp_dir/gerrit-valid.tar.gz"
printf 'tampered\n' >>"$HARNESS_EXPORTED_ARTIFACT_DIR/gerrit-artifacts-bundle.tar.gz"
if vm_cmd_stage_artifacts gerrit >"$tmp_dir/stage-fail.out" 2>"$tmp_dir/stage-fail.err"; then
  printf 'stage-artifacts must reject archive checksum drift\n' >&2
  exit 1
fi
grep -Fq 'stage-artifacts[gerrit]: failed' "$tmp_dir/stage-fail.out"
failure_evidence="$(find "$HARNESS_EVIDENCE_DIR" -name 'stage-artifacts-gerrit-*.json' | sort | tail -1)"
grep -Fq '"status": "fail"' "$failure_evidence"

cp "$tmp_dir/gerrit-valid.tar.gz" "$HARNESS_EXPORTED_ARTIFACT_DIR/gerrit-artifacts-bundle.tar.gz"
touch "$tmp_dir/stopped-gerrit"
if vm_cmd_stage_artifacts gerrit >"$tmp_dir/stopped.out" 2>"$tmp_dir/stopped.err"; then
  printf 'stage-artifacts must reject a stopped target VM\n' >&2
  exit 1
fi
