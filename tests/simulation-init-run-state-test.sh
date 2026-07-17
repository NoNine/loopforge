#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
docker_set="init-docker-$$"
vm_set="init-vm-$$"
collision_set="collision-$$"
publish_set="publish-fail-$$"
docker_root="$repo_root/generated/simulation/docker"
vm_root="$repo_root/generated/simulation/vm"

. "$repo_root/simulation/lib/common.sh"
. "$repo_root/simulation/lib/state.sh"
. "$repo_root/simulation/lib/identity.sh"

cleanup() {
  local run_id
  for output in "$tmp_dir"/*.out; do
    [ -f "$output" ] || continue
    run_id="$(sed -n 's/.*run-id=\([^ ]*\).*/\1/p' "$output" | tail -1)"
    [ -z "$run_id" ] || rm -rf "$docker_root/$run_id" "$vm_root/$run_id"
  done
  rm -rf "$tmp_dir" \
    "$docker_root/sets/$docker_set" "$vm_root/sets/$vm_set" \
    "$docker_root/sets/$collision_set" "$docker_root/sets/$publish_set" \
    "$docker_root/collision-run" "$docker_root/publish-fail-run"
  rm -f "$docker_root/locks/$docker_set.lock" \
    "$vm_root/locks/$vm_set.lock" "$docker_root/locks/$collision_set.lock" \
    "$docker_root/locks/$publish_set.lock"
}
trap cleanup EXIT

sed "s/^HARNESS_SET_ID=.*/HARNESS_SET_ID=$docker_set/" \
  "$repo_root/simulation/docker/examples/docker.env.example" >"$tmp_dir/docker.env"
sed "s/^HARNESS_SET_ID=.*/HARNESS_SET_ID=$vm_set/" \
  "$repo_root/simulation/vm/examples/vm.env.example" >"$tmp_dir/vm.env"

for harness in simulation/docker/simulate.sh simulation/vm/simulate.sh; do
  if "$repo_root/$harness" up >"$tmp_dir/removed-command.out" 2>&1; then
    printf '%s unexpectedly accepted removed command up\n' "$harness" >&2
    exit 1
  fi
  grep -Fq 'Unknown command: up' "$tmp_dir/removed-command.out"
done

"$repo_root/simulation/docker/simulate.sh" --env "$tmp_dir/docker.env" init-run \
  >"$tmp_dir/docker.out"
docker_run="$(sed -n 's/.*run-id=\([^ ]*\).*/\1/p' "$tmp_dir/docker.out")"
case "$docker_run" in run-*t*z-[a-f0-9]*) ;; *) exit 1 ;; esac
[ -f "$docker_root/sets/$docker_set/active-run.env" ]
[ -f "$docker_root/$docker_run/host/state/workflow-state.env" ]
[ -d "$docker_root/$docker_run/host/source-inputs" ]
[ ! -e "$docker_root/$docker_run/host/runtime-inputs" ]
[ ! -e "$docker_root/$docker_run/host/state/effective-inputs.env" ]
grep -Fxq 'input_state=pending' \
  "$docker_root/$docker_run/host/state/workflow-state.env"
grep -Fxq 'effective_inputs_fingerprint=none' \
  "$docker_root/$docker_run/host/state/workflow-state.env"
grep -Eq '^source_inputs_fingerprint=[a-f0-9]{64}$' \
  "$docker_root/$docker_run/.loopforge-docker-run.env"
grep -Fxq "resource_namespace=loopforge-docker-$docker_set" \
  "$docker_root/sets/$docker_set/active-run.env"
[ "$(resolve_harness_run_id docker "$docker_root" "$docker_set" "")" = "$docker_run" ]

"$repo_root/simulation/vm/simulate.sh" --env "$tmp_dir/vm.env" init-run \
  >"$tmp_dir/vm.out"
vm_run="$(sed -n 's/.*run-id=\([^ ]*\).*/\1/p' "$tmp_dir/vm.out")"
case "$vm_run" in run-*t*z-[a-f0-9]*) ;; *) exit 1 ;; esac
[ -f "$vm_root/sets/$vm_set/active-run.env" ]
[ -f "$vm_root/$vm_run/host/state/workflow-state.env" ]
[ -d "$vm_root/$vm_run/host/source-inputs" ]
[ ! -e "$vm_root/$vm_run/host/runtime-inputs" ]
[ ! -e "$vm_root/$vm_run/host/state/effective-inputs.env" ]
grep -Fxq 'input_state=pending' \
  "$vm_root/$vm_run/host/state/workflow-state.env"
grep -Fxq 'effective_inputs_fingerprint=none' \
  "$vm_root/$vm_run/host/state/workflow-state.env"
grep -Eq '^source_inputs_fingerprint=[a-f0-9]{64}$' \
  "$vm_root/$vm_run/.loopforge-vm-run.env"
grep -Fxq "resource_namespace=loopforge-vm-$vm_set" \
  "$vm_root/sets/$vm_set/active-run.env"
[ "$(resolve_harness_run_id vm "$vm_root" "$vm_set" "")" = "$vm_run" ]

cp "$tmp_dir/vm.env" "$tmp_dir/legacy-vm.env"
printf 'LOOPFORGE_VM_SET_ID=legacy\n' >>"$tmp_dir/legacy-vm.env"
if "$repo_root/simulation/vm/simulate.sh" --env "$tmp_dir/legacy-vm.env" preflight \
  >"$tmp_dir/legacy-vm.out" 2>&1; then
  printf 'VM harness unexpectedly accepted LOOPFORGE_VM_SET_ID\n' >&2
  exit 1
fi
grep -Fq 'LOOPFORGE_VM_SET_ID is not supported' "$tmp_dir/legacy-vm.out"

if "$repo_root/simulation/docker/simulate.sh" --env "$tmp_dir/docker.env" init-run \
  >"$tmp_dir/docker-repeat.out" 2>&1; then
  printf 'Repeated init-run unexpectedly replaced an active set\n' >&2
  exit 1
fi
grep -Fq 'already has active-run state' "$tmp_dir/docker-repeat.out"

mkdir -p "$docker_root/collision-run"
sed \
  -e "s/^HARNESS_SET_ID=.*/HARNESS_SET_ID=$collision_set/" \
  -e 's/^HARNESS_RUN_ID=.*/HARNESS_RUN_ID=collision-run/' \
  "$repo_root/simulation/docker/examples/docker.env.example" >"$tmp_dir/collision.env"
if "$repo_root/simulation/docker/simulate.sh" --env "$tmp_dir/collision.env" init-run \
  >"$tmp_dir/collision.out" 2>&1; then
  printf 'init-run unexpectedly reused an existing run root\n' >&2
  exit 1
fi
grep -Fq 'HARNESS_RUN_ID already exists: collision-run' "$tmp_dir/collision.out"

sed \
  -e "s/^HARNESS_SET_ID=.*/HARNESS_SET_ID=$publish_set/" \
  -e 's/^HARNESS_RUN_ID=.*/HARNESS_RUN_ID=publish-fail-run/' \
  "$repo_root/simulation/docker/examples/docker.env.example" >"$tmp_dir/publish.env"
mkdir -p "$docker_root/sets/$publish_set"
chmod 0500 "$docker_root/sets/$publish_set"
if "$repo_root/simulation/docker/simulate.sh" --env "$tmp_dir/publish.env" init-run \
  >"$tmp_dir/publish.out" 2>&1; then
  printf 'init-run unexpectedly succeeded when active pointer publication failed\n' >&2
  exit 1
fi
chmod 0700 "$docker_root/sets/$publish_set"
[ ! -e "$docker_root/sets/$publish_set/active-run.env" ]
[ -f "$docker_root/publish-fail-run/.loopforge-docker-run.env" ]
[ -f "$docker_root/publish-fail-run/host/state/workflow-state.env" ]
[ -d "$docker_root/publish-fail-run/host/source-inputs" ]
[ ! -e "$docker_root/publish-fail-run/host/runtime-inputs" ]
[ ! -e "$docker_root/publish-fail-run/host/state/effective-inputs.env" ]
grep -Fxq 'input_state=pending' \
  "$docker_root/publish-fail-run/host/state/workflow-state.env"

printf 'Simulation init-run state test passed\n'
