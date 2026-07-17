#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
run_id="vm-set-ownership-$$"
vm_set_id="ownership-$$"
resource_namespace="loopforge-vm-$vm_set_id"
generated_root="$repo_root/generated/simulation/vm"
trap 'rm -rf "$tmp_dir" "$generated_root/$run_id" "$generated_root/sets/$vm_set_id"; rm -f "$generated_root/locks/$vm_set_id.lock"' EXIT

env_file="$tmp_dir/harness.env"
audit_out="$tmp_dir/audit.out"
audit_err="$tmp_dir/audit.err"
stub_bin="$tmp_dir/bin"
mkdir -p "$stub_bin"

sed \
  -e "s/^HARNESS_RUN_ID=.*/HARNESS_RUN_ID=$run_id/" \
  -e "s/^HARNESS_SET_ID=.*/HARNESS_SET_ID=$vm_set_id/" \
  "$repo_root/simulation/vm/examples/vm.env.example" >"$env_file"

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

vm_set_dir="$generated_root/sets/$vm_set_id"
marker="$vm_set_dir/.loopforge-vm-set.env"
mkdir -p "$vm_set_dir"
touch "$vm_set_dir/unowned-content"

if PATH="$stub_bin:$PATH" "$repo_root/simulation/vm/simulate.sh" --env "$env_file" audit-state >"$audit_out" 2>"$audit_err"; then
  printf 'audit-state must fail when VM-set directory has no marker\n' >&2
  exit 1
fi
grep -Fq 'unowned content exists before VM-set creation' "$audit_err"
rm -f "$vm_set_dir/unowned-content"

cat >"$marker" <<EOF
mode=vm-simulation
set_id=$vm_set_id
resource_namespace=$resource_namespace
repo_root=$repo_root
vm_set_dir=$vm_set_dir
libvirt_uri=qemu:///system
domain_prefix=$resource_namespace-
network_name=$resource_namespace-net
storage_pool_name=$resource_namespace-images
seed_pool_name=$resource_namespace-seed
baseline_snapshot_name=loopforge-clean-baseline
ownership_schema_version=1
EOF
chmod 0600 "$marker"

if PATH="$stub_bin:$PATH" "$repo_root/simulation/vm/simulate.sh" --env "$env_file" audit-state >"$audit_out" 2>"$audit_err"; then
  printf 'audit-state must fail for a legacy VM-set ownership marker\n' >&2
  exit 1
fi
grep -Fq 'Incompatible legacy VM set' "$audit_err"

sed -i 's/^ownership_schema_version=1$/ownership_schema_version=6/' "$marker"
cat >>"$marker" <<EOF
base_image=not-created
base_image_fingerprint=not-created
disk_size=20G
storage_pool_target=$vm_set_dir/libvirt/disks
disk_ownership=libvirt-managed
EOF

PATH="$stub_bin:$PATH" "$repo_root/simulation/vm/simulate.sh" --env "$env_file" audit-state >"$audit_out"
grep -Fxq 'audit-state: ok' "$audit_out"

sed -i 's/^set_id=.*/set_id=wrong-set/' "$marker"
if PATH="$stub_bin:$PATH" "$repo_root/simulation/vm/simulate.sh" --env "$env_file" audit-state >"$audit_out" 2>"$audit_err"; then
  printf 'audit-state must fail when VM-set marker identity mismatches\n' >&2
  exit 1
fi
grep -Fq 'VM-set marker set_id does not match selected runtime config' "$audit_err"

cat >"$marker" <<EOF
mode=vm-simulation
set_id=$vm_set_id
resource_namespace=$resource_namespace
repo_root=$repo_root
vm_set_dir=$vm_set_dir
libvirt_uri=qemu:///system
domain_prefix=$resource_namespace-
network_name=$resource_namespace-net
storage_pool_name=$resource_namespace-images
seed_pool_name=$resource_namespace-seed
baseline_snapshot_name=loopforge-clean-baseline
ownership_schema_version=1
EOF
chmod 0600 "$marker"
if PATH="$stub_bin:$PATH" \
  "$repo_root/simulation/vm/simulate.sh" --env "$env_file" destroy \
  >"$tmp_dir/destroy-legacy.out" 2>&1; then
  printf 'destroy must reject a legacy VM-set marker\n' >&2
  exit 1
fi
destroy_log="$(sed -n 's/^log=//p' "$tmp_dir/destroy-legacy.out" | tail -1)"
[ -n "$destroy_log" ]
grep -Fq 'Incompatible legacy VM set' "$destroy_log"
