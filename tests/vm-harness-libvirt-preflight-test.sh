#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
run_id="vm-libvirt-preflight-$$"
vm_set_id="preflight-$$"
generated_root="$repo_root/generated/simulation/vm"
trap 'rm -rf "$tmp_dir" "$generated_root/$run_id" "$generated_root/sets/$vm_set_id"; rm -f "$generated_root/locks/$vm_set_id.lock"' EXIT

env_file="$tmp_dir/harness.env"
preflight_out="$tmp_dir/preflight.out"
preflight_err="$tmp_dir/preflight.err"
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
! grep -Fq 'set-id=' "$preflight_out"
! grep -Fq 'uri=' "$preflight_out"
! grep -Fq 'log=' "$preflight_out"
! grep -Fq 'evidence=' "$preflight_out"
[ ! -e "$generated_root/$run_id" ] || {
  printf 'read-only preflight unexpectedly created run state\n' >&2
  exit 1
}

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
! grep -Fq 'log=' "$preflight_out"
! grep -Fq 'evidence=' "$preflight_out"
[ ! -e "$generated_root/$run_id" ] || {
  printf 'failed read-only preflight unexpectedly created run state\n' >&2
  exit 1
}
