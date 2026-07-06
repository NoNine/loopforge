#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
docker_harness="$repo_root/simulation/docker/simulate.sh"
lib_dir="$repo_root/simulation/lib"

for module in common quote roles artifacts env state logs evidence; do
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
  copy_simulation_runtime_env_inputs \
  sha256_file \
  runtime_env_fingerprint \
  marker_value \
  write_runtime_marker \
  verify_runtime_marker \
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
. "$lib_dir/state.sh"
# shellcheck source=/dev/null
. "$lib_dir/logs.sh"
# shellcheck source=/dev/null
. "$lib_dir/evidence.sh"

[ "$(helper_for_role gerrit)" = "scripts/gerrit-setup.sh" ]
[ "$(helper_for_role jenkins-controller)" = "scripts/jenkins-controller-setup.sh" ]
[ "$(helper_for_role jenkins-agent)" = "scripts/jenkins-agent-setup.sh" ]

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
printf 'HARNESS_MODE=test\n' >"$runtime_env"
write_runtime_marker "$marker" test-mode run-1 project-1 "$repo_root" "$tmp_dir/run" "$runtime_env"
verify_runtime_marker "$marker" test-mode run-1 project-1 "$repo_root" "$tmp_dir/run" "$runtime_env" "test run marker"

checkpoint_marker="$tmp_dir/checkpoint.marker"
write_checkpoint_marker "$checkpoint_marker" test-mode run-1 project-1 "$runtime_env"
verify_checkpoint_marker "$checkpoint_marker" test-mode run-1 project-1 "$runtime_env" "test checkpoint marker"

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
