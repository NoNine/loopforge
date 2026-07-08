#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
run_id="vm-libvirt-preflight-$$"
vm_set_id="libvirt-preflight-$$"
generated_root="$repo_root/generated/simulation/vm"
trap 'rm -rf "$tmp_dir" "$generated_root/$run_id" "$generated_root/vm-sets/$vm_set_id"' EXIT

env_file="$tmp_dir/harness.env"
preflight_out="$tmp_dir/preflight.out"
preflight_err="$tmp_dir/preflight.err"
stub_bin="$tmp_dir/bin"
mkdir -p "$stub_bin"

sed \
  -e "s/^HARNESS_RUN_ID=.*/HARNESS_RUN_ID=$run_id/" \
  -e "s/^LOOPFORGE_VM_SET_ID=.*/LOOPFORGE_VM_SET_ID=$vm_set_id/" \
  "$repo_root/simulation/vm/example.env" >"$env_file"

cat >"$stub_bin/virsh" <<'STUB'
#!/usr/bin/env bash
if [ "${1:-}" = "-c" ]; then
  shift 2
fi
case "${1:-}" in
  uri)
    printf 'qemu:///system\n'
    ;;
  list)
    printf '\n'
    ;;
  net-list)
    printf 'default\n'
    ;;
  pool-list)
    printf 'images\n'
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

PATH="$stub_bin:$PATH" "$repo_root/simulation/vm/simulate.sh" --env "$env_file" preflight >"$preflight_out"

grep -Fxq 'preflight: ok mode=vm-simulation libvirt=ok' "$preflight_out"
! grep -Fq 'run-id=' "$preflight_out"
! grep -Fq 'vm-set=' "$preflight_out"
! grep -Fq 'uri=' "$preflight_out"
! grep -Fq 'log=' "$preflight_out"
! grep -Fq 'evidence=' "$preflight_out"
preflight_log="$(find "$generated_root/$run_id/host/logs/harness" -name 'preflight-*.log' -print | sort | tail -1)"
grep -Fq 'libvirt=ok uri=qemu:///system' "$preflight_log"
grep -Fq 'vm-set=absent vm-resources=absent' "$preflight_log"
preflight_evidence="$(find "$generated_root/$run_id/host/evidence/harness" -name 'preflight-harness-*.json' -print | sort | tail -1)"
grep -Eq "\"bounded_log\": \"$repo_root/generated/simulation/vm/$run_id/host/logs/harness/preflight-[0-9TZ]+\\.log\"" "$preflight_evidence"

cat >"$stub_bin/virsh" <<'STUB'
#!/usr/bin/env bash
printf 'stub virsh failure\n' >&2
exit 1
STUB
chmod +x "$stub_bin/virsh"
if PATH="$stub_bin:$PATH" "$repo_root/simulation/vm/simulate.sh" --env "$env_file" preflight >"$preflight_out" 2>"$preflight_err"; then
  printf 'preflight must fail when virsh cannot inspect libvirt\n' >&2
  exit 1
fi
grep -Fq 'preflight: failed reason=libvirt-or-vm-set-preflight' "$preflight_out"
grep -Eq "log=$repo_root/generated/simulation/vm/$run_id/host/logs/harness/preflight-[0-9TZ]+\\.log" "$preflight_out"
grep -Eq "evidence=$repo_root/generated/simulation/vm/$run_id/host/evidence/harness/preflight-harness-[0-9TZ]+\\.json" "$preflight_out"
failure_evidence="$(find "$generated_root/$run_id/host/evidence/harness" -name 'preflight-harness-*.json' -print | sort | tail -1)"
grep -Eq "\"bounded_log\": \"$repo_root/generated/simulation/vm/$run_id/host/logs/harness/preflight-[0-9TZ]+\\.log\"" "$failure_evidence"
