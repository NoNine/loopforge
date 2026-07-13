#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
run_id="vm-summary-$$"
vm_set_id="summary-$$"
fresh_run_id="vm-summary-fresh-$$"
fresh_vm_set_id="summary-fresh-$$"
generated_root="$repo_root/generated/simulation/vm"
trap 'rm -rf "$tmp_dir" "$generated_root/$run_id" "$generated_root/vm-sets/$vm_set_id" "$generated_root/$fresh_run_id" "$generated_root/vm-sets/$fresh_vm_set_id"' EXIT

env_file="$tmp_dir/harness.env"
fresh_env_file="$tmp_dir/harness-fresh.env"
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
  -e "s/^LOOPFORGE_VM_SET_ID=.*/LOOPFORGE_VM_SET_ID=$vm_set_id/" \
  "$repo_root/simulation/vm/examples/vm.env.example" >"$env_file"

sed \
  -e "s/^HARNESS_RUN_ID=.*/HARNESS_RUN_ID=$fresh_run_id/" \
  -e "s/^LOOPFORGE_VM_SET_ID=.*/LOOPFORGE_VM_SET_ID=$fresh_vm_set_id/" \
  "$repo_root/simulation/vm/examples/vm.env.example" >"$fresh_env_file"

PATH="$stub_bin:$PATH" HARNESS_TEST_WORKFLOW_CALLS="$fresh_workflow_calls" \
  "$repo_root/simulation/vm/simulate.sh" --env "$fresh_env_file" run \
  >"$tmp_dir/run-fresh.out" 2>"$tmp_dir/run-fresh.err"
grep -Fxq "run: mode=fresh run-id=$fresh_run_id vm-set=$fresh_vm_set_id" "$tmp_dir/run-fresh.out"
grep -Fxq '==> preflight' "$tmp_dir/run-fresh.out"
grep -Fxq '==> init-run' "$tmp_dir/run-fresh.out"
grep -Fxq '==> create' "$tmp_dir/run-fresh.out"
grep -Fxq '==> status' "$tmp_dir/run-fresh.out"
awk '
  $0 == "==> preflight" { preflight = NR }
  $0 == "==> init-run" { init = NR }
  $0 == "==> create" { create = NR }
  $0 == "==> up" { up = NR }
  $0 == "==> status" { status = NR }
  END { exit !(preflight && init && create && up && status && preflight < init && init < create && create < up && up < status) }
' "$tmp_dir/run-fresh.out"
grep -Fxq 'status' "$fresh_workflow_calls"

PATH="$stub_bin:$PATH" \
  "$repo_root/simulation/vm/simulate.sh" --env "$env_file" preflight >"$tmp_dir/preflight.out"
grep -Fxq 'preflight: ok mode=vm-simulation libvirt=ok' "$tmp_dir/preflight.out"
! grep -Fq 'log=' "$tmp_dir/preflight.out"
! grep -Fq 'evidence=' "$tmp_dir/preflight.out"
! grep -Fq 'vm-resources=' "$tmp_dir/preflight.out"

"$repo_root/simulation/vm/simulate.sh" --env "$env_file" init-run >"$tmp_dir/init-run.out"
grep -Fxq "init-run: ok run-id=$run_id" "$tmp_dir/init-run.out"
! grep -Fq 'vm-set=' "$tmp_dir/init-run.out"
! grep -Fq 'evidence=' "$tmp_dir/init-run.out"

PATH="$stub_bin:$PATH" HARNESS_TEST_WORKFLOW_CALLS="$resume_workflow_calls" \
  "$repo_root/simulation/vm/simulate.sh" --env "$env_file" run \
  >"$tmp_dir/run-resume.out" 2>"$tmp_dir/run-resume.err"
grep -Fxq "run: mode=resume run-id=$run_id vm-set=$vm_set_id" "$tmp_dir/run-resume.out"
grep -Fxq '==> create' "$tmp_dir/run-resume.out"
grep -Fxq '==> status' "$tmp_dir/run-resume.out"
awk '
  $0 == "==> create" { create = NR }
  $0 == "==> up" { up = NR }
  $0 == "==> status" { status = NR }
  END { exit !(create && up && status && create < up && up < status) }
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
! grep -Fq 'vm-set=' "$tmp_dir/audit-state.out"
! grep -Fq 'evidence=' "$tmp_dir/audit-state.out"

PATH="$stub_bin:$PATH" \
  "$repo_root/simulation/vm/simulate.sh" --env "$env_file" status >"$tmp_dir/status.out"
grep -Fq 'status: initialized' "$tmp_dir/status.out"
grep -Fq "Run ID        $run_id" "$tmp_dir/status.out"
grep -Fq "VM set        $vm_set_id" "$tmp_dir/status.out"
grep -Fq "Project       loopforge-vm-$run_id-$vm_set_id" "$tmp_dir/status.out"
grep -Fq 'Target SSH' "$tmp_dir/status.out"
grep -Fq 'Login accounts' "$tmp_dir/status.out"
! grep -Fq 'VM state' "$tmp_dir/status.out"
! grep -Fq 'Libvirt' "$tmp_dir/status.out"
