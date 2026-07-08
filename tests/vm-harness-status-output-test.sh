#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
run_id="vm-status-output-$$"
vm_set_id="status-output-$$"
generated_root="$repo_root/generated/simulation/vm"
trap 'rm -rf "$tmp_dir" "$generated_root/$run_id" "$generated_root/vm-sets/$vm_set_id"' EXIT

env_file="$tmp_dir/harness.env"
status_out="$tmp_dir/status.out"
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

sed \
  -e "s/^HARNESS_RUN_ID=.*/HARNESS_RUN_ID=$run_id/" \
  -e "s/^LOOPFORGE_VM_SET_ID=.*/LOOPFORGE_VM_SET_ID=$vm_set_id/" \
  "$repo_root/simulation/vm/example.env" >"$env_file"

"$repo_root/simulation/vm/simulate.sh" --env "$env_file" init-run >/dev/null
PATH="$stub_bin:$PATH" "$repo_root/simulation/vm/simulate.sh" --env "$env_file" status >"$status_out"

grep -Fq 'status: initialized' "$status_out"
grep -Fq "Run ID        $run_id" "$status_out"
grep -Fq "VM set        $vm_set_id" "$status_out"
grep -Fq "Project       loopforge-vm-$run_id-$vm_set_id" "$status_out"
grep -Fq 'Gerrit URL    pending-role-configuration' "$status_out"
grep -Fq 'Jenkins URL   pending-role-configuration' "$status_out"
grep -Fq 'Target SSH' "$status_out"
grep -Fq 'Role                User          Host             State' "$status_out"
grep -Fq 'gerrit              ci-operator   pending-up       pending-up' "$status_out"
grep -Fq 'jenkins-controller  ci-operator   pending-up       pending-up' "$status_out"
grep -Fq 'jenkins-agent       ci-operator   pending-up       pending-up' "$status_out"
grep -Fq 'Login accounts' "$status_out"
grep -Fq 'System              Username        Password              Purpose' "$status_out"
grep -Fq 'Gerrit              gerrit-admin    admin-password        Gerrit admin user' "$status_out"
grep -Fq 'Jenkins             jenkins-admin   admin-password        Jenkins admin user' "$status_out"
grep -Fq 'Gerrit              test-user       test-password         Test/change workflow user' "$status_out"
tail -1 "$status_out" | grep -Fq -- '------------------  --------------  --------------------  ----------------------------------------'
! grep -Fq 'VM state' "$status_out"
! grep -Fq 'Libvirt' "$status_out"
! grep -Fq 'vm-resources=' "$status_out"
! grep -Fq 'libvirt-uri=' "$status_out"
! grep -Fq 'VM domains' "$status_out"
! grep -Fq 'domain=' "$status_out"
