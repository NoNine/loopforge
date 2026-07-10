#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
run_id="vm-set-ownership-$$"
vm_set_id="ownership-$$"
project_name="loopforge-vm-$run_id-$vm_set_id"
generated_root="$repo_root/generated/simulation/vm"
trap 'rm -rf "$tmp_dir" "$generated_root/$run_id" "$generated_root/vm-sets/$vm_set_id"' EXIT

env_file="$tmp_dir/harness.env"
audit_out="$tmp_dir/audit.out"
audit_err="$tmp_dir/audit.err"
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

PATH="$stub_bin:$PATH" "$repo_root/simulation/vm/simulate.sh" --env "$env_file" init-run >/dev/null
PATH="$stub_bin:$PATH" "$repo_root/simulation/vm/simulate.sh" --env "$env_file" audit-state >"$audit_out"
grep -Fxq 'audit-state: ok' "$audit_out"
audit_log="$(find "$generated_root/$run_id/host/logs/harness" -name 'audit-state-*.log' -print | sort | tail -1)"
grep -Fq 'vm-set=absent vm-resources=absent' "$audit_log"
audit_evidence="$(find "$generated_root/$run_id/host/evidence/harness" -name 'audit-state-harness-*.json' -print | sort | tail -1)"
grep -Eq "\"bounded_log\": \"$repo_root/generated/simulation/vm/$run_id/host/logs/harness/audit-state-[0-9TZ]+\\.log\"" "$audit_evidence"

vm_set_dir="$generated_root/vm-sets/$vm_set_id"
marker="$vm_set_dir/.loopforge-vm-set.env"
mkdir -p "$vm_set_dir"

if PATH="$stub_bin:$PATH" "$repo_root/simulation/vm/simulate.sh" --env "$env_file" audit-state >"$audit_out" 2>"$audit_err"; then
  printf 'audit-state must fail when VM-set directory has no marker\n' >&2
  exit 1
fi
grep -Fq 'missing VM-set marker' "$audit_err"

cat >"$marker" <<EOF
mode=vm-simulation
vm_set_id=$vm_set_id
project_name=$project_name
repo_root=$repo_root
vm_set_dir=$vm_set_dir
libvirt_uri=qemu:///system
domain_prefix=$project_name-
network_name=$project_name-net
storage_pool_name=$project_name-images
seed_pool_name=$project_name-seed
baseline_snapshot_name=loopforge-clean-baseline
ownership_schema_version=1
EOF
chmod 0600 "$marker"

if PATH="$stub_bin:$PATH" "$repo_root/simulation/vm/simulate.sh" --env "$env_file" audit-state >"$audit_out" 2>"$audit_err"; then
  printf 'audit-state must fail for a legacy VM-set ownership marker\n' >&2
  exit 1
fi
grep -Fq "Incompatible legacy VM set $vm_set_id" "$audit_err"
grep -Fq 'Select a fresh HARNESS_RUN_ID and LOOPFORGE_VM_SET_ID' "$audit_err"
grep -Fq 'M5 down/destroy cleanup' "$audit_err"

sed -i 's/^ownership_schema_version=1$/ownership_schema_version=5/' "$marker"
cat >>"$marker" <<EOF
base_image=not-created
base_image_fingerprint=not-created
disk_size=20G
storage_pool_target=$vm_set_dir/libvirt/disks
disk_ownership=libvirt-managed
EOF

PATH="$stub_bin:$PATH" "$repo_root/simulation/vm/simulate.sh" --env "$env_file" audit-state >"$audit_out"
grep -Fxq 'audit-state: ok' "$audit_out"
audit_log="$(find "$generated_root/$run_id/host/logs/harness" -name 'audit-state-*.log' -print | sort | tail -1)"
grep -Fq 'vm-set=owned vm-resources=absent' "$audit_log"
audit_evidence="$(find "$generated_root/$run_id/host/evidence/harness" -name 'audit-state-harness-*.json' -print | sort | tail -1)"
grep -Eq "\"bounded_log\": \"$repo_root/generated/simulation/vm/$run_id/host/logs/harness/audit-state-[0-9TZ]+\\.log\"" "$audit_evidence"

sed -i 's/^vm_set_id=.*/vm_set_id=wrong-set/' "$marker"
if PATH="$stub_bin:$PATH" "$repo_root/simulation/vm/simulate.sh" --env "$env_file" audit-state >"$audit_out" 2>"$audit_err"; then
  printf 'audit-state must fail when VM-set marker identity mismatches\n' >&2
  exit 1
fi
grep -Fq 'VM-set marker vm_set_id does not match selected runtime config' "$audit_err"
