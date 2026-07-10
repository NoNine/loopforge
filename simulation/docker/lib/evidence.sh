#!/usr/bin/env bash

target_container_for_evidence() {
  local role
  role="${1:?role required}"
  case "$role" in
    gerrit|jenkins-controller|jenkins-agent)
      printf '%s-%s\n' "$HARNESS_PROJECT_NAME" "$(service_for_role "$role")"
      ;;
    *)
      printf '%s\n' "not-applicable"
      ;;
  esac
}

manifest_reference_for_evidence() {
  local checkpoint role
  checkpoint="${1:?checkpoint required}"
  role="${2:?role required}"
  case "$role" in
    gerrit|jenkins-controller|jenkins-agent)
      case "$checkpoint" in
        prepare-artifacts)
          printf '%s/manifest.txt\n' "$(container_bundle_factory_work_dir_for_role "$role")"
          ;;
        stage-artifacts|configure-role|validate-role)
          printf '%s/manifest.txt\n' "$(target_payload_dir_for_role "$role")"
          ;;
        *)
          printf '%s/manifest.txt\n' "$(target_payload_dir_for_role "$role")"
          ;;
      esac
      ;;
    *)
      printf '%s\n' "not-applicable"
      ;;
  esac
}

checksum_reference_for_evidence() {
  local checkpoint role
  checkpoint="${1:?checkpoint required}"
  role="${2:?role required}"
  case "$role" in
    gerrit|jenkins-controller|jenkins-agent)
      case "$checkpoint" in
        prepare-artifacts)
          printf '%s;%s\n' \
            "$(container_prepared_artifact_checksum_for_role "$role")" \
            "$(container_bundle_factory_work_dir_for_role "$role")/checksums.sha256"
          ;;
        stage-artifacts)
          printf '%s;%s/checksums.sha256\n' \
            "$(exported_artifact_checksum_for_role "$role")" \
            "$(target_payload_dir_for_role "$role")"
          ;;
        configure-role|validate-role)
          printf '%s/checksums.sha256\n' "$(target_payload_dir_for_role "$role")"
          ;;
        *)
          printf '%s/checksums.sha256\n' "$(target_payload_dir_for_role "$role")"
          ;;
      esac
      ;;
    *)
      printf '%s\n' "not-applicable"
      ;;
  esac
}
validate_role_baseline_manifest_in_target() {
  local role service manifest log gerrit_version jenkins_version plugin_manager_version bundle script
  role="${1:?role required}"
  service="${2:?service required}"
  log="${3:?log required}"
  manifest="$(target_payload_dir_for_role "$role")/manifest.txt"
  bundle="$(bundle_name_for_role "$role")"
  case "$role" in
    gerrit)
      gerrit_version="$HARNESS_GERRIT_BASELINE"
      jenkins_version="not-applicable"
      plugin_manager_version="not-applicable"
      ;;
    jenkins-controller)
      gerrit_version="not-applicable"
      jenkins_version="$HARNESS_JENKINS_BASELINE"
      plugin_manager_version="$HARNESS_JENKINS_PLUGIN_MANAGER_BASELINE"
      ;;
    jenkins-agent)
      gerrit_version="not-applicable"
      jenkins_version="not-applicable"
      plugin_manager_version="not-applicable"
      ;;
    *)
      die "Unknown role for target manifest validation: $role"
      ;;
  esac
  script='
manifest="$1"
role="$2"
bundle_name="$3"
ubuntu_release="$4"
ubuntu_codename="$5"
java_version="$6"
gerrit_version="$7"
jenkins_version="$8"
plugin_manager_version="$9"
test -f "$manifest" || {
  printf "baseline_drift role=%s field=manifest expected=present actual=missing manifest=%s\n" "$role" "$manifest"
  exit 1
}
expect_manifest_value() {
  key="$1"
  expected="$2"
  actual="$(awk -F= -v key="$key" '\''
    $1 == key {
      print substr($0, length(key) + 2)
      found = 1
      exit
    }
    END {
      if (!found) {
        exit 1
      }
    }
  '\'' "$manifest")" || {
    printf "baseline_drift role=%s field=%s expected=%s actual=<missing> manifest=%s\n" "$role" "$key" "$expected" "$manifest"
    exit 1
  }
  [ "$actual" = "$expected" ] || {
    printf "baseline_drift role=%s field=%s expected=%s actual=%s manifest=%s\n" "$role" "$key" "$expected" "$actual" "$manifest"
    exit 1
  }
}
expect_manifest_value harness_manifest_version 1
expect_manifest_value role "$role"
expect_manifest_value bundle_name "$bundle_name"
expect_manifest_value ubuntu_release "$ubuntu_release"
expect_manifest_value ubuntu_codename "$ubuntu_codename"
expect_manifest_value java_version "$java_version"
expect_manifest_value gerrit_version "$gerrit_version"
expect_manifest_value jenkins_version "$jenkins_version"
expect_manifest_value jenkins_plugin_manager_version "$plugin_manager_version"
'
  if ! compose exec -T "$service" sh -c "$script" sh \
    "$manifest" \
    "$role" \
    "$bundle" \
    "$HARNESS_UBUNTU_BASELINE_RELEASE" \
    "$HARNESS_UBUNTU_BASELINE_CODENAME" \
    "$HARNESS_JAVA_BASELINE" \
    "$gerrit_version" \
    "$jenkins_version" \
    "$plugin_manager_version" >>"$log" 2>&1; then
    return 1
  fi
  printf 'baseline_ok role=%s manifest=%s location=target-container\n' "$role" "$manifest" >>"$log"
}
write_evidence() {
  local checkpoint role status command_name log_ref message file
  local manifest_ref checksum_ref target_container
  local q_mode q_timestamp q_role q_checkpoint q_command q_status q_input
  local q_manifest q_checksum q_message q_log_ref q_redaction q_role_name
  local q_bundle_container q_ldap_container q_target_container
  local q_ubuntu_target q_ubuntu_release q_ubuntu_codename q_java q_gerrit
  local q_jenkins q_plugin_manager q_source_boundary
  checkpoint="${1:?checkpoint required}"
  role="${2:?role required}"
  status="${3:?status required}"
  command_name="${4:?command required}"
  log_ref="${5:-not-applicable}"
  message="${6:-}"

  validate_harness_inputs
  if [ "$checkpoint" = "preflight" ] || [ "$checkpoint" = "clean" ]; then
    ensure_preflight_dirs
  else
    ensure_dirs
  fi
  file="$(evidence_record_path "$(evidence_dir_for_record "$checkpoint" "$role")" "$checkpoint" "$role")"
  mkdir -p "$(dirname "$file")"
  manifest_ref="$(manifest_reference_for_evidence "$checkpoint" "$role")"
  checksum_ref="$(checksum_reference_for_evidence "$checkpoint" "$role")"
  target_container="$(target_container_for_evidence "$role")"
  q_mode="$(json_quote "$HARNESS_MODE")"
  q_timestamp="$(json_quote "$(iso_timestamp_utc)")"
  q_role="$(json_quote "$role")"
  q_checkpoint="$(json_quote "$checkpoint")"
  q_command="$(json_quote "$command_name")"
  q_status="$(json_quote "$status")"
  q_input="$(json_quote "not-applicable")"
  q_manifest="$(json_quote "$manifest_ref")"
  q_checksum="$(json_quote "$checksum_ref")"
  q_message="$(json_quote "$message")"
  q_log_ref="$(json_quote "$log_ref")"
  q_redaction="$(json_quote "secrets-not-recorded")"
  q_role_name="$(json_quote "$role")"
  q_bundle_container="$(json_quote "$HARNESS_PROJECT_NAME-bundle-factory")"
  q_ldap_container="$(json_quote "$HARNESS_PROJECT_NAME-ldap")"
  q_target_container="$(json_quote "$target_container")"
  q_ubuntu_target="$(json_quote "$HARNESS_UBUNTU_BASELINE_VERSION")"
  q_ubuntu_release="$(json_quote "$HARNESS_UBUNTU_BASELINE_RELEASE")"
  q_ubuntu_codename="$(json_quote "$HARNESS_UBUNTU_BASELINE_CODENAME")"
  q_java="$(json_quote "$HARNESS_JAVA_BASELINE")"
  q_gerrit="$(json_quote "$HARNESS_GERRIT_BASELINE")"
  q_jenkins="$(json_quote "$HARNESS_JENKINS_BASELINE")"
  q_plugin_manager="$(json_quote "$HARNESS_JENKINS_PLUGIN_MANAGER_BASELINE")"
  q_source_boundary="$(json_quote "Application artifacts are prepared in bundle factory and transferred to targets with a Docker cp simulation-only waiver; target-host public internet fallback is simulation-only for Ubuntu/OS dependencies.")"

  cat >"$file" <<EOF
{
  "verification_mode": $q_mode,
  "timestamp": $q_timestamp,
  "role_or_environment": $q_role,
  "checkpoint_name": $q_checkpoint,
  "command_name": $q_command,
  "status": $q_status,
  "reviewed_input_fingerprint": $q_input,
  "artifact_manifest_references": $q_manifest,
  "checksum_references": $q_checksum,
  "observed_checks": $q_message,
  "bounded_log_references": $q_log_ref,
  "redaction_status": $q_redaction,
  "mode_labels": ["docker-simulation", "simulation-only"],
  "role_name": $q_role_name,
  "container_names": {
    "bundle_factory": $q_bundle_container,
    "ldap": $q_ldap_container,
    "target": $q_target_container
  },
  "version_baseline": {
    "ubuntu_target": $q_ubuntu_target,
    "ubuntu_release": $q_ubuntu_release,
    "ubuntu_codename": $q_ubuntu_codename,
    "java": $q_java,
    "gerrit": $q_gerrit,
    "jenkins_controller": $q_jenkins,
    "jenkins_plugin_manager": $q_plugin_manager
  },
  "source_boundary": $q_source_boundary
}
EOF
  printf '%s\n' "$file"
}
check_target_os_release() {
  local role service log os_release os_codename evidence
  role="${1:?role required}"
  service="$(service_for_role "$role")"
  log="$(bounded_log_path "os-release-$role")"

  if ! compose exec -T "$service" sh -c '. /etc/os-release && printf "%s %s\n" "$VERSION_ID" "$VERSION_CODENAME"' >"$log" 2>&1; then
    evidence="$(write_evidence os-release "$role" fail "simulate.sh validate-role" "$log" "Could not read target OS release")"
    die "Failed to read OS release for $role; evidence=$evidence log=$log"
  fi

  os_release="$(awk '{print $1}' "$log")"
  os_codename="$(awk '{print $2}' "$log")"
  if [ "$os_release" != "$HARNESS_UBUNTU_BASELINE_RELEASE" ] || [ "$os_codename" != "$HARNESS_UBUNTU_BASELINE_CODENAME" ]; then
    evidence="$(write_evidence os-release "$role" blocked "simulate.sh validate-role" "$log" "Target OS $os_release $os_codename does not match Version Baseline")"
    die "Target OS drift for $role; expected $HARNESS_UBUNTU_BASELINE_RELEASE $HARNESS_UBUNTU_BASELINE_CODENAME, evidence=$evidence log=$log"
  fi

  write_evidence os-release "$role" pass "simulate.sh validate-role" "$log" "Target OS release matches Version Baseline" >/dev/null
}

check_ubuntu_service_baseline() {
  local service label log os_release os_codename image_id evidence
  service="${1:?service required}"
  label="${2:?label required}"
  log="$(bounded_log_path "baseline-$label")"

  require_running_service "$service"
  if ! compose exec -T "$service" sh -c '. /etc/os-release && printf "release=%s codename=%s pretty=%s\n" "$VERSION_ID" "$VERSION_CODENAME" "$PRETTY_NAME"' >"$log" 2>&1; then
    evidence="$(write_evidence baseline "$label" fail "simulate.sh up" "$log" "Could not read container OS release")"
    die "Failed to read OS release for $label; evidence=$evidence log=$log"
  fi

  os_release="$(sed -n 's/^release=\([^ ]*\).*/\1/p' "$log")"
  os_codename="$(sed -n 's/^.*codename=\([^ ]*\).*/\1/p' "$log")"
  image_id="$(docker inspect -f '{{.Image}}' "$(container_id_for_service "$service")" 2>/dev/null || printf 'unknown')"
  printf 'image_id=%s\n' "$image_id" >>"$log"

  if [ "$os_release" != "$HARNESS_UBUNTU_BASELINE_RELEASE" ] || [ "$os_codename" != "$HARNESS_UBUNTU_BASELINE_CODENAME" ]; then
    evidence="$(write_evidence baseline "$label" blocked "simulate.sh up" "$log" "Container OS does not match Version Baseline")"
    die "Container OS drift for $label; expected $HARNESS_UBUNTU_BASELINE_RELEASE $HARNESS_UBUNTU_BASELINE_CODENAME, evidence=$evidence log=$log"
  fi

  write_evidence baseline "$label" pass "simulate.sh up" "$log" "Container OS release matches Version Baseline; resolved image id recorded" >/dev/null
}

require_baseline_label() {
  [ "$HARNESS_PUBLIC_INTERNET_FALLBACK_LABEL" = "simulation-only" ] ||
    die "Public internet fallback label must be simulation-only"
  [ "$HARNESS_UBUNTU_BASELINE_RELEASE" = "24.04" ] ||
    die "Ubuntu baseline release drifted from 24.04"
  [ "$HARNESS_UBUNTU_BASELINE_CODENAME" = "noble" ] ||
    die "Ubuntu baseline codename drifted from noble"
  [ "$HARNESS_JAVA_BASELINE" = "21" ] ||
    die "Java baseline drifted from OpenJDK 21"
  [ "$HARNESS_GERRIT_BASELINE" = "3.13.6" ] ||
    die "Gerrit baseline drifted from 3.13.6"
  [ "$HARNESS_JENKINS_BASELINE" = "2.555.3" ] ||
    die "Jenkins baseline drifted from 2.555.3"
  [ "$HARNESS_JENKINS_PLUGIN_MANAGER_BASELINE" = "2.15.0" ] ||
    die "Jenkins Plugin Installation Manager baseline drifted from 2.15.0"
}

assert_no_placeholder_success() {
  local log
  log="${1:?log required}"
    if grep -Eiq "dummy success|operation-plan-only|planned-checks-only|placeholder success|would validate|would run|target-local observable" "$log"; then
    return 1
  fi
  if grep -Eiq "proof=modeled|proof_scope=step8-modeled|real_execution=false|modeled_(scheduling|patchset|agent_build|verified)" "$log"; then
    return 1
  fi
  return 0
}

assert_no_forbidden_success_markers() {
  local log
  log="${1:?log required}"
  if grep -Eiq 'dummy success|operation-plan-only|planned-checks-only|synthetic transcript|marker WAR|marker JAR|local responder|would verify|would validate|fake stream-events|fake scheduling|fake Verified' "$log"; then
    return 1
  fi
  if grep -Eiq 'proof[[:space:]]*=[[:space:]]*modeled|proof_scope[[:space:]]*=[[:space:]]*step[0-9]+-modeled|real_execution[[:space:]]*=[[:space:]]*false' "$log"; then
    return 1
  fi
  if grep -Eiq 'modeled[_ -]?(stream-events|trigger|scheduling|agent|agent-build|agent_execution|verified|vote|verified-vote)|simulated[_ -]?(stream-events|trigger|scheduling|agent-build|verified-vote)' "$log"; then
    return 1
  fi
  return 0
}

normalize_role_evidence_logs() {
  local log role pattern state_dir service latest latest_base evidence_copy normalized role_log_copy
  log="${1:?log required}"
  role="${2:?role required}"
  pattern="${3:?pattern required}"
  state_dir="${4:?state dir required}"
  service="$(service_for_role "$role")"
  latest="$(compose exec -T -u ci-operator "$service" sh -c \
    "find /var/lib/loopforge/evidence -maxdepth 1 -type f -name $(shell_quote "$pattern") -print | sort | tail -1" 2>>"$log" || true)"
  [ -n "$latest" ] || {
    printf 'missing_role_evidence role=%s expected=%s\n' "$role" "$pattern" >>"$log"
    return 1
  }

  require_command python3
  latest_base="$(basename "$latest")"
  evidence_copy="$(role_evidence_dir "$role")/$latest_base"
  normalized="$HARNESS_EVIDENCE_DIR/$(basename "${latest_base%.json}").host.json"
  docker_cp_file_from_service "$service" "$latest" "$evidence_copy" "$log" || return 1
  while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    case "$ref" in
      /*)
        role_log_copy="$(role_log_dir "$role")/${ref#/}"
        docker_cp_file_from_service "$service" "$ref" "$role_log_copy" "$log" || return 1
        if [ ! -s "$role_log_copy" ]; then
          printf 'bounded_log_reference_empty role=%s reference=%s\n' "$role" "$ref" >>"$log"
          return 1
        fi
        ;;
      *)
        printf 'unsupported_relative_bounded_log_reference role=%s reference=%s\n' "$role" "$ref" >>"$log"
        return 1
        ;;
    esac
  done <<EOF
$(python3 - "$evidence_copy" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    data = json.load(handle)

for ref in data.get("bounded_log_references", "").split(";"):
    if ref:
        print(ref)
PY
)
EOF

  python3 - "$evidence_copy" "$normalized" "$(role_log_dir "$role")" <<'PY' >>"$log" 2>&1
import json
import pathlib
import sys

evidence = pathlib.Path(sys.argv[1])
normalized = pathlib.Path(sys.argv[2])
snapshot_root = pathlib.Path(sys.argv[3])
data = json.loads(evidence.read_text())
refs = data.get("bounded_log_references", "")
mapped = []
for ref in refs.split(";"):
    if not ref:
        continue
    if ref.startswith("/"):
        mapped_ref = snapshot_root / ref.removeprefix("/")
        mapped.append(str(mapped_ref))
    else:
        mapped.append(ref)

data["bounded_log_references"] = ";".join(mapped)
normalized.write_text(json.dumps(data, indent=2) + "\n")
print("normalized_role_evidence=" + str(normalized))
print("normalized_bounded_log_references=" + data["bounded_log_references"])
PY
}

normalize_gerrit_role_evidence_logs() {
  local log
  log="${1:?log required}"
  normalize_role_evidence_logs \
    "$log" \
    gerrit \
    'gerrit-readiness-*.json' \
    "$HARNESS_STATE_DIR/gerrit"
}

normalize_jenkins_controller_role_evidence_logs() {
  local log
  log="${1:?log required}"
  normalize_role_evidence_logs \
    "$log" \
    jenkins-controller \
    'jenkins-controller-readiness-*.json' \
    "$HARNESS_STATE_DIR/jenkins-controller"
}

normalize_jenkins_agent_role_evidence_logs() {
  local log
  log="${1:?log required}"
  normalize_role_evidence_logs \
    "$log" \
    jenkins-agent \
    'jenkins-agent-readiness-*.json' \
    "$HARNESS_STATE_DIR/jenkins-agent"
}
