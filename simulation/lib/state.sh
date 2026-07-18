#!/usr/bin/env bash

sha256_file() {
  sha256sum "$1" | awk '{print $1}'
}

sha256_fingerprint_is_valid() {
  local value
  value="${1-}"
  [ "${#value}" -eq 64 ] || return 1
  case "$value" in
    *[!0-9a-f]*) return 1 ;;
  esac
}

runtime_env_fingerprint() {
  local runtime_env
  runtime_env="${1:-${HARNESS_RUNTIME_ENV:-}}"
  [ -n "$runtime_env" ] || die "runtime env path required"
  sha256_file "$runtime_env"
}

marker_value() {
  local file key
  file="${1:?file required}"
  key="${2:?key required}"
  awk -F= -v key="$key" '$1 == key { print substr($0, length(key) + 2); found = 1; exit } END { exit !found }' "$file"
}

strict_record_keys() {
  local file line expected value index
  local -a expected_keys
  file="${1:?record file required}"
  shift
  expected_keys=("$@")
  [ -f "$file" ] && [ -r "$file" ] || return 1
  index=0
  while IFS= read -r line || [ -n "$line" ]; do
    [ "$index" -lt "${#expected_keys[@]}" ] || return 1
    expected="${expected_keys[$index]}"
    case "$line" in
      "$expected="*) value="${line#*=}" ;;
      *) return 1 ;;
    esac
    [ -n "$value" ] || return 1
    case "$value" in *$'\r'*) return 1 ;; esac
    index=$((index + 1))
  done <"$file"
  [ "$index" -eq "${#expected_keys[@]}" ]
}

strict_record_value() {
  local file key
  file="${1:?record file required}"
  key="${2:?record key required}"
  awk -F= -v key="$key" '$1 == key { print substr($0, length(key) + 2); found = 1 } END { exit !found }' "$file"
}

atomic_write_record() {
  local file mode tmp line
  file="${1:?record file required}"
  mode="${2:?record mode required}"
  shift 2
  mkdir -p "$(dirname "$file")"
  tmp="$(mktemp "${file}.XXXXXX")"
  if ! {
    for line in "$@"; do
      printf '%s\n' "$line"
    done
  } >"$tmp" || ! chmod "$mode" "$tmp" || ! mv -- "$tmp" "$file"; then
    rm -f -- "$tmp"
    return 1
  fi
}

simulation_input_bundle_fingerprint() {
  local input_dir file
  input_dir="${1:?simulation input directory required}"
  for file in harness.env gerrit.env jenkins-controller.env jenkins-agent.env integration.env; do
    [ -f "$input_dir/$file" ] || die "Missing simulation input: $input_dir/$file"
  done
  (
    cd "$input_dir" || exit
    for file in harness.env gerrit.env jenkins-controller.env jenkins-agent.env integration.env; do
      printf '%s=%s\n' "$file" "$(sha256_file "$file")"
    done
  ) | sha256sum | awk '{print $1}'
}

write_runtime_marker() {
  local marker mode backend set_id run_id namespace repo_root generated_run_dir
  local runtime_env source_dir runtime_fingerprint source_fingerprint
  marker="${1:?marker required}"
  mode="${2:?mode required}"
  backend="${3:?backend required}"
  set_id="${4:?set ID required}"
  run_id="${5:?run ID required}"
  namespace="${6:?resource namespace required}"
  repo_root="${7:?repo root required}"
  generated_run_dir="${8:?generated run dir required}"
  runtime_env="${9:?runtime env required}"
  source_dir="${10:?source input directory required}"
  runtime_fingerprint="$(runtime_env_fingerprint "$runtime_env")"
  source_fingerprint="$(simulation_input_bundle_fingerprint "$source_dir")"
  atomic_write_record "$marker" "${LF_MODE_PUBLIC_FILE:-0644}" \
    "schema_version=1" \
    "mode=$mode" \
    "backend=$backend" \
    "set_id=$set_id" \
    "run_id=$run_id" \
    "resource_namespace=$namespace" \
    "repo_root=$repo_root" \
    "generated_run_dir=$generated_run_dir" \
    "runtime_env_fingerprint=$runtime_fingerprint" \
    "source_inputs_fingerprint=$source_fingerprint"
}

verify_runtime_marker() {
  local marker mode backend set_id run_id namespace repo_root generated_run_dir
  local runtime_env source_dir label runtime_fingerprint source_fingerprint
  marker="${1:?marker required}"
  mode="${2:?mode required}"
  backend="${3:?backend required}"
  set_id="${4:?set ID required}"
  run_id="${5:?run ID required}"
  namespace="${6:?resource namespace required}"
  repo_root="${7:?repo root required}"
  generated_run_dir="${8:?generated run dir required}"
  runtime_env="${9:?runtime env required}"
  source_dir="${10:?source input directory required}"
  label="${11:-Run marker}"

  [ -f "$marker" ] || die "Missing $label: $marker"
  strict_record_keys "$marker" schema_version mode backend set_id run_id \
    resource_namespace repo_root generated_run_dir runtime_env_fingerprint \
    source_inputs_fingerprint || die "$label has malformed or unexpected fields"
  [ "$(strict_record_value "$marker" schema_version)" = 1 ] ||
    die "$label schema version is unsupported"
  [ "$(strict_record_value "$marker" mode)" = "$mode" ] ||
    die "$label mode does not match selected runtime config"
  [ "$(strict_record_value "$marker" backend)" = "$backend" ] ||
    die "$label backend does not match selected runtime config"
  [ "$(strict_record_value "$marker" set_id)" = "$set_id" ] ||
    die "$label set ID does not match selected runtime config"
  [ "$(strict_record_value "$marker" run_id)" = "$run_id" ] ||
    die "$label run ID does not match selected runtime config"
  [ "$(strict_record_value "$marker" resource_namespace)" = "$namespace" ] ||
    die "$label resource namespace does not match selected runtime config"
  [ "$(strict_record_value "$marker" repo_root)" = "$repo_root" ] ||
    die "$label repo root does not match this checkout"
  [ "$(strict_record_value "$marker" generated_run_dir)" = "$generated_run_dir" ] ||
    die "$label generated run dir does not match selected runtime config"
  runtime_fingerprint="$(runtime_env_fingerprint "$runtime_env")"
  [ "$(strict_record_value "$marker" runtime_env_fingerprint)" = "$runtime_fingerprint" ] ||
    die "$label runtime env fingerprint does not match selected runtime config"
  source_fingerprint="$(simulation_input_bundle_fingerprint "$source_dir")"
  [ "$(strict_record_value "$marker" source_inputs_fingerprint)" = "$source_fingerprint" ] ||
    die "$label source input fingerprint does not match source inputs"
}

write_effective_inputs_record() {
  local file backend set_id run_id marker source_fingerprint effective_dir
  file="${1:?effective-input record required}"
  backend="${2:?backend required}"
  set_id="${3:?set ID required}"
  run_id="${4:?run ID required}"
  marker="${5:?run marker required}"
  source_fingerprint="${6:?source input fingerprint required}"
  effective_dir="${7:?effective input directory required}"
  atomic_write_record "$file" "${LF_MODE_REVIEW_FILE:-0640}" \
    "schema_version=1" \
    "backend=$backend" \
    "set_id=$set_id" \
    "run_id=$run_id" \
    "run_marker_sha256=$(sha256_file "$marker")" \
    "source_inputs_fingerprint=$source_fingerprint" \
    "effective_inputs_fingerprint=$(simulation_input_bundle_fingerprint "$effective_dir")"
}

effective_inputs_record_is_strict() {
  strict_record_keys "${1:?effective-input record required}" schema_version \
    backend set_id run_id run_marker_sha256 source_inputs_fingerprint \
    effective_inputs_fingerprint
}

effective_inputs_record_is_bound() {
  local file backend set_id run_id marker source_dir effective_dir
  file="${1:?effective-input record required}"
  backend="${2:?backend required}"
  set_id="${3:?set ID required}"
  run_id="${4:?run ID required}"
  marker="${5:?run marker required}"
  source_dir="${6:?source input directory required}"
  effective_dir="${7:?effective input directory required}"
  effective_inputs_record_is_strict "$file" || return 1
  [ "$(strict_record_value "$file" schema_version)" = 1 ] || return 1
  [ "$(strict_record_value "$file" backend)" = "$backend" ] || return 1
  [ "$(strict_record_value "$file" set_id)" = "$set_id" ] || return 1
  [ "$(strict_record_value "$file" run_id)" = "$run_id" ] || return 1
  [ "$(strict_record_value "$file" run_marker_sha256)" = "$(sha256_file "$marker")" ] || return 1
  sha256_fingerprint_is_valid "$(strict_record_value "$file" source_inputs_fingerprint)" || return 1
  sha256_fingerprint_is_valid "$(strict_record_value "$file" effective_inputs_fingerprint)" || return 1
  [ "$(strict_record_value "$file" source_inputs_fingerprint)" = \
    "$(simulation_input_bundle_fingerprint "$source_dir")" ] || return 1
  [ "$(strict_record_value "$file" effective_inputs_fingerprint)" = \
    "$(simulation_input_bundle_fingerprint "$effective_dir")" ]
}

write_checkpoint_marker() {
  local marker mode backend set_id run_id namespace runtime_env source_dir
  local effective_dir runtime_fingerprint source_fingerprint effective_fingerprint
  marker="${1:?marker required}"
  mode="${2:?mode required}"
  backend="${3:?backend required}"
  set_id="${4:?set ID required}"
  run_id="${5:?run ID required}"
  namespace="${6:?resource namespace required}"
  runtime_env="${7:?runtime env required}"
  source_dir="${8:?source input directory required}"
  effective_dir="${9:?effective input directory required}"
  runtime_fingerprint="$(runtime_env_fingerprint "$runtime_env")"
  source_fingerprint="$(simulation_input_bundle_fingerprint "$source_dir")"
  effective_fingerprint="$(simulation_input_bundle_fingerprint "$effective_dir")"
  atomic_write_record "$marker" "${LF_MODE_PUBLIC_FILE:-0644}" \
    "schema_version=1" \
    "mode=$mode" \
    "backend=$backend" \
    "set_id=$set_id" \
    "run_id=$run_id" \
    "resource_namespace=$namespace" \
    "runtime_env_fingerprint=$runtime_fingerprint" \
    "source_inputs_fingerprint=$source_fingerprint" \
    "effective_inputs_fingerprint=$effective_fingerprint"
}

verify_checkpoint_marker() {
  local marker mode backend set_id run_id namespace runtime_env source_dir
  local effective_dir label runtime_fingerprint source_fingerprint
  local effective_fingerprint
  marker="${1:?marker required}"
  mode="${2:?mode required}"
  backend="${3:?backend required}"
  set_id="${4:?set ID required}"
  run_id="${5:?run ID required}"
  namespace="${6:?resource namespace required}"
  runtime_env="${7:?runtime env required}"
  source_dir="${8:?source input directory required}"
  effective_dir="${9:?effective input directory required}"
  label="${10:-Checkpoint marker}"

  [ -f "$marker" ] || die "Missing $label: $marker"
  strict_record_keys "$marker" schema_version mode backend set_id run_id \
    resource_namespace runtime_env_fingerprint source_inputs_fingerprint \
    effective_inputs_fingerprint ||
    die "$label has malformed or unexpected fields"
  [ "$(strict_record_value "$marker" schema_version)" = 1 ] ||
    die "$label schema version is unsupported"
  [ "$(strict_record_value "$marker" mode)" = "$mode" ] ||
    die "$label mode does not match selected runtime config"
  [ "$(strict_record_value "$marker" backend)" = "$backend" ] ||
    die "$label backend does not match selected runtime config"
  [ "$(strict_record_value "$marker" set_id)" = "$set_id" ] ||
    die "$label set ID does not match selected runtime config"
  [ "$(strict_record_value "$marker" run_id)" = "$run_id" ] ||
    die "$label run ID does not match selected runtime config"
  [ "$(strict_record_value "$marker" resource_namespace)" = "$namespace" ] ||
    die "$label resource namespace does not match selected runtime config"
  runtime_fingerprint="$(runtime_env_fingerprint "$runtime_env")"
  [ "$(strict_record_value "$marker" runtime_env_fingerprint)" = "$runtime_fingerprint" ] ||
    die "$label runtime env fingerprint does not match selected runtime config"
  source_fingerprint="$(simulation_input_bundle_fingerprint "$source_dir")"
  [ "$(strict_record_value "$marker" source_inputs_fingerprint)" = "$source_fingerprint" ] ||
    die "$label source input fingerprint does not match source inputs"
  effective_fingerprint="$(simulation_input_bundle_fingerprint "$effective_dir")"
  [ "$(strict_record_value "$marker" effective_inputs_fingerprint)" = "$effective_fingerprint" ] ||
    die "$label effective input fingerprint does not match effective inputs"
}

write_active_run_record() {
  local file backend set_id run_id namespace marker baseline state restore
  file="${1:?active-run file required}"
  backend="${2:?backend required}"
  set_id="${3:?set ID required}"
  run_id="${4:?run ID required}"
  namespace="${5:?resource namespace required}"
  marker="${6:?run marker required}"
  baseline="${7:?baseline fingerprint required}"
  state="${8:?active-run state required}"
  restore="${9:?restore evidence fingerprint required}"
  atomic_write_record "$file" "${LF_MODE_PUBLIC_FILE:-0644}" \
    "schema_version=1" \
    "backend=$backend" \
    "set_id=$set_id" \
    "run_id=$run_id" \
    "resource_namespace=$namespace" \
    "run_marker_sha256=$(sha256_file "$marker")" \
    "baseline_fingerprint=$baseline" \
    "state=$state" \
    "restore_evidence_sha256=$restore"
}

active_run_record_is_strict() {
  strict_record_keys "${1:?active-run file required}" schema_version backend \
    set_id run_id resource_namespace run_marker_sha256 baseline_fingerprint \
    state restore_evidence_sha256
}

write_initial_workflow_state() {
  local file backend set_id run_id marker baseline source_fingerprint
  file="${1:?workflow state file required}"
  backend="${2:?backend required}"
  set_id="${3:?set ID required}"
  run_id="${4:?run ID required}"
  marker="${5:?run marker required}"
  baseline="${6:?baseline fingerprint required}"
  source_fingerprint="${7:?source input fingerprint required}"
  atomic_write_record "$file" "${LF_MODE_REVIEW_FILE:-0640}" \
    "schema_version=1" \
    "backend=$backend" \
    "set_id=$set_id" \
    "run_id=$run_id" \
    "run_marker_sha256=$(sha256_file "$marker")" \
    "baseline_fingerprint=$baseline" \
    "source_inputs_fingerprint=$source_fingerprint" \
    "input_state=pending" \
    "effective_inputs_fingerprint=none" \
    "activity=idle" \
    "active_checkpoint=none" \
    "last_checkpoint=none" \
    "last_record_sha256=none"
}

workflow_state_is_strict() {
  strict_record_keys "${1:?workflow state file required}" schema_version backend \
    set_id run_id run_marker_sha256 baseline_fingerprint \
    source_inputs_fingerprint input_state effective_inputs_fingerprint activity \
    active_checkpoint last_checkpoint last_record_sha256
}

publish_lifecycle_baseline_binding() {
  local active workflow fingerprint marker
  active="${1:?active-run file required}"
  workflow="${2:?workflow state file required}"
  fingerprint="${3:?baseline fingerprint required}"
  marker="${4:?run marker required}"
  active_run_record_is_strict "$active" ||
    die "Active-run state has malformed or unexpected fields"
  workflow_state_is_strict "$workflow" ||
    die "Workflow state has malformed or unexpected fields"
  sha256_fingerprint_is_valid "$fingerprint" ||
    die "Baseline fingerprint is malformed"
  [ "$(strict_record_value "$active" baseline_fingerprint)" = none ] ||
    die "Active run already has a baseline binding"
  [ "$(strict_record_value "$workflow" baseline_fingerprint)" = none ] ||
    die "Workflow already has a baseline binding"
  if [ "$(strict_record_value "$active" state)" != active ] ||
    [ "$(strict_record_value "$active" restore_evidence_sha256)" != none ]; then
    die "Active run is not eligible for baseline publication"
  fi
  if [ "$(strict_record_value "$workflow" activity)" != idle ] ||
    [ "$(strict_record_value "$workflow" active_checkpoint)" != none ] ||
    [ "$(strict_record_value "$workflow" last_checkpoint)" != none ] ||
    [ "$(strict_record_value "$workflow" last_record_sha256)" != none ]; then
    die "Workflow has progressed before baseline publication"
  fi

  atomic_write_record "$workflow" "${LF_MODE_REVIEW_FILE:-0640}" \
    "schema_version=$(strict_record_value "$workflow" schema_version)" \
    "backend=$(strict_record_value "$workflow" backend)" \
    "set_id=$(strict_record_value "$workflow" set_id)" \
    "run_id=$(strict_record_value "$workflow" run_id)" \
    "run_marker_sha256=$(strict_record_value "$workflow" run_marker_sha256)" \
    "baseline_fingerprint=$fingerprint" \
    "source_inputs_fingerprint=$(strict_record_value "$workflow" source_inputs_fingerprint)" \
    "input_state=$(strict_record_value "$workflow" input_state)" \
    "effective_inputs_fingerprint=$(strict_record_value "$workflow" effective_inputs_fingerprint)" \
    "activity=idle" \
    "active_checkpoint=none" \
    "last_checkpoint=none" \
    "last_record_sha256=none" || return $?
  write_active_run_record "$active" \
    "$(strict_record_value "$active" backend)" \
    "$(strict_record_value "$active" set_id)" \
    "$(strict_record_value "$active" run_id)" \
    "$(strict_record_value "$active" resource_namespace)" \
    "$marker" \
    "$fingerprint" active none
}

publish_lifecycle_restore_gate() {
  local active workflow evidence marker fingerprint
  active="${1:?active-run file required}"
  workflow="${2:?workflow state file required}"
  evidence="${3:?restoration evidence required}"
  marker="${4:?run marker required}"
  active_run_record_is_strict "$active" ||
    die "Active-run state has malformed or unexpected fields"
  workflow_state_is_strict "$workflow" ||
    die "Workflow state has malformed or unexpected fields"
  if [ "$(strict_record_value "$active" state)" != active ] ||
    [ "$(strict_record_value "$active" restore_evidence_sha256)" != none ]; then
    die "Active run is not eligible for baseline restoration"
  fi
  fingerprint="$(strict_record_value "$active" baseline_fingerprint)"
  sha256_fingerprint_is_valid "$fingerprint" ||
    die "Active run has no valid baseline binding"
  [ "$fingerprint" = "$(strict_record_value "$workflow" baseline_fingerprint)" ] ||
    die "Active-run and workflow baseline bindings do not agree"
  [ -f "$evidence" ] || die "Restoration evidence is missing: $evidence"
  write_active_run_record "$active" \
    "$(strict_record_value "$active" backend)" \
    "$(strict_record_value "$active" set_id)" \
    "$(strict_record_value "$active" run_id)" \
    "$(strict_record_value "$active" resource_namespace)" \
    "$marker" \
    "$fingerprint" restored-pending-clean "$(sha256_file "$evidence")"
}

lifecycle_records_are_bound() {
  local active marker workflow backend set_id run_id namespace source_fingerprint
  local active_state restore activity active_checkpoint
  active="${1:?active-run file required}"
  marker="${2:?run marker required}"
  workflow="${3:?workflow state file required}"
  backend="${4:?backend required}"
  set_id="${5:?set ID required}"
  run_id="${6:?run ID required}"
  namespace="${7:?resource namespace required}"
  source_fingerprint="${8:?source input fingerprint required}"
  active_run_record_is_strict "$active" || return 1
  workflow_state_is_strict "$workflow" || return 1
  [ "$(strict_record_value "$active" schema_version)" = 1 ] || return 1
  [ "$(strict_record_value "$workflow" schema_version)" = 1 ] || return 1
  [ "$(strict_record_value "$active" backend)" = "$backend" ] || return 1
  [ "$(strict_record_value "$workflow" backend)" = "$backend" ] || return 1
  [ "$(strict_record_value "$active" set_id)" = "$set_id" ] || return 1
  [ "$(strict_record_value "$workflow" set_id)" = "$set_id" ] || return 1
  [ "$(strict_record_value "$active" run_id)" = "$run_id" ] || return 1
  [ "$(strict_record_value "$workflow" run_id)" = "$run_id" ] || return 1
  [ "$(strict_record_value "$active" resource_namespace)" = "$namespace" ] || return 1
  [ "$(strict_record_value "$active" run_marker_sha256)" = "$(sha256_file "$marker")" ] || return 1
  [ "$(strict_record_value "$workflow" run_marker_sha256)" = "$(sha256_file "$marker")" ] || return 1
  [ "$(strict_record_value "$active" baseline_fingerprint)" = "$(strict_record_value "$workflow" baseline_fingerprint)" ] || return 1
  [ "$(strict_record_value "$marker" source_inputs_fingerprint)" = "$source_fingerprint" ] || return 1
  [ "$(strict_record_value "$workflow" source_inputs_fingerprint)" = "$source_fingerprint" ] || return 1
  case "$(strict_record_value "$workflow" input_state)" in
    pending)
      [ "$(strict_record_value "$workflow" effective_inputs_fingerprint)" = none ] || return 1
      ;;
    ready)
      sha256_fingerprint_is_valid \
        "$(strict_record_value "$workflow" effective_inputs_fingerprint)" || return 1
      ;;
    *) return 1 ;;
  esac
  active_state="$(strict_record_value "$active" state)"
  restore="$(strict_record_value "$active" restore_evidence_sha256)"
  case "$active_state:$restore" in active:none|restored-pending-clean:*) ;; *) return 1 ;; esac
  [ "$active_state" != restored-pending-clean ] || [ "$restore" != none ] || return 1
  activity="$(strict_record_value "$workflow" activity)"
  active_checkpoint="$(strict_record_value "$workflow" active_checkpoint)"
  case "$activity:$active_checkpoint" in
    idle:none) return 0 ;;
    observing:*|mutating:*|waiting:*) [ "$active_checkpoint" != none ] ;;
    *) return 1 ;;
  esac
}

workflow_state_publish_effective_inputs() {
  local workflow record
  workflow="${1:?workflow state file required}"
  record="${2:?effective-input record required}"
  workflow_state_is_strict "$workflow" ||
    die "Workflow state has malformed or unexpected fields"
  effective_inputs_record_is_strict "$record" ||
    die "Effective-input record has malformed or unexpected fields"
  [ "$(strict_record_value "$record" schema_version)" = 1 ] ||
    die "Effective-input record schema version is unsupported"
  sha256_fingerprint_is_valid \
    "$(strict_record_value "$record" effective_inputs_fingerprint)" ||
    die "Effective-input record fingerprint is malformed"
  [ "$(strict_record_value "$workflow" input_state)" = pending ] ||
    die "Workflow effective inputs are not pending"
  [ "$(strict_record_value "$workflow" effective_inputs_fingerprint)" = none ] ||
    die "Pending workflow has an effective input fingerprint"
  [ "$(strict_record_value "$workflow" activity)" = idle ] ||
    die "Workflow state is not idle"
  [ "$(strict_record_value "$workflow" active_checkpoint)" = none ] ||
    die "Workflow state has an unexpected active checkpoint"
  [ "$(strict_record_value "$workflow" last_checkpoint)" = none ] ||
    die "Workflow already has checkpoint progress"
  [ "$(strict_record_value "$record" backend)" = "$(strict_record_value "$workflow" backend)" ] ||
    die "Effective-input record backend does not match workflow state"
  [ "$(strict_record_value "$record" set_id)" = "$(strict_record_value "$workflow" set_id)" ] ||
    die "Effective-input record set ID does not match workflow state"
  [ "$(strict_record_value "$record" run_id)" = "$(strict_record_value "$workflow" run_id)" ] ||
    die "Effective-input record run ID does not match workflow state"
  [ "$(strict_record_value "$record" run_marker_sha256)" = "$(strict_record_value "$workflow" run_marker_sha256)" ] ||
    die "Effective-input record run marker does not match workflow state"
  [ "$(strict_record_value "$record" source_inputs_fingerprint)" = "$(strict_record_value "$workflow" source_inputs_fingerprint)" ] ||
    die "Effective-input record source inputs do not match workflow state"
  atomic_write_record "$workflow" "${LF_MODE_REVIEW_FILE:-0640}" \
    "schema_version=$(strict_record_value "$workflow" schema_version)" \
    "backend=$(strict_record_value "$workflow" backend)" \
    "set_id=$(strict_record_value "$workflow" set_id)" \
    "run_id=$(strict_record_value "$workflow" run_id)" \
    "run_marker_sha256=$(strict_record_value "$workflow" run_marker_sha256)" \
    "baseline_fingerprint=$(strict_record_value "$workflow" baseline_fingerprint)" \
    "source_inputs_fingerprint=$(strict_record_value "$workflow" source_inputs_fingerprint)" \
    "input_state=ready" \
    "effective_inputs_fingerprint=$(strict_record_value "$record" effective_inputs_fingerprint)" \
    "activity=idle" \
    "active_checkpoint=none" \
    "last_checkpoint=none" \
    "last_record_sha256=none"
}

simulation_input_state_is_bound() {
  local workflow marker backend set_id run_id source_dir record effective_dir
  local source_fingerprint input_state effective_fingerprint
  workflow="${1:?workflow state file required}"
  marker="${2:?run marker required}"
  backend="${3:?backend required}"
  set_id="${4:?set ID required}"
  run_id="${5:?run ID required}"
  source_dir="${6:?source input directory required}"
  record="${7:?effective-input record required}"
  effective_dir="${8:?effective input directory required}"
  workflow_state_is_strict "$workflow" || return 1
  source_fingerprint="$(simulation_input_bundle_fingerprint "$source_dir")" || return 1
  [ "$(strict_record_value "$marker" source_inputs_fingerprint)" = "$source_fingerprint" ] || return 1
  [ "$(strict_record_value "$workflow" source_inputs_fingerprint)" = "$source_fingerprint" ] || return 1
  input_state="$(strict_record_value "$workflow" input_state)"
  effective_fingerprint="$(strict_record_value "$workflow" effective_inputs_fingerprint)"
  case "$input_state" in
    pending)
      [ "$effective_fingerprint" = none ] || return 1
      [ ! -e "$record" ] && [ ! -e "$effective_dir" ]
      ;;
    ready)
      sha256_fingerprint_is_valid "$effective_fingerprint" || return 1
      effective_inputs_record_is_bound "$record" "$backend" "$set_id" "$run_id" \
        "$marker" "$source_dir" "$effective_dir" || return 1
      [ "$(strict_record_value "$record" effective_inputs_fingerprint)" = "$effective_fingerprint" ]
      ;;
    *) return 1 ;;
  esac
}

require_effective_inputs_ready() {
  local workflow marker backend set_id run_id source_dir record effective_dir
  workflow="${1:?workflow state file required}"
  marker="${2:?run marker required}"
  backend="${3:?backend required}"
  set_id="${4:?set ID required}"
  run_id="${5:?run ID required}"
  source_dir="${6:?source input directory required}"
  record="${7:?effective-input record required}"
  effective_dir="${8:?effective input directory required}"
  simulation_input_state_is_bound "$workflow" "$marker" "$backend" "$set_id" \
    "$run_id" "$source_dir" "$record" "$effective_dir" ||
    die "Simulation effective input state is missing, changed, or partially published"
  [ "$(strict_record_value "$workflow" input_state)" = ready ] ||
    die "Simulation effective inputs are pending; run start first"
}

publish_or_verify_effective_inputs() {
  local workflow marker backend set_id run_id source_dir record effective_dir
  local staged source_fingerprint input_state
  workflow="${1:?workflow state file required}"
  marker="${2:?run marker required}"
  backend="${3:?backend required}"
  set_id="${4:?set ID required}"
  run_id="${5:?run ID required}"
  source_dir="${6:?source input directory required}"
  record="${7:?effective-input record required}"
  effective_dir="${8:?effective input directory required}"
  staged="${9:?staged effective input directory required}"
  simulation_input_state_is_bound "$workflow" "$marker" "$backend" "$set_id" \
    "$run_id" "$source_dir" "$record" "$effective_dir" ||
    die "Simulation effective input state is changed or partially published"
  input_state="$(strict_record_value "$workflow" input_state)"
  case "$input_state" in
    pending)
      source_fingerprint="$(simulation_input_bundle_fingerprint "$source_dir")"
      publish_simulation_input_bundle "$staged" "$effective_dir" || return $?
      [ "${HARNESS_TEST_EFFECTIVE_PUBLICATION_FAIL_AFTER:-}" != directory ] ||
        die "Injected effective input publication failure after directory"
      write_effective_inputs_record "$record" "$backend" "$set_id" "$run_id" \
        "$marker" "$source_fingerprint" "$effective_dir" || return $?
      [ "${HARNESS_TEST_EFFECTIVE_PUBLICATION_FAIL_AFTER:-}" != record ] ||
        die "Injected effective input publication failure after record"
      workflow_state_publish_effective_inputs "$workflow" "$record"
      ;;
    ready)
      simulation_input_bundles_are_identical "$effective_dir" "$staged" ||
        die "Rendered effective inputs changed after first publication"
      rm -rf -- "$staged"
      ;;
    *) die "Unsupported workflow input state: $input_state" ;;
  esac
  require_effective_inputs_ready "$workflow" "$marker" "$backend" "$set_id" \
    "$run_id" "$source_dir" "$record" "$effective_dir"
}

workflow_state_publish_activity() {
  local file activity checkpoint
  file="${1:?workflow state file required}"
  activity="${2:?workflow activity required}"
  checkpoint="${3:?checkpoint required}"
  workflow_state_is_strict "$file" || die "Workflow state has malformed or unexpected fields"
  [ "$(strict_record_value "$file" input_state)" = ready ] ||
    die "Workflow effective inputs are not ready"
  [ "$(strict_record_value "$file" activity)" = idle ] ||
    die "Workflow state is not idle"
  [ "$(strict_record_value "$file" active_checkpoint)" = none ] ||
    die "Workflow state has an unexpected active checkpoint"
  simulation_checkpoint_name_is_known "$checkpoint" ||
    die "Unknown simulation checkpoint: $checkpoint"
  case "$activity" in
    observing|mutating) ;;
    *) die "Unsupported workflow activity: $activity" ;;
  esac
  atomic_write_record "$file" "${LF_MODE_REVIEW_FILE:-0640}" \
    "schema_version=$(strict_record_value "$file" schema_version)" \
    "backend=$(strict_record_value "$file" backend)" \
    "set_id=$(strict_record_value "$file" set_id)" \
    "run_id=$(strict_record_value "$file" run_id)" \
    "run_marker_sha256=$(strict_record_value "$file" run_marker_sha256)" \
    "baseline_fingerprint=$(strict_record_value "$file" baseline_fingerprint)" \
    "source_inputs_fingerprint=$(strict_record_value "$file" source_inputs_fingerprint)" \
    "input_state=ready" \
    "effective_inputs_fingerprint=$(strict_record_value "$file" effective_inputs_fingerprint)" \
    "activity=$activity" \
    "active_checkpoint=$checkpoint" \
    "last_checkpoint=$(strict_record_value "$file" last_checkpoint)" \
    "last_record_sha256=$(strict_record_value "$file" last_record_sha256)"
}

write_immutable_checkpoint_record() {
  local file backend set_id run_id baseline source_inputs effective_inputs
  local checkpoint predecessor
  local mutation_kind status evidence started completed evidence_sha
  file="${1:?checkpoint record file required}"
  [ ! -e "$file" ] || die "Checkpoint record already exists: $file"
  backend="${2:?backend required}"
  set_id="${3:?set ID required}"
  run_id="${4:?run ID required}"
  baseline="${5:?baseline fingerprint required}"
  source_inputs="${6:?source input fingerprint required}"
  effective_inputs="${7:?effective input fingerprint required}"
  checkpoint="${8:?checkpoint required}"
  predecessor="${9:?predecessor fingerprint required}"
  mutation_kind="${10:?mutation kind required}"
  status="${11:?checkpoint status required}"
  evidence="${12:?evidence file required}"
  started="${13:?start timestamp required}"
  completed="${14:?completion timestamp required}"
  simulation_checkpoint_name_is_known "$checkpoint" ||
    die "Unknown simulation checkpoint: $checkpoint"
  case "$mutation_kind" in mutating|observational) ;; *) die "Invalid checkpoint mutation kind" ;; esac
  case "$status" in complete|waiting) ;; *) die "Invalid checkpoint status" ;; esac
  evidence_sha="$(sha256_file "$evidence")" || return $?
  atomic_write_record "$file" "${LF_MODE_REVIEW_FILE:-0640}" \
    "schema_version=1" \
    "backend=$backend" \
    "set_id=$set_id" \
    "run_id=$run_id" \
    "baseline_fingerprint=$baseline" \
    "source_inputs_fingerprint=$source_inputs" \
    "effective_inputs_fingerprint=$effective_inputs" \
    "checkpoint=$checkpoint" \
    "predecessor_sha256=$predecessor" \
    "mutation_kind=$mutation_kind" \
    "status=$status" \
    "evidence_sha256=$evidence_sha" \
    "started_at=$started" \
    "completed_at=$completed"
}

checkpoint_record_is_strict() {
  strict_record_keys "${1:?checkpoint record required}" schema_version backend \
    set_id run_id baseline_fingerprint source_inputs_fingerprint \
    effective_inputs_fingerprint checkpoint predecessor_sha256 mutation_kind \
    status evidence_sha256 started_at completed_at
}

simulation_checkpoint_name_is_known() {
  case "${1-}" in
    prepare-artifacts-gerrit|prepare-artifacts-jenkins-controller|prepare-artifacts-jenkins-agent|\
    stage-artifacts-gerrit|stage-artifacts-jenkins-controller|stage-artifacts-jenkins-agent|\
    configure-role-gerrit|configure-role-jenkins-controller|configure-role-jenkins-agent|\
    validate-role-gerrit|validate-role-jenkins-controller|validate-role-jenkins-agent|\
    reviewed-integration-access|configure-integration|validate-integration|prove-integration)
      return 0
      ;;
    *) return 1 ;;
  esac
}

simulation_checkpoint_ordinal() {
  case "${1-}" in
    prepare-artifacts-gerrit) printf '1\n' ;;
    prepare-artifacts-jenkins-controller) printf '2\n' ;;
    prepare-artifacts-jenkins-agent) printf '3\n' ;;
    stage-artifacts-gerrit) printf '4\n' ;;
    stage-artifacts-jenkins-controller) printf '5\n' ;;
    stage-artifacts-jenkins-agent) printf '6\n' ;;
    configure-role-gerrit) printf '7\n' ;;
    configure-role-jenkins-controller) printf '8\n' ;;
    configure-role-jenkins-agent) printf '9\n' ;;
    validate-role-gerrit) printf '10\n' ;;
    validate-role-jenkins-controller) printf '11\n' ;;
    validate-role-jenkins-agent) printf '12\n' ;;
    reviewed-integration-access) printf '13\n' ;;
    configure-integration) printf '14\n' ;;
    validate-integration) printf '15\n' ;;
    prove-integration) printf '16\n' ;;
    *) return 1 ;;
  esac
}

checkpoint_chain_is_valid() {
  local dir checkpoint expected_sha backend set_id run_id baseline source_inputs
  local effective_inputs
  local file actual_sha predecessor candidate candidate_sha matches count ordinal
  dir="${1:?checkpoint directory required}"
  checkpoint="${2:?last checkpoint required}"
  expected_sha="${3:?last record fingerprint required}"
  backend="${4:?backend required}"
  set_id="${5:?set ID required}"
  run_id="${6:?run ID required}"
  baseline="${7:?baseline fingerprint required}"
  source_inputs="${8:?source input fingerprint required}"
  effective_inputs="${9:?effective input fingerprint required}"
  count=0
  file="$dir/$checkpoint.env"
  while [ "$expected_sha" != none ]; do
    count=$((count + 1))
    [ "$count" -le 64 ] || return 1
    checkpoint_record_is_strict "$file" || return 1
    actual_sha="$(sha256_file "$file")"
    [ "$actual_sha" = "$expected_sha" ] || return 1
    simulation_checkpoint_name_is_known "$(strict_record_value "$file" checkpoint)" || return 1
    [ "$(strict_record_value "$file" schema_version)" = 1 ] || return 1
    [ "$(strict_record_value "$file" backend)" = "$backend" ] || return 1
    [ "$(strict_record_value "$file" set_id)" = "$set_id" ] || return 1
    [ "$(strict_record_value "$file" run_id)" = "$run_id" ] || return 1
    [ "$(strict_record_value "$file" baseline_fingerprint)" = "$baseline" ] || return 1
    [ "$(strict_record_value "$file" source_inputs_fingerprint)" = "$source_inputs" ] || return 1
    [ "$(strict_record_value "$file" effective_inputs_fingerprint)" = "$effective_inputs" ] || return 1
    [ "$(strict_record_value "$file" checkpoint)" = "$checkpoint" ] || return 1
    ordinal="$(simulation_checkpoint_ordinal "$checkpoint")" || return 1
    predecessor="$(strict_record_value "$file" predecessor_sha256)"
    if [ "$predecessor" = none ]; then
      [ "$ordinal" -eq 1 ] || return 1
      return 0
    fi
    [ "$ordinal" -gt 1 ] || return 1
    matches=0
    for candidate in "$dir"/*.env; do
      [ -f "$candidate" ] || continue
      candidate_sha="$(sha256_file "$candidate")"
      if [ "$candidate_sha" = "$predecessor" ]; then
        checkpoint_record_is_strict "$candidate" || return 1
        file="$candidate"
        checkpoint="$(strict_record_value "$candidate" checkpoint)"
        [ "$(simulation_checkpoint_ordinal "$checkpoint")" -eq $((ordinal - 1)) ] ||
          return 1
        [ "$(strict_record_value "$candidate" status)" = complete ] || return 1
        matches=$((matches + 1))
      fi
    done
    [ "$matches" -eq 1 ] || return 1
    expected_sha="$predecessor"
  done
  return 1
}

workflow_state_publish_checkpoint() {
  local workflow record status checkpoint next_activity next_active activity
  local checkpoint_ordinal last_checkpoint last_ordinal
  workflow="${1:?workflow state file required}"
  record="${2:?checkpoint record required}"
  status="${3:?checkpoint status required}"
  workflow_state_is_strict "$workflow" || die "Workflow state has malformed or unexpected fields"
  checkpoint_record_is_strict "$record" || die "Checkpoint record has malformed or unexpected fields"
  checkpoint="$(strict_record_value "$record" checkpoint)"
  simulation_checkpoint_name_is_known "$checkpoint" ||
    die "Unknown simulation checkpoint: $checkpoint"
  [ "$(strict_record_value "$workflow" active_checkpoint)" = "$checkpoint" ] ||
    die "Checkpoint record does not match active workflow checkpoint"
  [ "$(strict_record_value "$record" backend)" = "$(strict_record_value "$workflow" backend)" ] ||
    die "Checkpoint record backend does not match workflow state"
  [ "$(strict_record_value "$record" set_id)" = "$(strict_record_value "$workflow" set_id)" ] ||
    die "Checkpoint record set ID does not match workflow state"
  [ "$(strict_record_value "$record" run_id)" = "$(strict_record_value "$workflow" run_id)" ] ||
    die "Checkpoint record run ID does not match workflow state"
  [ "$(strict_record_value "$record" baseline_fingerprint)" = "$(strict_record_value "$workflow" baseline_fingerprint)" ] ||
    die "Checkpoint record baseline does not match workflow state"
  [ "$(strict_record_value "$record" source_inputs_fingerprint)" = "$(strict_record_value "$workflow" source_inputs_fingerprint)" ] ||
    die "Checkpoint record source inputs do not match workflow state"
  [ "$(strict_record_value "$record" effective_inputs_fingerprint)" = "$(strict_record_value "$workflow" effective_inputs_fingerprint)" ] ||
    die "Checkpoint record effective inputs do not match workflow state"
  [ "$(strict_record_value "$record" predecessor_sha256)" = "$(strict_record_value "$workflow" last_record_sha256)" ] ||
    die "Checkpoint record predecessor does not match workflow head"
  checkpoint_ordinal="$(simulation_checkpoint_ordinal "$checkpoint")" ||
    die "Unknown simulation checkpoint: $checkpoint"
  last_checkpoint="$(strict_record_value "$workflow" last_checkpoint)"
  if [ "$last_checkpoint" = none ]; then
    [ "$checkpoint_ordinal" -eq 1 ] ||
      die "Checkpoint record is not the first workflow checkpoint"
  else
    last_ordinal="$(simulation_checkpoint_ordinal "$last_checkpoint")" ||
      die "Workflow head names an unknown checkpoint"
    [ "$checkpoint_ordinal" -eq $((last_ordinal + 1)) ] ||
      die "Checkpoint record is out of workflow order"
  fi
  activity="$(strict_record_value "$workflow" activity)"
  case "$activity" in
    observing|mutating) ;;
    *) die "Workflow state has no publishable checkpoint activity" ;;
  esac
  case "$activity:$(strict_record_value "$record" mutation_kind)" in
    observing:observational|mutating:mutating) ;;
    *) die "Checkpoint record mutation kind does not match workflow activity" ;;
  esac
  case "$status" in
    complete) next_activity=idle; next_active=none ;;
    waiting) next_activity=waiting; next_active="$checkpoint" ;;
    *) die "Unsupported checkpoint publication status: $status" ;;
  esac
  [ "$(strict_record_value "$record" status)" = "$status" ] ||
    die "Checkpoint record status does not match publication status"
  atomic_write_record "$workflow" "${LF_MODE_REVIEW_FILE:-0640}" \
    "schema_version=$(strict_record_value "$workflow" schema_version)" \
    "backend=$(strict_record_value "$workflow" backend)" \
    "set_id=$(strict_record_value "$workflow" set_id)" \
    "run_id=$(strict_record_value "$workflow" run_id)" \
    "run_marker_sha256=$(strict_record_value "$workflow" run_marker_sha256)" \
    "baseline_fingerprint=$(strict_record_value "$workflow" baseline_fingerprint)" \
    "source_inputs_fingerprint=$(strict_record_value "$workflow" source_inputs_fingerprint)" \
    "input_state=ready" \
    "effective_inputs_fingerprint=$(strict_record_value "$workflow" effective_inputs_fingerprint)" \
    "activity=$next_activity" \
    "active_checkpoint=$next_active" \
    "last_checkpoint=$checkpoint" \
    "last_record_sha256=$(sha256_file "$record")"
}

simulation_classify_claimed_state() {
  local active marker workflow backend set_id run_id namespace backend_state
  local checkpoint_dir baseline source_inputs effective_inputs input_state
  local active_state activity active_checkpoint last_checkpoint last_record
  local active_ordinal last_ordinal last_file last_status chain_valid
  active="${1:?active-run file required}"
  marker="${2:?run marker required}"
  workflow="${3:?workflow state file required}"
  backend="${4:?backend required}"
  set_id="${5:?set ID required}"
  run_id="${6:?run ID required}"
  namespace="${7:?resource namespace required}"
  backend_state="${8:?backend state required}"
  checkpoint_dir="${9-}"

  if ! active_run_record_is_strict "$active" ||
    ! workflow_state_is_strict "$workflow" || [ ! -f "$marker" ]; then
    printf 'conflicting\n'
    return
  fi
  if [ "$(strict_record_value "$active" schema_version)" != 1 ] ||
    [ "$(strict_record_value "$workflow" schema_version)" != 1 ] ||
    [ "$(strict_record_value "$active" backend)" != "$backend" ] ||
    [ "$(strict_record_value "$workflow" backend)" != "$backend" ] ||
    [ "$(strict_record_value "$active" set_id)" != "$set_id" ] ||
    [ "$(strict_record_value "$workflow" set_id)" != "$set_id" ] ||
    [ "$(strict_record_value "$active" run_id)" != "$run_id" ] ||
    [ "$(strict_record_value "$workflow" run_id)" != "$run_id" ] ||
    [ "$(strict_record_value "$active" resource_namespace)" != "$namespace" ] ||
    [ "$(strict_record_value "$active" run_marker_sha256)" != "$(sha256_file "$marker")" ] ||
    [ "$(strict_record_value "$workflow" run_marker_sha256)" != "$(sha256_file "$marker")" ] ||
    [ "$(strict_record_value "$active" baseline_fingerprint)" != "$(strict_record_value "$workflow" baseline_fingerprint)" ] ||
    [ "$(strict_record_value "$marker" source_inputs_fingerprint)" != "$(strict_record_value "$workflow" source_inputs_fingerprint)" ]; then
    printf 'conflicting\n'
    return
  fi

  active_state="$(strict_record_value "$active" state)"
  activity="$(strict_record_value "$workflow" activity)"
  active_checkpoint="$(strict_record_value "$workflow" active_checkpoint)"
  last_checkpoint="$(strict_record_value "$workflow" last_checkpoint)"
  last_record="$(strict_record_value "$workflow" last_record_sha256)"
  baseline="$(strict_record_value "$workflow" baseline_fingerprint)"
  source_inputs="$(strict_record_value "$workflow" source_inputs_fingerprint)"
  effective_inputs="$(strict_record_value "$workflow" effective_inputs_fingerprint)"
  input_state="$(strict_record_value "$workflow" input_state)"
  case "$input_state" in
    pending) [ "$effective_inputs" = none ] || { printf 'conflicting\n'; return; } ;;
    ready) sha256_fingerprint_is_valid "$effective_inputs" || { printf 'conflicting\n'; return; } ;;
    *) printf 'conflicting\n'; return ;;
  esac
  case "$active_state:$(strict_record_value "$active" restore_evidence_sha256)" in
    active:none) ;;
    restored-pending-clean:none) printf 'conflicting\n'; return ;;
    restored-pending-clean:*)
      [ "$backend_state" = baseline ] && printf 'baseline\n' || printf 'conflicting\n'
      return
      ;;
    *) printf 'conflicting\n'; return ;;
  esac
  case "$activity:$active_checkpoint" in
    idle:none|observing:*|waiting:*) ;;
    mutating:*) ;;
    *) printf 'conflicting\n'; return ;;
  esac
  if [ "$activity" != idle ]; then
    simulation_checkpoint_name_is_known "$active_checkpoint" || {
      printf 'conflicting\n'
      return
    }
    active_ordinal="$(simulation_checkpoint_ordinal "$active_checkpoint")" || {
      printf 'conflicting\n'
      return
    }
  fi
  chain_valid=0
  if [ "$last_checkpoint" != none ] && [ "$last_record" != none ] &&
    [ -n "$checkpoint_dir" ] &&
    checkpoint_chain_is_valid "$checkpoint_dir" "$last_checkpoint" "$last_record" \
      "$backend" "$set_id" "$run_id" "$baseline" "$source_inputs" \
      "$effective_inputs"; then
    chain_valid=1
  elif [ "$last_checkpoint" != none ] || [ "$last_record" != none ]; then
    printf 'conflicting\n'
    return
  fi
  if [ "$activity" = mutating ] || [ "$activity" = observing ]; then
    [ "$input_state" = ready ] || {
      printf 'conflicting\n'
      return
    }
    if [ "$last_checkpoint" = none ]; then
      [ "$active_ordinal" -eq 1 ] || {
        printf 'conflicting\n'
        return
      }
    else
      last_ordinal="$(simulation_checkpoint_ordinal "$last_checkpoint")" || {
        printf 'conflicting\n'
        return
      }
      if [ "$chain_valid" -ne 1 ] ||
        [ "$active_ordinal" -ne $((last_ordinal + 1)) ]; then
        printf 'conflicting\n'
        return
      fi
    fi
  fi
  if [ "$activity" = mutating ]; then
    printf 'active-incomplete\n'
    return
  fi
  if [ "$last_checkpoint" = none ] && [ "$last_record" = none ]; then
    [ "$activity" != waiting ] || {
      printf 'conflicting\n'
      return
    }
    case "$backend_state" in
      absent) printf 'none\n' ;;
      baseline|exact) printf 'baseline\n' ;;
      *) printf 'conflicting\n' ;;
    esac
    return
  fi
  [ "$input_state" = ready ] || {
    printf 'conflicting\n'
    return
  }
  last_file="$checkpoint_dir/$last_checkpoint.env"
  last_status="$(strict_record_value "$last_file" status)"
  case "$activity:$last_status" in
    idle:complete|observing:complete) ;;
    waiting:waiting)
      [ "$active_checkpoint" = "$last_checkpoint" ] || {
        printf 'conflicting\n'
        return
      }
      ;;
    *) printf 'conflicting\n'; return ;;
  esac
  if [ "$chain_valid" -eq 1 ] && [ "$backend_state" = exact ]; then
    printf 'exact-bound\n'
  else
    printf 'conflicting\n'
  fi
}

require_generated_state_file() {
  local state_name label file
  state_name="${1:?state name required}"
  label="${2:?label required}"
  file="${3:?file required}"
  [ -f "$file" ] || die "Inconsistent $state_name: missing $label: $file"
  [ -r "$file" ] || die "Inconsistent $state_name: unreadable $label: $file"
}

require_generated_state_dir() {
  local state_name label dir
  state_name="${1:?state name required}"
  label="${2:?label required}"
  dir="${3:?dir required}"
  [ -d "$dir" ] || die "Inconsistent $state_name: missing $label: $dir"
  [ ! -L "$dir" ] || die "Inconsistent $state_name: $label must not be a symlink: $dir"
}

any_path_exists() {
  local path
  for path in "$@"; do
    [ -e "$path" ] && return 0
  done
  return 1
}
