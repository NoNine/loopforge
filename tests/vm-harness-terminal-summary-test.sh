#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
run_id="vm-summary-$$"
vm_set_id="summary-$$"
fresh_run_id="vm-summary-fresh-$$"
fresh_vm_set_id="summary-fresh-$$"
create_die_run_id="vm-summary-create-die-$$"
create_die_vm_set_id="sum-create-$$"
generated_root="$repo_root/generated/simulation/vm"
cleanup() {
  rm -rf "$tmp_dir" \
    "$generated_root/$run_id" \
    "$generated_root/sets/$vm_set_id" \
    "$generated_root/$fresh_run_id" \
    "$generated_root/sets/$fresh_vm_set_id" \
    "$generated_root/$create_die_run_id" \
    "$generated_root/sets/$create_die_vm_set_id"
  rm -f "$generated_root/locks/$vm_set_id.lock" \
    "$generated_root/locks/$fresh_vm_set_id.lock" \
    "$generated_root/locks/$create_die_vm_set_id.lock"
}
trap cleanup EXIT

env_file="$tmp_dir/harness.env"
fresh_env_file="$tmp_dir/harness-fresh.env"
create_die_env_file="$tmp_dir/harness-create-die.env"
fresh_workflow_calls="$tmp_dir/run-fresh-workflow.calls"
resume_workflow_calls="$tmp_dir/run-resume-workflow.calls"
stub_bin="$tmp_dir/bin"
mkdir -p "$stub_bin"

cat >"$stub_bin/virsh" <<'STUB'
#!/usr/bin/env bash
if [ "${1:-}" = "-c" ]; then
  shift 2
fi
case "${1:-}" in
  uri)
    printf 'qemu:///system\n'
    ;;
  list|net-list|pool-list)
    printf '\n'
    ;;
  domstate)
    exit 1
    ;;
  *)
    printf 'unexpected virsh command: %s\n' "$*" >&2
    exit 1
    ;;
esac
STUB
chmod +x "$stub_bin/virsh"

for tool in qemu-img virt-install cloud-localds; do
  cat >"$stub_bin/$tool" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
  chmod +x "$stub_bin/$tool"
done

sed \
  -e "s/^HARNESS_RUN_ID=.*/HARNESS_RUN_ID=$run_id/" \
  -e "s/^HARNESS_SET_ID=.*/HARNESS_SET_ID=$vm_set_id/" \
  "$repo_root/simulation/vm/examples/vm.env.example" >"$env_file"

sed \
  -e "s/^HARNESS_RUN_ID=.*/HARNESS_RUN_ID=$fresh_run_id/" \
  -e "s/^HARNESS_SET_ID=.*/HARNESS_SET_ID=$fresh_vm_set_id/" \
  "$repo_root/simulation/vm/examples/vm.env.example" >"$fresh_env_file"

sed \
  -e "s/^HARNESS_RUN_ID=.*/HARNESS_RUN_ID=$create_die_run_id/" \
  -e "s/^HARNESS_SET_ID=.*/HARNESS_SET_ID=$create_die_vm_set_id/" \
  -e "s|^VM_BASE_IMAGE_PATH=.*|VM_BASE_IMAGE_PATH=$tmp_dir/missing-base.img|" \
  "$repo_root/simulation/vm/examples/vm.env.example" >"$create_die_env_file"

PATH="$stub_bin:$PATH" HARNESS_TEST_WORKFLOW_CALLS="$fresh_workflow_calls" \
  "$repo_root/simulation/vm/simulate.sh" --env "$fresh_env_file" run \
  >"$tmp_dir/run-fresh.out" 2>"$tmp_dir/run-fresh.err"
grep -Fxq "run: mode=fresh run-id=$fresh_run_id set-id=$fresh_vm_set_id" "$tmp_dir/run-fresh.out"
grep -Fxq '==> preflight' "$tmp_dir/run-fresh.out"
grep -Fxq '==> init-run' "$tmp_dir/run-fresh.out"
grep -Fxq '==> create' "$tmp_dir/run-fresh.out"
grep -Fxq '==> status' "$tmp_dir/run-fresh.out"
awk '
  $0 == "==> preflight" { preflight = NR }
  $0 == "==> init-run" { init = NR }
  $0 == "==> create" { create = NR }
  $0 == "==> start" { start = NR }
  $0 == "==> status" { status = NR }
  END { exit !(preflight && init && create && start && status && preflight < init && init < create && create < start && start < status) }
' "$tmp_dir/run-fresh.out"
grep -Fxq 'status' "$fresh_workflow_calls"

PATH="$stub_bin:$PATH" \
  "$repo_root/simulation/vm/simulate.sh" --env "$env_file" preflight >"$tmp_dir/preflight.out"
grep -Fxq 'preflight: ok mode=vm-simulation libvirt=ok' "$tmp_dir/preflight.out"
! grep -Fq 'log=' "$tmp_dir/preflight.out"
! grep -Fq 'evidence=' "$tmp_dir/preflight.out"
! grep -Fq 'vm-resources=' "$tmp_dir/preflight.out"

"$repo_root/simulation/vm/simulate.sh" --env "$env_file" init-run >"$tmp_dir/init-run.out"
grep -Fxq "init-run: ok set-id=$vm_set_id run-id=$run_id" "$tmp_dir/init-run.out"
! grep -Fq 'evidence=' "$tmp_dir/init-run.out"

PATH="$stub_bin:$PATH" HARNESS_TEST_WORKFLOW_CALLS="$resume_workflow_calls" \
  "$repo_root/simulation/vm/simulate.sh" --env "$env_file" run \
  >"$tmp_dir/run-resume.out" 2>"$tmp_dir/run-resume.err"
grep -Fxq "run: mode=resume run-id=$run_id set-id=$vm_set_id" "$tmp_dir/run-resume.out"
grep -Fxq '==> create' "$tmp_dir/run-resume.out"
grep -Fxq '==> status' "$tmp_dir/run-resume.out"
awk '
  $0 == "==> create" { create = NR }
  $0 == "==> start" { start = NR }
  $0 == "==> status" { status = NR }
  END { exit !(create && start && status && create < start && start < status) }
' "$tmp_dir/run-resume.out"
if grep -Eq '^==> (preflight|init-run)$' "$tmp_dir/run-resume.out"; then
  printf 'resume run should not rerun preflight or init-run\n' >&2
  exit 1
fi
grep -Fxq 'status' "$resume_workflow_calls"
! grep -Fq 'HARNESS_RUN_ID: unbound variable' "$tmp_dir/run-resume.err"

PATH="$stub_bin:$PATH" \
  "$repo_root/simulation/vm/simulate.sh" --env "$env_file" audit-state >"$tmp_dir/audit-state.out"
grep -Fxq 'audit-state: ok' "$tmp_dir/audit-state.out"
! grep -Fq 'run-id=' "$tmp_dir/audit-state.out"
! grep -Fq 'set-id=' "$tmp_dir/audit-state.out"
! grep -Fq 'evidence=' "$tmp_dir/audit-state.out"

PATH="$stub_bin:$PATH" \
  "$repo_root/simulation/vm/simulate.sh" --env "$env_file" status >"$tmp_dir/status.out"
grep -Fq 'status: initialized' "$tmp_dir/status.out"
grep -Fq "Run ID        $run_id" "$tmp_dir/status.out"
grep -Fq "VM set        $vm_set_id" "$tmp_dir/status.out"
grep -Fq "Project       loopforge-vm-$vm_set_id" "$tmp_dir/status.out"
grep -Fq 'Target SSH' "$tmp_dir/status.out"
grep -Fq 'Login accounts' "$tmp_dir/status.out"
! grep -Fq 'VM state' "$tmp_dir/status.out"
! grep -Fq 'Libvirt' "$tmp_dir/status.out"

if PATH="$stub_bin:$PATH" "$repo_root/simulation/vm/simulate.sh" \
  --env "$env_file" start >"$tmp_dir/start-fail.out" 2>&1; then
  printf 'start must fail when the VM set marker is missing\n' >&2
  exit 1
fi
grep -Fxq 'start: failed reason=vm-set-start' "$tmp_dir/start-fail.out"
grep -Eq '^log=.*/start-[0-9]{8}T[0-9]{6}Z\.log$' "$tmp_dir/start-fail.out"
grep -Eq '^evidence=.*/start-harness-[0-9]{8}T[0-9]{6}Z\.json$' "$tmp_dir/start-fail.out"
start_fail_log="$(sed -n 's/^log=//p' "$tmp_dir/start-fail.out")"
grep -Fq 'ERROR: Missing VM-set marker:' "$start_fail_log"

if PATH="$stub_bin:$PATH" "$repo_root/simulation/vm/simulate.sh" \
  --env "$env_file" reboot --role gerrit >"$tmp_dir/reboot-fail.out" 2>&1; then
  printf 'reboot must fail when the VM set marker is missing\n' >&2
  exit 1
fi
grep -Fq 'Simulation effective inputs are pending; run start first' "$tmp_dir/reboot-fail.out"
! grep -Fq 'log=' "$tmp_dir/reboot-fail.out"
! grep -Fq 'evidence=' "$tmp_dir/reboot-fail.out"

"$repo_root/simulation/vm/simulate.sh" --env "$create_die_env_file" init-run \
  >"$tmp_dir/init-run-create-die.out"
if PATH="$stub_bin:$PATH" "$repo_root/simulation/vm/simulate.sh" \
  --env "$create_die_env_file" create >"$tmp_dir/create-die.out" 2>&1; then
  printf 'create must fail when VM_BASE_IMAGE_PATH is missing\n' >&2
  exit 1
fi
grep -Fxq 'create: failed reason=vm-set-create' "$tmp_dir/create-die.out"
grep -Eq '^log=.*/create-[0-9]{8}T[0-9]{6}Z\.log$' "$tmp_dir/create-die.out"
grep -Eq '^evidence=.*/create-harness-[0-9]{8}T[0-9]{6}Z\.json$' "$tmp_dir/create-die.out"
[ "$(grep -Fc 'create: failed reason=vm-set-create' "$tmp_dir/create-die.out")" -eq 1 ]
create_die_log="$(sed -n 's/^log=//p' "$tmp_dir/create-die.out")"
[ -s "$create_die_log" ]
grep -Fq 'ERROR: VM_BASE_IMAGE_PATH does not exist:' "$create_die_log"
