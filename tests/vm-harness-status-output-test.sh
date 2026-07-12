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

project_name="loopforge-vm-$run_id-$vm_set_id"
machine_mac() {
  local machine digest
  machine="${1:?machine required}"
  digest="$(printf '%s:%s:%s\n' "$project_name" "$vm_set_id" "$machine" |
    sha256sum | awk '{print $1}')"
  printf '52:54:00:%s:%s:%s\n' \
    "${digest:0:2}" "${digest:2:2}" "${digest:4:2}"
}
gerrit_mac="$(machine_mac gerrit)"
jenkins_controller_mac="$(machine_mac jenkins-controller)"

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
    case "${HARNESS_TEST_VM_DOMSTATE:-missing}" in
      running) printf 'running\n' ;;
      missing) exit 1 ;;
      *) printf '%s\n' "$HARNESS_TEST_VM_DOMSTATE" ;;
    esac
    ;;
  net-dhcp-leases)
    mac=""
    while [ "$#" -gt 0 ]; do
      if [ "$1" = "--mac" ]; then
        shift
        mac="${1:-}"
        break
      fi
      shift
    done
    case "$mac" in
      "$HARNESS_TEST_GERRIT_MAC")
        printf ' Expiry Time           MAC address          Protocol   IP address           Hostname   Client ID or DUID\n'
        printf ' 2026-07-12 09:00:00   %s   ipv4       192.168.126.5/24    gerrit     -\n' "$mac"
        ;;
      "$HARNESS_TEST_JENKINS_CONTROLLER_MAC")
        printf ' Expiry Time           MAC address          Protocol   IP address           Hostname             Client ID or DUID\n'
        printf ' 2026-07-12 09:00:00   %s   ipv4       192.168.126.6/24    jenkins-controller -\n' "$mac"
        ;;
      *)
        exit 1
        ;;
    esac
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
  "$repo_root/simulation/vm/examples/vm.env.example" >"$env_file"

"$repo_root/simulation/vm/simulate.sh" --env "$env_file" init-run >/dev/null
PATH="$stub_bin:$PATH" "$repo_root/simulation/vm/simulate.sh" --env "$env_file" status >"$status_out"

grep -Fq 'status: initialized' "$status_out"
grep -Fq "Run ID        $run_id" "$status_out"
grep -Fq "VM set        $vm_set_id" "$status_out"
grep -Fq "Project       loopforge-vm-$run_id-$vm_set_id" "$status_out"
grep -Fq 'Gerrit URL    pending-up' "$status_out"
grep -Fq 'Jenkins URL   pending-up' "$status_out"
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

HARNESS_TEST_VM_DOMSTATE=running \
HARNESS_TEST_GERRIT_MAC="$gerrit_mac" \
HARNESS_TEST_JENKINS_CONTROLLER_MAC="$jenkins_controller_mac" \
  PATH="$stub_bin:$PATH" "$repo_root/simulation/vm/simulate.sh" --env "$env_file" status >"$status_out"

grep -Fq 'status: running' "$status_out"
grep -Fq 'Gerrit URL    http://192.168.126.5:8080/' "$status_out"
grep -Fq 'Jenkins URL   http://192.168.126.6:8080/login' "$status_out"
