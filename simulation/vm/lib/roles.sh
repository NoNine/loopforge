#!/usr/bin/env bash

vm_roles_assert_no_placeholder_success() {
  local log
  log="${1:?log required}"
  ! grep -Eiq \
    'dummy success|operation-plan-only|planned-checks-only|placeholder success|would validate|would run|target-local observable|proof[[:space:]]*=[[:space:]]*modeled|real_execution[[:space:]]*=[[:space:]]*false' \
    "$log"
}

vm_roles_assert_no_contradictory_failure() {
  local log
  log="${1:?log required}"
  ! grep -Eiq \
    '(^|[[:space:]])(ERROR|FAILED|Timed out|Traceback|Exception)(:|[[:space:]])|BLOCKED:' \
    "$log"
}

vm_roles_failure_status() {
  local log
  log="${1:?log required}"
  if grep -Eiq \
    'missing_staged_artifacts|baseline_drift|BLOCKED:|Missing .* checkpoint|Stale .* checkpoint' \
    "$log"; then
    printf 'blocked\n'
  else
    printf 'fail\n'
  fi
}

vm_roles_evidence_pattern() {
  case "${1:?role required}" in
    gerrit) printf 'gerrit-readiness-*.json\n' ;;
    jenkins-controller) printf 'jenkins-controller-readiness-*.json\n' ;;
    jenkins-agent) printf 'jenkins-agent-readiness-*.json\n' ;;
  esac
}

vm_roles_copy_evidence() {
  local role machine pattern remote evidence_dir log_dir evidence_copy normalized ref dest
  role="${1:?role required}"
  machine="$(vm_ssh_role_machine "$role")"
  pattern="$(vm_roles_evidence_pattern "$role")"
  evidence_dir="$HARNESS_TARGET_DIR/evidence/$role"
  log_dir="$HARNESS_TARGET_DIR/logs/$role"
  remote="$(vm_ssh_run_machine "$machine" \
    "find /var/lib/loopforge/evidence -maxdepth 1 -type f -name $(shell_quote "$pattern") -print | sort | tail -1")"
  [ -n "$remote" ] || die "Missing role readiness evidence on target VM: $role"
  evidence_copy="$evidence_dir/$(basename "$remote")"
  vm_ssh_copy_file_from_machine "$machine" "$remote" "$evidence_copy" || return $?
  python3 - "$evidence_copy" <<'PY' || return $?
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
if data.get("verification_mode") != "vm-simulation" or data.get("status") != "pass":
    raise SystemExit("role evidence is not a vm-simulation pass")
PY
  while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    case "$ref" in
      /*) dest="$log_dir/${ref#/}" ;;
      *) die "Unsupported relative bounded log reference for $role: $ref" ;;
    esac
    vm_ssh_copy_file_from_machine "$machine" "$ref" "$dest" || return $?
    [ -s "$dest" ] || die "Copied role bounded log is empty: $dest"
  done < <(python3 - "$evidence_copy" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
for ref in data.get("bounded_log_references", "").split(";"):
    if ref:
        print(ref)
PY
)
  normalized="$HARNESS_EVIDENCE_DIR/$(basename "${evidence_copy%.json}").host.json"
  python3 - "$evidence_copy" "$normalized" "$log_dir" <<'PY' || return $?
import json, pathlib, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
root = pathlib.Path(sys.argv[3])
data["bounded_log_references"] = ";".join(
    str(root / (ref[1:] if ref.startswith("/") else ref))
    for ref in data.get("bounded_log_references", "").split(";") if ref
)
pathlib.Path(sys.argv[2]).write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY
  chmod 0600 "$normalized"
  printf 'role-evidence=ready role=%s evidence=%s normalized=%s\n' \
    "$role" "$evidence_copy" "$normalized"
}

vm_write_role_evidence() {
  local checkpoint role status log_ref message file machine manifest checksum
  checkpoint="${1:?checkpoint required}"
  role="${2:?role required}"
  status="${3:?status required}"
  log_ref="${4:?bounded log required}"
  message="${5:-}"
  machine="$(vm_ssh_role_machine "$role")"
  manifest="$(vm_artifacts_target_payload "$role")/manifest.txt"
  checksum="$(vm_artifacts_target_payload "$role")/checksums.sha256"
  mkdir -p "$HARNESS_EVIDENCE_DIR"
  file="$(evidence_record_path "$HARNESS_EVIDENCE_DIR" "$checkpoint" "$role")"
  cat >"$file" <<EOF
{
  "verification_mode": "vm-simulation",
  "timestamp": $(json_quote "$(iso_timestamp_utc)"),
  "package_version": "gerrit-jenkins-setup",
  "helper_command_version": "simulation/vm/simulate.sh",
  "role_or_environment": $(json_quote "$role"),
  "checkpoint": $(json_quote "$checkpoint"),
  "command": $(json_quote "$checkpoint"),
  "status": $(json_quote "$status"),
  "run_id": $(json_quote "$HARNESS_RUN_ID"),
  "set_id": $(json_quote "$HARNESS_SET_ID"),
  "target_vm": $(json_quote "$machine"),
  "effective_input": $(json_quote "$(vm_path_guest_role_env "$role")"),
  "artifact_manifest_references": $(json_quote "$manifest"),
  "checksum_references": $(json_quote "$checksum"),
  "checksum_verification": $(json_quote "$([ "$status" = pass ] && printf pass || printf not-proven)"),
  "source_boundary": $(json_quote "$HARNESS_PUBLIC_INTERNET_FALLBACK_LABEL"),
  "bounded_log": $(json_quote "$log_ref"),
  "message": $(json_quote "$message"),
  "redaction": "secrets-not-recorded"
}
EOF
  chmod 0600 "$file"
  printf '%s\n' "$file"
}

vm_roles_run_helper() {
  local role machine helper env command
  role="${1:?role required}"
  command="${2:?helper command required}"
  machine="$(vm_ssh_role_machine "$role")"
  helper="$(vm_path_guest_role_helper "$role")"
  env="$(vm_path_guest_role_env "$role")"
  case "$role" in
    gerrit|jenkins-controller)
      vm_ssh_run_machine_with_ldap_password "$machine" \
        "set -eu; $(shell_quote "$helper") --env $(shell_quote "$env") --yes $(shell_quote "$command")"
      ;;
    jenkins-agent)
      vm_ssh_run_machine "$machine" \
        "set -eu; $(shell_quote "$helper") --env $(shell_quote "$env") --yes $(shell_quote "$command")"
      ;;
  esac
}

vm_roles_configure() {
  local role machine boot_id
  role="${1:?role required}"
  machine="$(vm_ssh_role_machine "$role")"
  vm_set_verify_run_and_set || return $?
  vm_artifacts_stage_role_env "$machine" "$role" || return $?
  vm_artifacts_verify_staged_role "$role" || return $?
  case "$role" in
    gerrit)
      vm_roles_run_helper "$role" install || return $?
      vm_roles_run_helper "$role" configure || return $?
      ;;
    jenkins-controller)
      vm_roles_run_helper "$role" install || return $?
      vm_roles_run_helper "$role" configure-service || return $?
      vm_roles_run_helper "$role" install-plugins || return $?
      vm_roles_run_helper "$role" configure-jcasc || return $?
      ;;
    jenkins-agent)
      vm_roles_run_helper "$role" install || return $?
      vm_roles_run_helper "$role" configure-runtime || return $?
      ;;
  esac
  boot_id="$(vm_ssh_boot_id "$machine")" || return $?
  vm_state_invalidate_role_validation "$role" || return $?
  vm_state_write_role_checkpoint "$role" configured "$boot_id" || return $?
  printf 'role-configured=ready role=%s machine=%s boot-id=%s\n' "$role" "$machine" "$boot_id"
}

vm_roles_validate() {
  local role machine boot_id marker_boot_id
  role="${1:?role required}"
  machine="$(vm_ssh_role_machine "$role")"
  vm_set_verify_run_and_set || return $?
  vm_state_verify_role_checkpoint "$role" configured || return $?
  vm_artifacts_stage_role_env "$machine" "$role" || return $?
  vm_artifacts_verify_staged_role "$role" || return $?
  vm_roles_run_helper "$role" validate || return $?
  vm_roles_run_helper "$role" collect-evidence || return $?
  vm_roles_copy_evidence "$role" || return $?
  boot_id="$(vm_ssh_boot_id "$machine")" || return $?
  marker_boot_id="$(marker_value "$(vm_path_role_checkpoint_marker "$role" configured)" boot_id)" || return $?
  [ -n "$marker_boot_id" ] || die "Configured checkpoint has no boot ID for $role"
  vm_state_write_role_checkpoint "$role" validated "$boot_id" || return $?
  printf 'role-validated=ready role=%s machine=%s boot-id=%s\n' "$role" "$machine" "$boot_id"
}

vm_roles_assert_reboot_recovery() {
  local role machine env script
  role="${1:?role required}"
  machine="$(vm_ssh_role_machine "$role")"
  env="$(vm_path_guest_role_env "$role")"
  case "$role" in
    gerrit)
      script=$(cat <<EOF
set -eu
. $(shell_quote "$env")
sudo -n systemctl is-enabled --quiet gerrit.service
sudo -n systemctl is-active --quiet gerrit.service
pid="\$(sudo -n systemctl show gerrit.service --property=MainPID --value)"
test -n "\$pid" && test "\$pid" != 0
owner="\$(ps -o user= -p "\$pid" | awk '{print \$1}')"
test "\$owner" = "\$GERRIT_RUNTIME_ACCOUNT"
timeout 5 bash -c 'exec 3<>"/dev/tcp/\$1/\$2"' _ "\$GERRIT_HOST" "\$GERRIT_HTTP_PORT"
printf 'reboot-service=ready role=gerrit unit=gerrit.service pid=%s\n' "\$pid"
EOF
)
      ;;
    jenkins-controller)
      script=$(cat <<EOF
set -eu
. $(shell_quote "$env")
sudo -n systemctl is-enabled --quiet jenkins.service
sudo -n systemctl is-active --quiet jenkins.service
pid="\$(sudo -n systemctl show jenkins.service --property=MainPID --value)"
test -n "\$pid" && test "\$pid" != 0
owner="\$(ps -o user= -p "\$pid" | awk '{print \$1}')"
test "\$owner" = "\$JENKINS_RUNTIME_ACCOUNT"
timeout 5 bash -c 'exec 3<>"/dev/tcp/\$1/\$2"' _ "\$JENKINS_HOST" "\$JENKINS_HTTP_PORT"
printf 'reboot-service=ready role=jenkins-controller unit=jenkins.service pid=%s\n' "\$pid"
EOF
)
      ;;
    jenkins-agent)
      script=$(cat <<'EOF'
set -eu
for unit in ssh.service sshd.service; do
  if sudo -n systemctl is-enabled --quiet "$unit" 2>/dev/null; then
    sudo -n systemctl is-active --quiet "$unit"
    pid="$(sudo -n systemctl show "$unit" --property=MainPID --value)"
    test -n "$pid" && test "$pid" != 0
    printf 'reboot-service=ready role=jenkins-agent unit=%s pid=%s\n' "$unit" "$pid"
    exit 0
  fi
done
exit 1
EOF
)
      ;;
    *) die "Unknown role for reboot recovery: $role" ;;
  esac
  vm_ssh_run_machine "$machine" "$script"
}
