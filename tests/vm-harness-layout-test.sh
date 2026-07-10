#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
vm_root="$repo_root/simulation/vm"

reject_in_file() {
  local file pattern message
  file="${1:?file required}"
  pattern="${2:?pattern required}"
  message="${3:?message required}"
  if grep -Eq -- "$pattern" "$file"; then
    printf '%s: %s\n' "$message" "${file#$repo_root/}" >&2
    exit 1
  fi
}

require_in_file() {
  local file pattern message
  file="${1:?file required}"
  pattern="${2:?pattern required}"
  message="${3:?message required}"
  if ! grep -Eq -- "$pattern" "$file"; then
    printf '%s: %s\n' "$message" "${file#$repo_root/}" >&2
    exit 1
  fi
}

[ -d "$vm_root" ] || {
  printf 'Missing VM simulation directory\n' >&2
  exit 1
}

mapfile -t vm_impl_files < <(
  find "$vm_root" -type f \
    \( -name 'simulate.sh' -o -path "$vm_root/lib/*.sh" -o -path "$vm_root/tools/*.sh" \) |
    sort
)

[ -x "$vm_root/tools/cleanup-libvirt-resources.sh" ] || {
  printf 'Missing executable VM libvirt resource cleanup tool\n' >&2
  exit 1
}
[ -x "$repo_root/tests/vm-harness-m5-lifecycle-test.sh" ] || {
  printf 'Missing executable VM M5 lifecycle test\n' >&2
  exit 1
}

if [ -f "$vm_root/simulate.sh" ]; then
  require_in_file "$vm_root/simulate.sh" 'simulation/lib|/lib/' \
    'VM public CLI must source shared or VM-local helper libraries'
fi

for file in "${vm_impl_files[@]}"; do
  reject_in_file "$file" 'simulation/docker/lib|/docker/lib/' \
    'VM harness implementation must not source Docker harness internals'
  reject_in_file "$file" '(^|[^[:alnum:]_-])docker-compose([^[:alnum:]_-]|$)|(^|[^[:alnum:]_-])docker[[:space:]]+compose([^[:alnum:]_-]|$)' \
    'VM harness implementation must not use Docker Compose'
  reject_in_file "$file" 'gerrit-target|jenkins-controller-target|jenkins-agent-target|bundle-factory-target|ldap-target' \
    'VM harness implementation must not depend on Docker service names'
  reject_in_file "$file" 'generated/simulation/vm/[^[:space:]]*/target/artifacts/staging|target/artifacts/staging' \
    'VM harness implementation must not use generated target artifact staging sidebands'
  reject_in_file "$file" '(^|[^[:alnum:]_-])virsh[[:space:]]+console([^[:alnum:]_-]|$)' \
    'VM harness implementation must not use libvirt console as checkpoint control plane'
  reject_in_file "$file" '(^|[^[:alnum:]_-])(guestfish|guestmount|virt-copy-in|virt-copy-out|virt-customize|virt-rescue|qemu-nbd)([^[:alnum:]_-]|$)' \
    'VM harness implementation must not edit guest disks or images for checkpoint work'
  reject_in_file "$file" 'cloud-init[^[:cntrl:]]*(stage-artifacts|configure-role|validate-role|configure-integration|validate-integration|prove-integration)' \
    'VM harness implementation must not use post-baseline cloud-init for checkpoint work'
  reject_in_file "$file" 'print_command_failure[^[:cntrl:]]*basename[[:space:]]+"?\$\(?(log|evidence)' \
    'VM harness failure summaries must print full log and evidence paths'
done
