#!/usr/bin/env bash

bundle_name_for_role() {
  local role
  role="${1:?role required}"
  case "$role" in
    gerrit) printf '%s\n' "gerrit-artifacts-bundle" ;;
    jenkins-controller) printf '%s\n' "jenkins-artifacts-bundle" ;;
    jenkins-agent) printf '%s\n' "jenkins-agent-artifacts-bundle" ;;
    *) die "Unknown role for artifact bundle: $role" ;;
  esac
}

bundle_payload_dir_for_role() {
  local role
  role="${1:?role required}"
  case "$role" in
    gerrit) printf '%s\n' "gerrit" ;;
    jenkins-controller) printf '%s\n' "jenkins" ;;
    jenkins-agent) printf '%s\n' "jenkins-agent" ;;
    *) die "Unknown role for artifact payload: $role" ;;
  esac
}

container_bundle_factory_work_dir_for_role() {
  local role bundle payload
  role="${1:?role required}"
  bundle="$(bundle_name_for_role "$role")"
  payload="$(bundle_payload_dir_for_role "$role")"
  printf '/var/lib/loopforge/preparing/%s/%s\n' "$bundle" "$payload"
}

container_bundle_factory_root_for_role() {
  local role bundle
  role="${1:?role required}"
  bundle="$(bundle_name_for_role "$role")"
  printf '/var/lib/loopforge/preparing/%s\n' "$bundle"
}

container_prepared_artifact_archive_for_role() {
  local role bundle
  role="${1:?role required}"
  bundle="$(bundle_name_for_role "$role")"
  printf '/var/lib/loopforge/preparing/%s.tar.gz\n' "$bundle"
}

container_prepared_artifact_checksum_for_role() {
  local role
  role="${1:?role required}"
  printf '%s.sha256\n' "$(container_prepared_artifact_archive_for_role "$role")"
}

exported_artifact_archive_for_role() {
  local role bundle
  role="${1:?role required}"
  bundle="$(bundle_name_for_role "$role")"
  printf '%s/%s.tar.gz\n' "$HARNESS_EXPORTED_ARTIFACT_DIR" "$bundle"
}

exported_artifact_checksum_for_role() {
  local role
  role="${1:?role required}"
  printf '%s.sha256\n' "$(exported_artifact_archive_for_role "$role")"
}

stage_bundle_dir_for_role() {
  local role bundle
  role="${1:?role required}"
  bundle="$(bundle_name_for_role "$role")"
  printf '%s/%s/%s\n' "$HARNESS_STAGING_DIR" "$role" "$bundle"
}

stage_payload_dir_for_role() {
  local role payload
  role="${1:?role required}"
  payload="$(bundle_payload_dir_for_role "$role")"
  printf '%s/%s\n' "$(stage_bundle_dir_for_role "$role")" "$payload"
}

target_bundle_dir_for_role() {
  local role
  role="${1:?role required}"
  printf '%s\n' "$(target_payload_dir_for_role "$role")"
}

target_payload_dir_for_role() {
  local role payload
  role="${1:?role required}"
  payload="$(bundle_payload_dir_for_role "$role")"
  printf '/var/lib/loopforge/staging/%s\n' "$payload"
}

manifest_get() {
  local key manifest
  key="${1:?key required}"
  manifest="${2:?manifest required}"
  awk -F= -v key="$key" '
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
  ' "$manifest"
}

env_file_value() {
  local file key
  file="${1:?file required}"
  key="${2:?key required}"
  awk -F= -v key="$key" '
    $1 == key {
      value = substr($0, length(key) + 2)
      gsub(/^"/, "", value)
      gsub(/"$/, "", value)
      print value
      found = 1
      exit
    }
    END {
      if (!found) {
        exit 1
      }
    }
  ' "$file"
}

validate_manifest_value() {
  local role manifest log key expected actual
  role="${1:?role required}"
  manifest="${2:?manifest required}"
  log="${3:?log required}"
  key="${4:?key required}"
  expected="${5:?expected required}"

  if ! actual="$(manifest_get "$key" "$manifest")"; then
    printf 'baseline_drift role=%s field=%s expected=%s actual=<missing> manifest=%s\n' \
      "$role" "$key" "$expected" "$manifest" >>"$log"
    return 1
  fi

  if [ "$actual" != "$expected" ]; then
    printf 'baseline_drift role=%s field=%s expected=%s actual=%s manifest=%s\n' \
      "$role" "$key" "$expected" "$actual" "$manifest" >>"$log"
    return 1
  fi
}

verify_checksum_file_in_dir() {
  local checksum dir log
  checksum="${1:?checksum file required}"
  dir="${2:-$(dirname "$checksum")}"
  log="${3:-/dev/null}"
  (cd "$dir" && sha256sum -c "$(basename "$checksum")") >>"$log" 2>&1
}
