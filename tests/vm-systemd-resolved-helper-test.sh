#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

helper="$repo_root/simulation/vm/tools/configure-systemd-resolved.sh"
stub_bin="$tmp_dir/bin"
stub_state="$tmp_dir/state"
mkdir -p "$stub_bin" "$stub_state"

cat >"$stub_bin/virsh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = "-c" ]; then
  shift 2
fi
cmd="${1:-}"
shift || true
case "$cmd" in
  net-info)
    network="${1:?network required}"
    printf '%s\n' "$network" >"${VM_TEST_STATE:?}/last-network"
    if [ "${VM_TEST_NET_MISSING:-0}" = 1 ]; then
      exit 1
    fi
    if [ "${VM_TEST_NET_INACTIVE:-0}" = 1 ]; then
      printf 'Active: no\n'
    else
      printf 'Active: yes\n'
    fi
    ;;
  net-dumpxml)
    network="${1:?network required}"
    printf '%s\n' "$network" >"${VM_TEST_STATE:?}/last-dumpxml-network"
    cat <<XML
<network>
  <name>$network</name>
  <bridge name='lf-test123'/>
  <ip address='192.168.126.1' netmask='255.255.255.0'/>
</network>
XML
    ;;
  *)
    printf 'unexpected virsh command: %s %s\n' "$cmd" "$*" >&2
    exit 1
    ;;
esac
STUB
chmod +x "$stub_bin/virsh"

cat >"$stub_bin/dig" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
name="${@: -2:1}"
case "$name" in
  gerrit.example.test) printf '192.168.126.5\n' ;;
  jenkins-controller.example.test) printf '192.168.126.6\n' ;;
  *) exit 1 ;;
esac
STUB
chmod +x "$stub_bin/dig"

cat >"$stub_bin/getent" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" != ahostsv4 ]; then
  /usr/bin/getent "$@"
  exit $?
fi
case "${VM_TEST_HOST_DNS:-unresolved}:${2:-}" in
  ready:gerrit.example.test) printf '192.168.126.5 gerrit.example.test\n' ;;
  ready:jenkins-controller.example.test) printf '192.168.126.6 jenkins-controller.example.test\n' ;;
  mismatch:gerrit.example.test) printf '192.168.126.55 gerrit.example.test\n' ;;
  mismatch:jenkins-controller.example.test) printf '192.168.126.66 jenkins-controller.example.test\n' ;;
  *) exit 2 ;;
esac
STUB
chmod +x "$stub_bin/getent"

cat >"$stub_bin/systemd-resolve" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${VM_TEST_STATE:?}/systemd-resolve.calls"
STUB
chmod +x "$stub_bin/systemd-resolve"

cat >"$stub_bin/sudo" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
if [ "${VM_TEST_SUDO_FAIL:-0}" = 1 ]; then
  exit 1
fi
if [ "${1:-}" = "-n" ] && [ "${2:-}" = true ]; then
  printf 'sudo-check\n' >>"${VM_TEST_STATE:?}/sudo.calls"
  exit 0
fi
if [ "${1:-}" = "-n" ]; then
  shift
fi
printf 'sudo-run %s\n' "$*" >>"${VM_TEST_STATE:?}/sudo.calls"
"$@"
STUB
chmod +x "$stub_bin/sudo"

env_file="$tmp_dir/vm.env"
sed \
  -e 's/^HARNESS_RUN_ID=.*/HARNESS_RUN_ID=resolved-test/' \
  -e 's/^LOOPFORGE_VM_SET_ID=.*/LOOPFORGE_VM_SET_ID=resolved-set/' \
  "$repo_root/simulation/vm/examples/vm.env.example" >"$env_file"

PATH="$stub_bin:$PATH" VM_TEST_STATE="$stub_state" \
  "$helper" --env "$env_file" --dry-run >"$tmp_dir/dry-run.out"
grep -Fq 'selected-network=loopforge-vm-resolved-test-resolved-set-net' "$tmp_dir/dry-run.out"
grep -Fq 'bridge=lf-test123' "$tmp_dir/dry-run.out"
grep -Fq 'gateway=192.168.126.1' "$tmp_dir/dry-run.out"
grep -Fq 'libvirt-dns=ready gerrit.example.test=192.168.126.5 jenkins-controller.example.test=192.168.126.6' "$tmp_dir/dry-run.out"
grep -Fq 'host-dns=unresolved gerrit.example.test=unresolved jenkins-controller.example.test=unresolved' "$tmp_dir/dry-run.out"
grep -Fq 'systemd-resolved: dry-run ok' "$tmp_dir/dry-run.out"
[ ! -f "$stub_state/sudo.calls" ]

PATH="$stub_bin:$PATH" VM_TEST_STATE="$stub_state" VM_TEST_HOST_DNS=ready \
  "$helper" --env "$env_file" --dry-run >"$tmp_dir/dry-run-ready.out"
grep -Fq 'host-dns=ready gerrit.example.test=192.168.126.5 jenkins-controller.example.test=192.168.126.6' "$tmp_dir/dry-run-ready.out"

PATH="$stub_bin:$PATH" VM_TEST_STATE="$stub_state" VM_TEST_HOST_DNS=mismatch \
  "$helper" --env "$env_file" --dry-run >"$tmp_dir/dry-run-mismatch.out"
grep -Fq 'host-dns=mismatch gerrit.example.test=192.168.126.55 jenkins-controller.example.test=192.168.126.66' "$tmp_dir/dry-run-mismatch.out"

PATH="$stub_bin:$PATH" VM_TEST_STATE="$stub_state" \
  "$helper" --apply --env "$env_file" >"$tmp_dir/apply.out"
grep -Fq 'systemd-resolved-action=apply interface=lf-test123 dns=192.168.126.1 domain=~example.test' "$tmp_dir/apply.out"
grep -Fq 'systemd-resolved[apply]: ok mode=apply' "$tmp_dir/apply.out"
grep -Fq -- '--interface=lf-test123 --set-dns=192.168.126.1 --set-domain=~example.test' "$stub_state/systemd-resolve.calls"
grep -Fq 'sudo-check' "$stub_state/sudo.calls"

PATH="$stub_bin:$PATH" VM_TEST_STATE="$stub_state" \
  "$helper" --env "$env_file" --revert >"$tmp_dir/revert.out"
grep -Fq 'systemd-resolved-action=revert interface=lf-test123' "$tmp_dir/revert.out"
grep -Fq 'systemd-resolved[revert]: ok mode=revert' "$tmp_dir/revert.out"
grep -Fq -- '--interface=lf-test123 --revert' "$stub_state/systemd-resolve.calls"

rm -f "$stub_state/sudo.calls"
set +e
PATH="$stub_bin:$PATH" VM_TEST_STATE="$stub_state" VM_TEST_SUDO_FAIL=1 \
  "$helper" --env "$env_file" --apply >"$tmp_dir/no-sudo.out" 2>&1
rc=$?
set -e
[ "$rc" -ne 0 ]
grep -Fq 'Non-interactive sudo is required for --apply' "$tmp_dir/no-sudo.out"
if [ -f "$stub_state/sudo.calls" ] && grep -Fq 'sudo-run' "$stub_state/sudo.calls"; then
  printf 'apply must fail before running sudo-mutating command\n' >&2
  exit 1
fi

PATH="$stub_bin:$PATH" VM_TEST_STATE="$stub_state" \
  "$helper" >"$tmp_dir/default-env.out"
grep -Fq 'selected-network=loopforge-vm-manual-default-net' "$tmp_dir/default-env.out"
grep -Fq 'systemd-resolved: dry-run ok' "$tmp_dir/default-env.out"

if PATH="$stub_bin:$PATH" VM_TEST_STATE="$stub_state" \
  "$helper" --env "$env_file" --check >"$tmp_dir/check-rejected.out" 2>&1; then
  printf 'systemd-resolved helper must reject --check\n' >&2
  exit 1
fi
grep -Fq 'Unknown option: --check' "$tmp_dir/check-rejected.out"
