#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
lib_dir="$repo_root/simulation/lib"

. "$lib_dir/common.sh"
. "$lib_dir/permissions.sh"
. "$lib_dir/identity.sh"
. "$lib_dir/locking.sh"
. "$lib_dir/env.sh"
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
source_dir="$tmp_dir/source-inputs"
effective_dir="$tmp_dir/runtime-inputs"
effective_record="$tmp_dir/run/state/effective-inputs.env"
marker="$tmp_dir/run.env"
active="$tmp_dir/set/active-run.env"
workflow="$tmp_dir/run/state/workflow-state.env"
checkpoint_dir="$tmp_dir/run/state/checkpoints"
printf 'HARNESS_MODE=docker-simulation\n' >"$runtime_env"
mkdir -p "$source_dir" "$checkpoint_dir"
for input in harness.env gerrit.env jenkins-controller.env jenkins-agent.env integration.env; do
  printf 'input=%s\n' "$input" >"$source_dir/$input"
done
source_inputs="$(simulation_input_bundle_fingerprint "$source_dir")"
write_runtime_marker "$marker" docker-simulation docker default run-a \
  loopforge-docker-default "$repo_root" "$tmp_dir/run" "$runtime_env" "$source_dir"
write_initial_workflow_state "$workflow" docker default run-a "$marker" none "$source_inputs"
cp "$workflow" "$tmp_dir/pending-workflow.env"
write_active_run_record "$active" docker default run-a loopforge-docker-default \
  "$marker" none active none
lifecycle_records_are_bound "$active" "$marker" "$workflow" docker default \
  run-a loopforge-docker-default "$source_inputs"
[ "$(strict_record_value "$workflow" input_state)" = pending ]
[ "$(strict_record_value "$workflow" effective_inputs_fingerprint)" = none ]
simulation_input_state_is_bound "$workflow" "$marker" docker default run-a \
  "$source_dir" "$effective_record" "$effective_dir"
if (workflow_state_publish_activity "$workflow" mutating prepare-artifacts-gerrit) \
  >/dev/null 2>&1; then
  fail "Pending effective inputs allowed workflow activity"
fi
[ "$(simulation_classify_claimed_state "$active" "$marker" "$workflow" \
  docker default run-a loopforge-docker-default absent "$checkpoint_dir")" = none ]

staged="$tmp_dir/staged-effective-inputs"
cp -R "$source_dir" "$staged"
publish_or_verify_effective_inputs "$workflow" "$marker" docker default run-a \
  "$source_dir" "$effective_record" "$effective_dir" "$staged"
effective_inputs="$(simulation_input_bundle_fingerprint "$effective_dir")"
[ "$(strict_record_value "$workflow" input_state)" = ready ]
[ "$(strict_record_value "$workflow" effective_inputs_fingerprint)" = "$effective_inputs" ]
require_effective_inputs_ready "$workflow" "$marker" docker default run-a \
  "$source_dir" "$effective_record" "$effective_dir"
[ "$(simulation_classify_claimed_state "$active" "$marker" "$workflow" \
  docker default run-a loopforge-docker-default exact "$checkpoint_dir")" = baseline ]

staged="$tmp_dir/staged-effective-inputs-repeat"
cp -R "$source_dir" "$staged"
publish_or_verify_effective_inputs "$workflow" "$marker" docker default run-a \
  "$source_dir" "$effective_record" "$effective_dir" "$staged"
[ ! -e "$staged" ]

staged="$tmp_dir/staged-effective-inputs-changed"
cp -R "$source_dir" "$staged"
printf 'changed=true\n' >>"$staged/integration.env"
if (publish_or_verify_effective_inputs "$workflow" "$marker" docker default run-a \
  "$source_dir" "$effective_record" "$effective_dir" "$staged") \
  >/dev/null 2>&1; then
  fail "Changed effective inputs were accepted after publication"
fi

partial_workflow="$tmp_dir/partial-directory-workflow.env"
partial_record="$tmp_dir/partial-directory-record.env"
partial_effective="$tmp_dir/partial-directory-effective"
partial_staged="$tmp_dir/partial-directory-staged"
cp "$tmp_dir/pending-workflow.env" "$partial_workflow"
cp -R "$source_dir" "$partial_staged"
if (HARNESS_TEST_EFFECTIVE_PUBLICATION_FAIL_AFTER=directory \
  publish_or_verify_effective_inputs "$partial_workflow" "$marker" docker default run-a \
    "$source_dir" "$partial_record" "$partial_effective" "$partial_staged") \
  >/dev/null 2>&1; then
  fail "Injected interruption after effective directory publication succeeded"
fi
[ -d "$partial_effective" ]
[ ! -e "$partial_record" ]
grep -Fxq 'input_state=pending' "$partial_workflow"
partial_retry="$tmp_dir/partial-directory-retry"
cp -R "$source_dir" "$partial_retry"
if (publish_or_verify_effective_inputs "$partial_workflow" "$marker" docker default run-a \
  "$source_dir" "$partial_record" "$partial_effective" "$partial_retry") \
  >/dev/null 2>&1; then
  fail "Retry silently repaired partial effective directory publication"
fi

partial_workflow="$tmp_dir/partial-record-workflow.env"
partial_record="$tmp_dir/partial-record.env"
partial_effective="$tmp_dir/partial-record-effective"
partial_staged="$tmp_dir/partial-record-staged"
cp "$tmp_dir/pending-workflow.env" "$partial_workflow"
cp -R "$source_dir" "$partial_staged"
if (HARNESS_TEST_EFFECTIVE_PUBLICATION_FAIL_AFTER=record \
  publish_or_verify_effective_inputs "$partial_workflow" "$marker" docker default run-a \
    "$source_dir" "$partial_record" "$partial_effective" "$partial_staged") \
  >/dev/null 2>&1; then
  fail "Injected interruption after effective record publication succeeded"
fi
[ -d "$partial_effective" ]
[ -f "$partial_record" ]
grep -Fxq 'input_state=pending' "$partial_workflow"
partial_retry="$tmp_dir/partial-record-retry"
cp -R "$source_dir" "$partial_retry"
if (publish_or_verify_effective_inputs "$partial_workflow" "$marker" docker default run-a \
  "$source_dir" "$partial_record" "$partial_effective" "$partial_retry") \
  >/dev/null 2>&1; then
  fail "Retry silently repaired partial effective record publication"
fi

workflow_state_publish_activity "$workflow" mutating prepare-artifacts-gerrit
[ "$(simulation_classify_claimed_state "$active" "$marker" "$workflow" \
  docker default run-a loopforge-docker-default exact "$checkpoint_dir")" = active-incomplete ]

producer_record="$tmp_dir/producer-record.json"
printf '{}\n' >"$producer_record"
record="$checkpoint_dir/prepare-artifacts-gerrit.env"
write_immutable_checkpoint_record "$record" docker default run-a none \
  "$source_inputs" "$effective_inputs" prepare-artifacts-gerrit none mutating \
  complete "$producer_record" \
  2026-07-17T00:00:00Z 2026-07-17T00:00:01Z
grep -Fxq "producer_record_sha256=$(sha256_file "$producer_record")" "$record"
if grep -q '^evidence_sha256=' "$record"; then
  fail "Workflow checkpoint retained the superseded evidence digest field"
fi
workflow_state_publish_checkpoint "$workflow" "$record" complete
[ "$(simulation_classify_claimed_state "$active" "$marker" "$workflow" \
  docker default run-a loopforge-docker-default exact "$checkpoint_dir")" = exact-bound ]

cross_workflow="$tmp_dir/cross-workflow.env"
cross_record="$tmp_dir/cross-record.env"
cp "$workflow" "$cross_workflow"
workflow_state_publish_activity "$cross_workflow" mutating prepare-artifacts-jenkins-controller
write_immutable_checkpoint_record "$cross_record" docker default run-b none \
  "$source_inputs" "$effective_inputs" prepare-artifacts-jenkins-controller \
  "$(sha256_file "$record")" mutating complete \
  "$producer_record" 2026-07-17T00:00:02Z 2026-07-17T00:00:03Z
if (workflow_state_publish_checkpoint "$cross_workflow" "$cross_record" complete) \
  >/dev/null 2>&1; then
  fail "Cross-run checkpoint record was published"
fi

order_workflow="$tmp_dir/order-workflow.env"
order_record="$tmp_dir/order-record.env"
cp "$workflow" "$order_workflow"
workflow_state_publish_activity "$order_workflow" mutating stage-artifacts-gerrit
write_immutable_checkpoint_record "$order_record" docker default run-a none \
  "$source_inputs" "$effective_inputs" stage-artifacts-gerrit \
  "$(sha256_file "$record")" mutating complete "$producer_record" \
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

sed 's/^effective_inputs_fingerprint=.*/effective_inputs_fingerprint=none/' \
  "$workflow" >"$tmp_dir/ready-none.env"
[ "$(simulation_classify_claimed_state "$active" "$marker" "$tmp_dir/ready-none.env" \
  docker default run-a loopforge-docker-default exact "$checkpoint_dir")" = conflicting ]

printf 'changed=true\n' >>"$effective_dir/integration.env"
if (require_effective_inputs_ready "$workflow" "$marker" docker default run-a \
  "$source_dir" "$effective_record" "$effective_dir") >/dev/null 2>&1; then
  fail "Changed published effective inputs remained ready"
fi

printf 'Simulation lifecycle state library test passed\n'
