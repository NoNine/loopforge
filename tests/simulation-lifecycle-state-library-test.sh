#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
lib_dir="$repo_root/simulation/lib"

. "$lib_dir/common.sh"
. "$lib_dir/permissions.sh"
. "$lib_dir/identity.sh"
. "$lib_dir/locking.sh"
. "$lib_dir/state.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

fail() {
  printf '%s\n' "$1" >&2
  exit 1
}

[ "$(simulation_resource_namespace docker default)" = loopforge-docker-default ]
[ "$(simulation_resource_namespace vm ci-7)" = loopforge-vm-ci-7 ]
short_name="$(simulation_short_resource_name vm default bridge lf- 15)"
[ "${#short_name}" -eq 15 ]
case "$(generate_harness_run_id)" in
  run-[0-9]*t[0-9]*z-[a-f0-9]*) ;;
  *) fail "Generated run ID has an unexpected shape" ;;
esac
if (validate_harness_set_id 'Bad_ID') >/dev/null 2>&1; then
  fail "Invalid set ID was accepted"
fi
if (validate_harness_set_id 'trailing-') >/dev/null 2>&1; then
  fail "Trailing hyphen was accepted"
fi
if (validate_harness_set_id 'abcdefghijklmnopqrstuvwxy') >/dev/null 2>&1; then
  fail "Set ID longer than 24 characters was accepted"
fi

lock_file="$(simulation_set_lock_path "$tmp_dir/backend" default)"
simulation_set_lock_acquire exclusive "$lock_file" default
if (
  unset SIMULATION_SET_LOCK_FD
  simulation_set_lock_acquire shared "$lock_file" default
) >/dev/null 2>&1; then
  fail "Contended set lock was acquired"
fi
simulation_set_lock_release
simulation_set_lock_acquire shared "$lock_file" default
if ! (
  unset SIMULATION_SET_LOCK_FD
  simulation_set_lock_acquire shared "$lock_file" default
  simulation_set_lock_release
); then
  fail "Concurrent shared set lock was rejected"
fi
if (
  unset SIMULATION_SET_LOCK_FD
  simulation_set_lock_acquire exclusive "$lock_file" default
) >/dev/null 2>&1; then
  fail "Exclusive set lock was acquired while a shared lock was held"
fi
simulation_set_lock_release

runtime_env="$tmp_dir/runtime.env"
input_dir="$tmp_dir/inputs"
marker="$tmp_dir/run.env"
active="$tmp_dir/set/active-run.env"
workflow="$tmp_dir/run/state/workflow-state.env"
checkpoint_dir="$tmp_dir/run/state/checkpoints"
printf 'HARNESS_MODE=docker-simulation\n' >"$runtime_env"
mkdir -p "$input_dir" "$checkpoint_dir"
for input in harness.env gerrit.env jenkins-controller.env jenkins-agent.env integration.env; do
  printf 'input=%s\n' "$input" >"$input_dir/$input"
done
inputs="$(reviewed_inputs_fingerprint "$input_dir")"
write_runtime_marker "$marker" docker-simulation docker default run-a \
  loopforge-docker-default "$repo_root" "$tmp_dir/run" "$runtime_env" "$input_dir"
write_initial_workflow_state "$workflow" docker default run-a "$marker" none "$inputs"
write_active_run_record "$active" docker default run-a loopforge-docker-default \
  "$marker" none active none
lifecycle_records_are_bound "$active" "$marker" "$workflow" docker default \
  run-a loopforge-docker-default "$inputs"
[ "$(simulation_classify_claimed_state "$active" "$marker" "$workflow" \
  docker default run-a loopforge-docker-default absent "$checkpoint_dir")" = none ]

workflow_state_publish_activity "$workflow" mutating prepare-artifacts-gerrit
[ "$(simulation_classify_claimed_state "$active" "$marker" "$workflow" \
  docker default run-a loopforge-docker-default exact "$checkpoint_dir")" = active-incomplete ]

evidence="$tmp_dir/evidence.json"
printf '{}\n' >"$evidence"
record="$checkpoint_dir/prepare-artifacts-gerrit.env"
write_immutable_checkpoint_record "$record" docker default run-a none "$inputs" \
  prepare-artifacts-gerrit none mutating complete "$evidence" \
  2026-07-17T00:00:00Z 2026-07-17T00:00:01Z
workflow_state_publish_checkpoint "$workflow" "$record" complete
[ "$(simulation_classify_claimed_state "$active" "$marker" "$workflow" \
  docker default run-a loopforge-docker-default exact "$checkpoint_dir")" = exact-bound ]

cross_workflow="$tmp_dir/cross-workflow.env"
cross_record="$tmp_dir/cross-record.env"
cp "$workflow" "$cross_workflow"
workflow_state_publish_activity "$cross_workflow" mutating prepare-artifacts-jenkins-controller
write_immutable_checkpoint_record "$cross_record" docker default run-b none "$inputs" \
  prepare-artifacts-jenkins-controller "$(sha256_file "$record")" mutating complete \
  "$evidence" 2026-07-17T00:00:02Z 2026-07-17T00:00:03Z
if (workflow_state_publish_checkpoint "$cross_workflow" "$cross_record" complete) \
  >/dev/null 2>&1; then
  fail "Cross-run checkpoint record was published"
fi

order_workflow="$tmp_dir/order-workflow.env"
order_record="$tmp_dir/order-record.env"
cp "$workflow" "$order_workflow"
workflow_state_publish_activity "$order_workflow" mutating stage-artifacts-gerrit
write_immutable_checkpoint_record "$order_record" docker default run-a none "$inputs" \
  stage-artifacts-gerrit "$(sha256_file "$record")" mutating complete "$evidence" \
  2026-07-17T00:00:04Z 2026-07-17T00:00:05Z
if (workflow_state_publish_checkpoint "$order_workflow" "$order_record" complete) \
  >/dev/null 2>&1; then
  fail "Out-of-order checkpoint record was published"
fi

unknown_workflow="$tmp_dir/unknown-workflow.env"
cp "$workflow" "$unknown_workflow"
if (workflow_state_publish_activity "$unknown_workflow" mutating unknown-step) \
  >/dev/null 2>&1; then
  fail "Unknown checkpoint activity was published"
fi

cp "$active" "$tmp_dir/duplicate.env"
printf 'state=active\n' >>"$tmp_dir/duplicate.env"
if active_run_record_is_strict "$tmp_dir/duplicate.env"; then
  fail "Duplicate active-run field was accepted"
fi

sed '/^state=/i unexpected=value' "$active" >"$tmp_dir/unknown-field.env"
if active_run_record_is_strict "$tmp_dir/unknown-field.env"; then
  fail "Unknown active-run field was accepted"
fi

sed '/^state=/d' "$active" >"$tmp_dir/missing-field.env"
if active_run_record_is_strict "$tmp_dir/missing-field.env"; then
  fail "Missing active-run field was accepted"
fi
mkdir -p "$tmp_dir/backend/sets/broken"
printf 'schema_version=1\nbackend=docker\n' \
  >"$tmp_dir/backend/sets/broken/active-run.env"
if (resolve_harness_run_id docker "$tmp_dir/backend" broken "") \
  >/dev/null 2>&1; then
  fail "Malformed active-run pointer resolved a run ID"
fi

sed 's/^run_id=run-a$/run_id=run-b/' "$workflow" >"$tmp_dir/mismatch.env"
[ "$(simulation_classify_claimed_state "$active" "$marker" "$tmp_dir/mismatch.env" \
  docker default run-a loopforge-docker-default exact "$checkpoint_dir")" = conflicting ]

printf 'Simulation lifecycle state library test passed\n'
