#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

. "$repo_root/simulation/lib/common.sh"
. "$repo_root/simulation/lib/permissions.sh"
. "$repo_root/simulation/vm/lib/ssh.sh"

VM_OPERATOR_SSH_TIMEOUT_SECONDS=5
VM_OPERATOR_SSH_POLL_SECONDS=1
boot_id=before-reboot
calls="$tmp_dir/calls.log"

vm_ssh_run_machine() {
  local machine script
  machine="$1"
  script="$2"
  printf 'run machine=%s script=%s\n' "$machine" "$script" >>"$calls"
  case "$script" in
    *'/proc/sys/kernel/random/boot_id'*) printf '%s\n' "$boot_id" ;;
    *'systemctl reboot'*) return 255 ;;
  esac
}
vm_ssh_wait_unavailable() { printf 'unavailable %s\n' "$1" >>"$calls"; }
vm_ssh_wait_system_ready() {
  printf 'system-ready %s\n' "$1" >>"$calls"
  boot_id=after-reboot
}
vm_ssh_verify_known_host() { printf 'known-host %s\n' "$1" >>"$calls"; }

vm_ssh_reboot_machine gerrit >"$tmp_dir/out"
grep -Fq 'reboot=ready machine=gerrit boot-id-before=before-reboot boot-id-after=after-reboot ssh-return=ready system=running' "$tmp_dir/out"
grep -Fxq 'unavailable gerrit' "$calls"
grep -Fxq 'system-ready gerrit' "$calls"
grep -Fxq 'known-host gerrit' "$calls"

boot_id=same
vm_ssh_wait_system_ready() { printf 'system-ready %s\n' "$1" >>"$calls"; }
set +e
(vm_ssh_reboot_machine jenkins-agent) >"$tmp_dir/fail.out" 2>"$tmp_dir/fail.err"
rc=$?
set -e
if [ "$rc" -eq 0 ]; then
  printf 'reboot must reject an unchanged boot ID\n' >&2
  exit 1
fi
grep -Fq 'Guest boot ID did not change after reboot: jenkins-agent' "$tmp_dir/fail.err"

stub_bin="$tmp_dir/bin"
mkdir -p "$stub_bin"
cat >"$stub_bin/ssh" <<'STUB'
#!/usr/bin/env bash
printf '@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@\n' >&2
printf '@    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @\n' >&2
printf '@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@\n' >&2
printf 'Host key verification failed.\n' >&2
exit 255
STUB
chmod +x "$stub_bin/ssh"

vm_ssh_wait_host() {
  printf '192.168.126.3\n'
}
VM_OPERATOR_SSH_TIMEOUT_SECONDS=1
VM_OPERATOR_SSH_POLL_SECONDS=1
VM_OPERATOR_USER=ci-operator
HARNESS_TARGET_SSH_IDENTITY_FILE="$tmp_dir/ci-operator"
HARNESS_TARGET_SSH_KNOWN_HOSTS_FILE="$tmp_dir/known_hosts"
touch "$HARNESS_TARGET_SSH_IDENTITY_FILE" "$HARNESS_TARGET_SSH_KNOWN_HOSTS_FILE"
set +e
PATH="$stub_bin:$PATH" vm_ssh_wait_ready bundle-factory >"$tmp_dir/ssh-ready.out" 2>"$tmp_dir/ssh-ready.err"
rc=$?
set -e
if [ "$rc" -eq 0 ]; then
  printf 'SSH readiness must fail when host-key verification fails\n' >&2
  exit 1
fi
grep -Fq 'Last SSH readiness error for bundle-factory (192.168.126.3):' "$tmp_dir/ssh-ready.err"
grep -Fq 'REMOTE HOST IDENTIFICATION HAS CHANGED' "$tmp_dir/ssh-ready.err"
grep -Fq 'Host key verification failed.' "$tmp_dir/ssh-ready.err"
grep -Fq 'Timed out waiting for target OS SSH on bundle-factory (192.168.126.3)' "$tmp_dir/ssh-ready.err"
