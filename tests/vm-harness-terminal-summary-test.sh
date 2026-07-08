#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
run_id="vm-summary-$$"
vm_set_id="summary-$$"
generated_root="$repo_root/generated/simulation/vm"
trap 'rm -rf "$tmp_dir" "$generated_root/$run_id" "$generated_root/vm-sets/$vm_set_id"' EXIT

env_file="$tmp_dir/harness.env"
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
  "$repo_root/simulation/vm/example.env" >"$env_file"

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
grep -Fq 'Login accounts' "$tmp_dir/status.out"
