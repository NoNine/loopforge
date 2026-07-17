#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
docker_harness="$repo_root/simulation/docker/simulate.sh"
lib_dir="$repo_root/simulation/lib"

for module in common quote roles artifacts env identity locking state permissions logs evidence; do
  [ -f "$lib_dir/$module.sh" ] || {
    printf 'Missing shared simulation library module: %s.sh\n' "$module" >&2
    exit 1
  }
  bash -n "$lib_dir/$module.sh"
  grep -Fq -- ". \"\$simulation_lib_dir/$module.sh\"" "$docker_harness" || {
    printf 'Docker harness must source shared simulation module: %s.sh\n' "$module" >&2
    exit 1
  }
done

bash -n "$docker_harness"

for helper in \
  die \
  require_command \
  print_command_summary \
  print_command_failure \
  timestamp_utc \
  iso_timestamp_utc \
  require_readable_file \
  json_quote \
  shell_quote \
  validate_role_name \
  helper_for_role \
  role_helpers_root_for_operator \
  role_helper_path_for_operator \
  role_helper_source_paths \
  parse_role \
  parse_optional_role \
  bundle_name_for_role \
  bundle_payload_dir_for_role \
  manifest_get \
  env_file_value \
  validate_manifest_value \
  verify_checksum_file_in_dir \
  resolve_base_relative_path \
  source_env_file \
  set_env_file_value \
  remove_env_file_value \
  copy_simulation_input_bundle \
  simulation_input_bundles_are_identical \
  publish_simulation_input_bundle \
  validate_harness_set_id \
  simulation_resource_namespace \
  simulation_short_resource_name \
  generate_harness_run_id \
  resolve_harness_run_id \
  simulation_set_lock_path \
  simulation_set_lock_acquire \
  simulation_set_lock_release \
  simulation_with_set_lock \
  sha256_file \
  sha256_fingerprint_is_valid \
  runtime_env_fingerprint \
  marker_value \
  simulation_input_bundle_fingerprint \
  write_runtime_marker \
  verify_runtime_marker \
  write_effective_inputs_record \
  write_checkpoint_marker \
  verify_checkpoint_marker \
  require_generated_state_file \
  require_generated_state_dir \
  any_path_exists \
  bounded_log_path_in_dir \
  evidence_record_path
do
  if grep -Eq "^${helper}\\(\\)" "$docker_harness"; then
    printf 'Docker harness must use shared helper instead of redefining: %s\n' "$helper" >&2
    exit 1
  fi
done

usage() {
  :
}

# shellcheck source=/dev/null
. "$lib_dir/common.sh"
# shellcheck source=/dev/null
. "$lib_dir/quote.sh"
# shellcheck source=/dev/null
. "$lib_dir/roles.sh"
# shellcheck source=/dev/null
. "$lib_dir/artifacts.sh"
# shellcheck source=/dev/null
. "$lib_dir/env.sh"
# shellcheck source=/dev/null
. "$lib_dir/identity.sh"
# shellcheck source=/dev/null
. "$lib_dir/locking.sh"
# shellcheck source=/dev/null
. "$lib_dir/state.sh"
# shellcheck source=/dev/null
. "$lib_dir/permissions.sh"
# shellcheck source=/dev/null
. "$lib_dir/logs.sh"
# shellcheck source=/dev/null
. "$lib_dir/evidence.sh"

[ "$LF_MODE_PRIVATE_DIR" = 0700 ]
[ "$LF_MODE_PRIVATE_FILE" = 0600 ]
[ "$LF_MODE_REVIEW_DIR" = 0750 ]
[ "$LF_MODE_REVIEW_FILE" = 0640 ]
[ "$LF_MODE_PUBLIC_DIR" = 0755 ]
[ "$LF_MODE_PUBLIC_FILE" = 0644 ]
[ "$LF_MODE_EXECUTABLE_FILE" = 0755 ]
[ "$LF_MODE_SHARED_SETGID_DIR" = 2775 ]

[ "$(helper_for_role gerrit)" = "scripts/gerrit-setup.sh" ]
[ "$(helper_for_role jenkins-controller)" = "scripts/jenkins-controller-setup.sh" ]
[ "$(helper_for_role jenkins-agent)" = "scripts/jenkins-agent-setup.sh" ]
[ "$(role_helpers_root_for_operator ci-operator)" = "/home/ci-operator/loopforge" ]
[ "$(role_helper_path_for_operator ci-operator gerrit)" = "/home/ci-operator/loopforge/scripts/gerrit-setup.sh" ]
[ "$(role_helper_path_for_operator deploy jenkins-controller)" = "/home/deploy/loopforge/scripts/jenkins-controller-setup.sh" ]
for path in scripts/common.sh scripts/gerrit-setup.sh \
  scripts/jenkins-controller-setup.sh scripts/jenkins-agent-setup.sh \
  templates/gerrit templates/jenkins-controller templates/jenkins-agent; do
  role_helper_source_paths | grep -Fxq "$path"
done

[ "$(bundle_name_for_role gerrit)" = "gerrit-artifacts-bundle" ]
[ "$(bundle_name_for_role jenkins-controller)" = "jenkins-artifacts-bundle" ]
[ "$(bundle_name_for_role jenkins-agent)" = "jenkins-agent-artifacts-bundle" ]

[ "$(bundle_payload_dir_for_role gerrit)" = "gerrit" ]
[ "$(bundle_payload_dir_for_role jenkins-controller)" = "jenkins" ]
[ "$(bundle_payload_dir_for_role jenkins-agent)" = "jenkins-agent" ]

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

printf 'NAME=old\n' >"$tmp_dir/sample.env"
set_env_file_value "$tmp_dir/sample.env" NAME "new value"
grep -Fq "NAME=new\\ value" "$tmp_dir/sample.env"

[ "$(resolve_base_relative_path /base rel/path)" = "/base/rel/path" ]
[ "$(resolve_base_relative_path /base /abs/path)" = "/abs/path" ]

printf 'payload\n' >"$tmp_dir/payload.txt"
(cd "$tmp_dir" && sha256sum payload.txt >checksums.sha256)
verify_checksum_file_in_dir "$tmp_dir/checksums.sha256" "$tmp_dir" /dev/null

runtime_env="$tmp_dir/runtime.env"
marker="$tmp_dir/run.marker"
source_inputs="$tmp_dir/source-inputs"
effective_inputs="$tmp_dir/effective-inputs"
printf 'HARNESS_MODE=test\n' >"$runtime_env"
mkdir -p "$source_inputs" "$effective_inputs"
for input in harness.env gerrit.env jenkins-controller.env jenkins-agent.env integration.env; do
  printf '%s=test\n' "$input" >"$source_inputs/$input"
  cp "$source_inputs/$input" "$effective_inputs/$input"
done
write_runtime_marker "$marker" test-mode docker default run-1 \
  loopforge-docker-default "$repo_root" "$tmp_dir/run" "$runtime_env" "$source_inputs"
verify_runtime_marker "$marker" test-mode docker default run-1 \
  loopforge-docker-default "$repo_root" "$tmp_dir/run" "$runtime_env" \
  "$source_inputs" "test run marker"

effective_record="$tmp_dir/effective-inputs.env"
write_effective_inputs_record "$effective_record" docker default run-1 "$marker" \
  "$(simulation_input_bundle_fingerprint "$source_inputs")" "$effective_inputs"
effective_inputs_record_is_bound "$effective_record" docker default run-1 \
  "$marker" "$source_inputs" "$effective_inputs"

checkpoint_marker="$tmp_dir/checkpoint.marker"
write_checkpoint_marker "$checkpoint_marker" test-mode docker default run-1 \
  loopforge-docker-default "$runtime_env" "$source_inputs" "$effective_inputs"
verify_checkpoint_marker "$checkpoint_marker" test-mode docker default run-1 \
  loopforge-docker-default "$runtime_env" "$source_inputs" "$effective_inputs" \
  "test checkpoint marker"

require_generated_state_file "test generated state" payload "$tmp_dir/payload.txt"
require_generated_state_dir "test generated state" tmp "$tmp_dir"
any_path_exists "$tmp_dir/missing" "$tmp_dir/payload.txt"

log_path="$(bounded_log_path_in_dir "$tmp_dir/logs" example)"
case "$log_path" in
  "$tmp_dir/logs"/example-*.log) ;;
  *) printf 'Unexpected bounded log path: %s\n' "$log_path" >&2; exit 1 ;;
esac

evidence_path="$(evidence_record_path "$tmp_dir/evidence" checkpoint role)"
case "$evidence_path" in
  "$tmp_dir/evidence"/checkpoint-role-*.json) ;;
  *) printf 'Unexpected evidence path: %s\n' "$evidence_path" >&2; exit 1 ;;
esac
