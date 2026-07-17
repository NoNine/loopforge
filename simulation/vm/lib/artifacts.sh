#!/usr/bin/env bash

vm_artifacts_role_machine() {
  vm_ssh_role_machine "${1:?role required}"
}

vm_artifacts_role_input_file() {
  case "${1:?role required}" in
    gerrit) printf '%s\n' "$HARNESS_GERRIT_ENV_FILE" ;;
    jenkins-controller) printf '%s\n' "$HARNESS_JENKINS_CONTROLLER_ENV_FILE" ;;
    jenkins-agent) printf '%s\n' "$HARNESS_JENKINS_AGENT_ENV_FILE" ;;
  esac
}

vm_artifacts_guest_preparing_dir() {
  printf '/var/lib/loopforge/preparing/%s\n' "$(bundle_name_for_role "${1:?role required}")"
}

vm_artifacts_guest_archive() {
  printf '/var/lib/loopforge/preparing/%s.tar.gz\n' "$(bundle_name_for_role "${1:?role required}")"
}

vm_artifacts_guest_archive_checksum() {
  printf '%s.sha256\n' "$(vm_artifacts_guest_archive "${1:?role required}")"
}

vm_artifacts_exported_archive() {
  printf '%s/%s.tar.gz\n' \
    "$HARNESS_EXPORTED_ARTIFACT_DIR" \
    "$(bundle_name_for_role "${1:?role required}")"
}

vm_artifacts_exported_checksum() {
  printf '%s.sha256\n' "$(vm_artifacts_exported_archive "${1:?role required}")"
}

vm_artifacts_target_payload() {
  printf '/var/lib/loopforge/staging/%s\n' \
    "$(bundle_payload_dir_for_role "${1:?role required}")"
}

vm_artifacts_verify_source_boundary() {
  local machine
  machine="${1:?machine required}"
  vm_ssh_run_machine "$machine" \
    "set -eu; test \"\$(cat /etc/loopforge-source-boundary)\" = $(shell_quote "public_internet_fallback=$HARNESS_PUBLIC_INTERNET_FALLBACK_LABEL"); printf 'source-boundary=ready machine=%s label=%s\\n' $(shell_quote "$machine") $(shell_quote "$HARNESS_PUBLIC_INTERNET_FALLBACK_LABEL")"
}

vm_artifacts_stage_role_env() {
  local machine role root remote_env effective
  machine="${1:?machine required}"
  role="${2:?role required}"
  root="$(vm_path_guest_input_root)"
  remote_env="$(vm_path_guest_role_env "$role")"
  effective="$(vm_artifacts_role_input_file "$role")"
  require_readable_file "Published effective role input for $role" "$effective"
  vm_ssh_run_machine "$machine" \
    "set -eu; install -d -m 0700 $(shell_quote "$root")" || return $?
  vm_ssh_copy_file_to_machine_atomic "$machine" "$effective" "$remote_env" 0600 ||
    return $?
  vm_ssh_run_machine "$machine" \
    "set -eu; test \"\$(stat -c %U:%G $(shell_quote "$remote_env"))\" = $(shell_quote "$VM_OPERATOR_USER:$VM_OPERATOR_USER"); test \"\$(stat -c %a $(shell_quote "$remote_env"))\" = 600; printf 'role-input=ready role=%s path=%s\\n' $(shell_quote "$role") $(shell_quote "$remote_env")"
}

vm_artifacts_validate_archive_pair() {
  local role archive checksum payload tmp entries rc
  role="${1:?role required}"
  archive="${2:?archive required}"
  checksum="${3:?checksum required}"
  payload="$(bundle_payload_dir_for_role "$role")"
  [ -f "$archive" ] || return 1
  [ -f "$checksum" ] || return 1
  verify_checksum_file_in_dir "$checksum" "$(dirname "$archive")" /dev/stdout || return 1
  entries="$(tar -tzf "$archive")" || return 1
  printf '%s\n' "$entries" | awk -v prefix="$payload/" '
    $0 ~ /^\// || $0 ~ /(^|\/)\.\.($|\/)/ || index($0, prefix) != 1 { bad=1 }
    END { exit bad || NR == 0 }
  ' || return 1
  tmp="$(mktemp -d "$HARNESS_HOST_DIR/.artifact-verify-$role.XXXXXX")"
  rc=0
  tar --no-same-owner -xzf "$archive" -C "$tmp" || rc=$?
  if [ "$rc" -eq 0 ]; then
    verify_checksum_file_in_dir "$tmp/$payload/checksums.sha256" "$tmp/$payload" /dev/stdout || rc=$?
  fi
  if [ "$rc" -eq 0 ]; then
    validate_role_baseline_manifest "$role" "$tmp/$payload/manifest.txt" /dev/stdout || rc=$?
  fi
  rm -rf -- "$tmp"
  return "$rc"
}

vm_artifacts_prepare_guest() {
  local role machine helper_path guest_env guest_dir archive checksum script rc
  role="${1:?role required}"
  machine="bundle-factory"
  helper_path="$(vm_path_guest_role_helper "$role")"
  guest_env="$(vm_path_guest_role_env "$role")"
  guest_dir="$(vm_artifacts_guest_preparing_dir "$role")/$(bundle_payload_dir_for_role "$role")"
  archive="$(vm_artifacts_guest_archive "$role")"
  checksum="$(vm_artifacts_guest_archive_checksum "$role")"
  vm_set_verify_run_and_set || return $?
  vm_artifacts_verify_source_boundary "$machine" || return $?
  vm_artifacts_stage_role_env "$machine" "$role" || return $?
  script="set -eu; $(shell_quote "$helper_path") --env $(shell_quote "$guest_env") --yes prepare-artifacts; test -f $(shell_quote "$guest_dir/manifest.txt"); test -f $(shell_quote "$guest_dir/checksums.sha256"); cd $(shell_quote "$guest_dir"); sha256sum -c checksums.sha256; cd /var/lib/loopforge/preparing; sha256sum -c $(shell_quote "$(basename "$checksum")")"
  rc=0
  vm_ssh_run_machine "$machine" "$script" || rc=$?
  [ "$rc" -eq 0 ] || return "$rc"
  printf 'artifact-prepare=ready role=%s machine=%s archive=%s\n' "$role" "$machine" "$archive"
}

vm_artifacts_export_from_guest() {
  local role archive checksum export_archive export_checksum tmp_archive tmp_checksum
  role="${1:?role required}"
  archive="$(vm_artifacts_guest_archive "$role")"
  checksum="$(vm_artifacts_guest_archive_checksum "$role")"
  export_archive="$(vm_artifacts_exported_archive "$role")"
  export_checksum="$(vm_artifacts_exported_checksum "$role")"
  mkdir -p "$HARNESS_EXPORTED_ARTIFACT_DIR"
  tmp_archive="$export_archive.loopforge-tmp-$$"
  tmp_checksum="$export_checksum.loopforge-tmp-$$"
  rm -f -- "$tmp_archive" "$tmp_checksum"
  vm_ssh_copy_file_from_machine bundle-factory "$archive" "$tmp_archive" || return $?
  vm_ssh_copy_file_from_machine bundle-factory "$checksum" "$tmp_checksum" || {
    rm -f -- "$tmp_archive" "$tmp_checksum"
    return 1
  }
  mv -f -- "$tmp_archive" "$export_archive"
  mv -f -- "$tmp_checksum" "$export_checksum"
  chmod "$LF_MODE_PUBLIC_FILE" "$export_archive" "$export_checksum"
  vm_artifacts_validate_archive_pair "$role" "$export_archive" "$export_checksum" || return $?
  printf 'artifact-export=ready role=%s archive=%s transfer=target-os-ssh\n' \
    "$role" "$(basename "$export_archive")"
}

vm_artifacts_prepare_role() {
  local role
  role="${1:?role required}"
  vm_artifacts_prepare_guest "$role" || return $?
  vm_artifacts_export_from_guest "$role"
}

vm_artifacts_prepare_target_workspace() {
  local role machine helper_path guest_env rc
  role="${1:?role required}"
  machine="$(vm_artifacts_role_machine "$role")"
  helper_path="$(vm_path_guest_role_helper "$role")"
  guest_env="$(vm_path_guest_role_env "$role")"
  vm_artifacts_stage_role_env "$machine" "$role" || return $?
  rc=0
  vm_ssh_run_machine "$machine" \
    "set -eu; $(shell_quote "$helper_path") --env $(shell_quote "$guest_env") --yes prepare-target-workspace; test -d /var/lib/loopforge/staging; test \"\$(stat -c %U:%G /var/lib/loopforge/staging)\" = $(shell_quote "$VM_OPERATOR_USER:$VM_OPERATOR_USER")" || rc=$?
  return "$rc"
}

vm_artifacts_target_validation_script() {
  local role payload bundle archive checksum gerrit jenkins plugin_manager
  role="${1:?role required}"
  payload="$(vm_artifacts_target_payload "$role")"
  bundle="$(bundle_name_for_role "$role")"
  archive="/var/lib/loopforge/staging/$bundle.tar.gz"
  checksum="$archive.sha256"
  case "$role" in
    gerrit)
      gerrit="$HARNESS_GERRIT_BASELINE"
      jenkins=not-applicable
      plugin_manager=not-applicable
      ;;
    jenkins-controller)
      gerrit=not-applicable
      jenkins="$HARNESS_JENKINS_BASELINE"
      plugin_manager="$HARNESS_JENKINS_PLUGIN_MANAGER_BASELINE"
      ;;
    jenkins-agent)
      gerrit=not-applicable
      jenkins=not-applicable
      plugin_manager=not-applicable
      ;;
  esac
  cat <<EOF
set -eu
staging=/var/lib/loopforge/staging
archive=$(shell_quote "$archive")
checksum=$(shell_quote "$checksum")
payload=$(shell_quote "$payload")
cd "\$staging"
sha256sum -c "\$(basename "\$checksum")"
rm -rf -- "\$payload"
tar --no-same-owner -xzf "\$(basename "\$archive")" -C "\$staging"
test -f "\$payload/manifest.txt"
test -f "\$payload/checksums.sha256"
cd "\$payload"
sha256sum -c checksums.sha256
expect_manifest() {
  key="\$1"
  expected="\$2"
  actual="\$(awk -F= -v key="\$key" '\$1 == key { print substr(\$0, length(key) + 2); found=1; exit } END { if (!found) exit 1 }' manifest.txt)"
  test "\$actual" = "\$expected"
}
expect_manifest harness_manifest_version 1
expect_manifest role $(shell_quote "$role")
expect_manifest bundle_name $(shell_quote "$bundle")
expect_manifest ubuntu_release $(shell_quote "$HARNESS_UBUNTU_BASELINE_RELEASE")
expect_manifest ubuntu_codename $(shell_quote "$HARNESS_UBUNTU_BASELINE_CODENAME")
expect_manifest java_version $(shell_quote "$HARNESS_JAVA_BASELINE")
expect_manifest gerrit_version $(shell_quote "$gerrit")
expect_manifest jenkins_version $(shell_quote "$jenkins")
expect_manifest jenkins_plugin_manager_version $(shell_quote "$plugin_manager")
test "\$(cat /etc/loopforge-source-boundary)" = $(shell_quote "public_internet_fallback=$HARNESS_PUBLIC_INTERNET_FALLBACK_LABEL")
printf 'artifact-stage=ready role=%s payload=%s source-boundary=%s transfer=target-os-ssh\\n' $(shell_quote "$role") "\$payload" $(shell_quote "$HARNESS_PUBLIC_INTERNET_FALLBACK_LABEL")
EOF
}

vm_artifacts_stage_role() {
  local role machine archive checksum remote_archive remote_checksum script
  role="${1:?role required}"
  machine="$(vm_artifacts_role_machine "$role")"
  archive="$(vm_artifacts_exported_archive "$role")"
  checksum="$(vm_artifacts_exported_checksum "$role")"
  remote_archive="/var/lib/loopforge/staging/$(basename "$archive")"
  remote_checksum="/var/lib/loopforge/staging/$(basename "$checksum")"
  vm_set_verify_run_and_set || return $?
  vm_artifacts_validate_archive_pair "$role" "$archive" "$checksum" || return $?
  vm_artifacts_verify_source_boundary "$machine" || return $?
  vm_artifacts_prepare_target_workspace "$role" || return $?
  vm_ssh_copy_file_to_machine_atomic "$machine" "$archive" "$remote_archive" 0644 || return $?
  vm_ssh_copy_file_to_machine_atomic "$machine" "$checksum" "$remote_checksum" 0644 || return $?
  script="$(vm_artifacts_target_validation_script "$role")"
  vm_ssh_run_machine "$machine" "$script"
}

vm_artifacts_verify_staged_role() {
  local role machine payload bundle gerrit jenkins plugin_manager script
  role="${1:?role required}"
  machine="$(vm_artifacts_role_machine "$role")"
  payload="$(vm_artifacts_target_payload "$role")"
  bundle="$(bundle_name_for_role "$role")"
  case "$role" in
    gerrit)
      gerrit="$HARNESS_GERRIT_BASELINE"
      jenkins=not-applicable
      plugin_manager=not-applicable
      ;;
    jenkins-controller)
      gerrit=not-applicable
      jenkins="$HARNESS_JENKINS_BASELINE"
      plugin_manager="$HARNESS_JENKINS_PLUGIN_MANAGER_BASELINE"
      ;;
    jenkins-agent)
      gerrit=not-applicable
      jenkins=not-applicable
      plugin_manager=not-applicable
      ;;
  esac
  script=$(cat <<EOF
set -eu
payload=$(shell_quote "$payload")
. /etc/os-release
test "\$VERSION_ID" = $(shell_quote "$HARNESS_UBUNTU_BASELINE_RELEASE")
test "\$VERSION_CODENAME" = $(shell_quote "$HARNESS_UBUNTU_BASELINE_CODENAME")
test -d "\$payload" || { printf 'missing_staged_artifacts payload=%s\\n' "\$payload"; exit 1; }
test -f "\$payload/manifest.txt" || { printf 'missing_staged_artifacts manifest=%s\\n' "\$payload/manifest.txt"; exit 1; }
test -f "\$payload/checksums.sha256" || { printf 'missing_staged_artifacts checksums=%s\\n' "\$payload/checksums.sha256"; exit 1; }
cd "\$payload"
sha256sum -c checksums.sha256
expect_manifest() {
  key="\$1"
  expected="\$2"
  actual="\$(awk -F= -v key="\$key" '\$1 == key { print substr(\$0, length(key) + 2); found=1; exit } END { if (!found) exit 1 }' manifest.txt)"
  test "\$actual" = "\$expected" || { printf 'baseline_drift field=%s expected=%s actual=%s\\n' "\$key" "\$expected" "\$actual"; exit 1; }
}
expect_manifest harness_manifest_version 1
expect_manifest role $(shell_quote "$role")
expect_manifest bundle_name $(shell_quote "$bundle")
expect_manifest ubuntu_release $(shell_quote "$HARNESS_UBUNTU_BASELINE_RELEASE")
expect_manifest ubuntu_codename $(shell_quote "$HARNESS_UBUNTU_BASELINE_CODENAME")
expect_manifest java_version $(shell_quote "$HARNESS_JAVA_BASELINE")
expect_manifest gerrit_version $(shell_quote "$gerrit")
expect_manifest jenkins_version $(shell_quote "$jenkins")
expect_manifest jenkins_plugin_manager_version $(shell_quote "$plugin_manager")
test "\$(cat /etc/loopforge-source-boundary)" = $(shell_quote "public_internet_fallback=$HARNESS_PUBLIC_INTERNET_FALLBACK_LABEL")
printf 'staged-artifacts=ready role=%s payload=%s\\n' $(shell_quote "$role") "\$payload"
EOF
)
  vm_ssh_run_machine "$machine" "$script"
}

vm_write_artifact_evidence() {
  local checkpoint role status log_ref message file manifest_ref checksum_ref target
  local q_timestamp q_checkpoint q_role q_status q_log q_message q_manifest q_checksum q_target
  checkpoint="${1:?checkpoint required}"
  role="${2:?role required}"
  status="${3:?status required}"
  log_ref="${4:?bounded log required}"
  message="${5:-}"
  mkdir -p "$HARNESS_EVIDENCE_DIR"
  file="$(evidence_record_path "$HARNESS_EVIDENCE_DIR" "$checkpoint" "$role")"
  case "$checkpoint" in
    prepare-artifacts)
      manifest_ref="$(vm_artifacts_guest_preparing_dir "$role")/$(bundle_payload_dir_for_role "$role")/manifest.txt"
      checksum_ref="$(vm_artifacts_guest_archive_checksum "$role");$(vm_artifacts_guest_preparing_dir "$role")/$(bundle_payload_dir_for_role "$role")/checksums.sha256"
      target="bundle-factory"
      ;;
    stage-artifacts)
      manifest_ref="$(vm_artifacts_target_payload "$role")/manifest.txt"
      checksum_ref="/var/lib/loopforge/staging/$(basename "$(vm_artifacts_exported_checksum "$role")");$(vm_artifacts_target_payload "$role")/checksums.sha256"
      target="$(vm_artifacts_role_machine "$role")"
      ;;
  esac
  q_timestamp="$(json_quote "$(iso_timestamp_utc)")"
  q_checkpoint="$(json_quote "$checkpoint")"
  q_role="$(json_quote "$role")"
  q_status="$(json_quote "$status")"
  q_log="$(json_quote "$log_ref")"
  q_message="$(json_quote "$message")"
  q_manifest="$(json_quote "$manifest_ref")"
  q_checksum="$(json_quote "$checksum_ref")"
  q_target="$(json_quote "$target")"
  cat >"$file" <<EOF
{
  "verification_mode": "vm-simulation",
  "timestamp": $q_timestamp,
  "package_version": "gerrit-jenkins-setup",
  "helper_command_version": "simulation/vm/simulate.sh",
  "role_or_environment": $q_role,
  "checkpoint": $q_checkpoint,
  "command": $q_checkpoint,
  "status": $q_status,
  "run_id": $(json_quote "$HARNESS_RUN_ID"),
  "set_id": $(json_quote "$HARNESS_SET_ID"),
  "target_vm": $q_target,
  "artifact_manifest_references": $q_manifest,
  "checksum_references": $q_checksum,
  "checksum_verification": $(json_quote "$([ "$status" = pass ] && printf pass || printf not-proven)"),
  "source_boundary": $(json_quote "$HARNESS_PUBLIC_INTERNET_FALLBACK_LABEL"),
  "transfer_mode": "target-os-ssh",
  "bounded_log": $q_log,
  "message": $q_message,
  "redaction": "secrets-not-recorded"
}
EOF
  chmod 0600 "$file"
  printf '%s\n' "$file"
}
