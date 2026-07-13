#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
tool="$repo_root/simulation/vm/tools/cleanup-libvirt-resources.sh"
tmp_dir="$(mktemp -d)"
stub_bin="$tmp_dir/bin"
state="$tmp_dir/state"
command_log="$tmp_dir/commands.log"
trap 'rm -rf "$tmp_dir"' EXIT
mkdir -p "$stub_bin"

cat >"$stub_bin/id" <<'STUB'
#!/usr/bin/env bash
[ "${1:-}" = -u ] || exit 2
printf '%s\n' "${VM_TOOL_TEST_UID:-1000}"
STUB

cat >"$stub_bin/ip" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
state="${VM_TOOL_TEST_STATE:?}"
log="${VM_TOOL_TEST_LOG:?}"
case "$*" in
  '-o link show type bridge')
    n=1
    for file in "$state"/bridges/*; do
      [ -e "$file" ] || continue
      printf '%s: %s: <BROADCAST> mtu 1500 state DOWN\n' "$n" "$(basename "$file")"
      n=$((n + 1))
    done
    ;;
  'link show '*)
    bridge="${*: -1}"
    [ -e "$state/bridges/$bridge" ]
    ;;
  'link delete '*)
    bridge="${*: -1}"
    printf 'ip-delete %s\n' "$bridge" >>"$log"
    [ "${VM_TOOL_FAIL:-}" != ip-delete ] || exit 41
    rm -f "$state/bridges/$bridge"
    ;;
  *)
    printf 'unexpected ip command: %s\n' "$*" >&2
    exit 2
    ;;
esac
STUB

cat >"$stub_bin/virsh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
state="${VM_TOOL_TEST_STATE:?}"
log="${VM_TOOL_TEST_LOG:?}"
if [ "${1:-}" = -c ]; then shift 2; fi
cmd="${1:-}"
shift || true
fail_if_requested() {
  [ "${VM_TOOL_FAIL:-}" != "$1" ] || exit 42
}
case "$cmd" in
  uri)
    printf 'qemu:///system\n'
    ;;
  list)
    fail_if_requested list
    for file in "$state"/domains/*; do [ ! -e "$file" ] || basename "$file"; done
    ;;
  domstate)
    cat "$state/domains/${1:?}"
    ;;
  destroy)
    fail_if_requested destroy-domain
    printf 'destroy-domain %s\n' "$1" >>"$log"
    printf 'shut off\n' >"$state/domains/$1"
    ;;
  undefine)
    fail_if_requested undefine-domain
    printf 'undefine-domain %s\n' "$1" >>"$log"
    rm -f "$state/domains/$1"
    ;;
  pool-list)
    fail_if_requested pool-list
    for dir in "$state"/pools/*; do [ ! -d "$dir" ] || basename "$dir"; done
    ;;
  pool-info)
    pool="${1:?}"
    [ -d "$state/pools/$pool" ]
    if [ -e "$state/pools/$pool/active" ]; then
      printf 'State: running\n'
    else
      printf 'State: inactive\n'
    fi
    ;;
  pool-dumpxml)
    pool="${1:?}"
    target="$(cat "$state/pools/$pool/target")"
    printf "<pool type='dir'><name>%s</name><target><path>%s</path></target></pool>\n" "$pool" "$target"
    ;;
  vol-list)
    pool="${1:?}"
    target="$(cat "$state/pools/$pool/target")"
    printf ' Name                 Path\n-----------------------------------------\n'
    for file in "$target"/*; do
      [ -f "$file" ] || continue
      printf ' %-20s %s\n' "$(basename "$file")" "$file"
    done
    ;;
  pool-start)
    fail_if_requested pool-start
    printf 'pool-start %s\n' "$1" >>"$log"
    touch "$state/pools/$1/active"
    ;;
  pool-refresh)
    fail_if_requested pool-refresh
    printf 'pool-refresh %s\n' "$1" >>"$log"
    ;;
  vol-delete)
    volume="${1:?}"
    shift
    [ "${1:-}" = --pool ]
    pool="${2:?}"
    fail_if_requested vol-delete
    printf 'vol-delete %s/%s\n' "$pool" "$volume" >>"$log"
    target="$(cat "$state/pools/$pool/target")"
    rm -f "$target/$volume"
    ;;
  pool-destroy)
    fail_if_requested pool-destroy
    printf 'pool-destroy %s\n' "$1" >>"$log"
    rm -f "$state/pools/$1/active"
    ;;
  pool-undefine)
    fail_if_requested pool-undefine
    printf 'pool-undefine %s\n' "$1" >>"$log"
    rm -rf "$state/pools/$1"
    ;;
  net-list)
    fail_if_requested net-list
    for dir in "$state"/networks/*; do [ ! -d "$dir" ] || basename "$dir"; done
    ;;
  net-info)
    network="${1:?}"
    [ -d "$state/networks/$network" ]
    if [ -e "$state/networks/$network/active" ]; then
      printf 'Active: yes\n'
    else
      printf 'Active: no\n'
    fi
    ;;
  net-dumpxml)
    network="${1:?}"
    bridge="$(cat "$state/networks/$network/bridge")"
    printf "<network><name>%s</name><bridge name='%s'/></network>\n" "$network" "$bridge"
    ;;
  net-destroy)
    fail_if_requested net-destroy
    network="${1:?}"
    printf 'net-destroy %s\n' "$network" >>"$log"
    rm -f "$state/networks/$network/active"
    bridge="$(cat "$state/networks/$network/bridge")"
    rm -f "$state/bridges/$bridge"
    ;;
  net-undefine)
    fail_if_requested net-undefine
    printf 'net-undefine %s\n' "$1" >>"$log"
    rm -rf "$state/networks/$1"
    ;;
  *)
    printf 'unexpected virsh command: %s %s\n' "$cmd" "$*" >&2
    exit 2
    ;;
esac
STUB
chmod +x "$stub_bin/id" "$stub_bin/ip" "$stub_bin/virsh"

reset_state() {
  rm -rf "$state"
  mkdir -p "$state/domains" "$state/pools" "$state/networks" "$state/bridges" "$state/volumes"
  : >"$command_log"
  printf 'running\n' >"$state/domains/loopforge-vm-test-running"
  printf 'shut off\n' >"$state/domains/loopforge-vm-test-stopped"
  printf 'running\n' >"$state/domains/unrelated-domain"
  for pool in loopforge-vm-test-images loopforge-vm-test-cache unrelated-pool; do
    mkdir -p "$state/pools/$pool" "$state/volumes/$pool"
    printf '%s\n' "$state/volumes/$pool" >"$state/pools/$pool/target"
    touch "$state/pools/$pool/active"
  done
  mkdir -p "$state/pools/loopforge-vm-test-missingtarget"
  printf '%s\n' "$state/volumes/loopforge-vm-test-missingtarget" \
    >"$state/pools/loopforge-vm-test-missingtarget/target"
  rm -f "$state/pools/loopforge-vm-test-cache/active"
  printf 'overlay\n' >"$state/volumes/loopforge-vm-test-images/bundle-factory.qcow2"
  printf 'cache\n' >"$state/volumes/loopforge-vm-test-cache/base.qcow2"
  printf 'keep\n' >"$state/volumes/unrelated-pool/keep.qcow2"
  for network in loopforge-vm-test-net loopforge-vm-test-inactive-net unrelated-net; do
    mkdir -p "$state/networks/$network"
  done
  printf 'lf-aabbccdd\n' >"$state/networks/loopforge-vm-test-net/bridge"
  printf 'lf-11223344\n' >"$state/networks/loopforge-vm-test-inactive-net/bridge"
  printf 'virbr0\n' >"$state/networks/unrelated-net/bridge"
  touch "$state/networks/loopforge-vm-test-net/active" "$state/networks/unrelated-net/active"
  touch "$state/bridges/lf-aabbccdd" "$state/bridges/lf-11223344" \
    "$state/bridges/lf-deadbeef" "$state/bridges/virbr0"
}

run_tool() {
  env PATH="$stub_bin:$PATH" VM_TOOL_TEST_STATE="$state" VM_TOOL_TEST_LOG="$command_log" \
    VM_TOOL_TEST_UID="${VM_TOOL_TEST_UID:-1000}" VM_TOOL_FAIL="${VM_TOOL_FAIL:-}" \
    "$tool" "$@"
}

reset_state
dry_out="$tmp_dir/dry-run.out"
run_tool --dry-run >"$dry_out"
grep -Fq 'would-destroy-domain name=loopforge-vm-test-running state=running' "$dry_out"
grep -Fq 'would-undefine-domain name=loopforge-vm-test-stopped' "$dry_out"
grep -Fq 'would-delete-volume pool=loopforge-vm-test-images name=bundle-factory.qcow2' "$dry_out"
grep -Fq 'would-start-pool name=loopforge-vm-test-cache' "$dry_out"
grep -Fq 'would-delete-volume pool=loopforge-vm-test-cache name=base.qcow2' "$dry_out"
grep -Fq 'missing-pool-target pool=loopforge-vm-test-missingtarget' "$dry_out"
grep -Fq 'would-undefine-pool name=loopforge-vm-test-missingtarget' "$dry_out"
grep -Fq 'would-destroy-network name=loopforge-vm-test-net' "$dry_out"
grep -Fq 'would-undefine-network name=loopforge-vm-test-inactive-net' "$dry_out"
grep -Fq 'would-delete-bridge name=lf-deadbeef' "$dry_out"
grep -Fq 'dry-run: ok domains=2 volumes=2 pools=3 networks=2 bridges=3' "$dry_out"
[ ! -s "$command_log" ]
[ -e "$state/domains/loopforge-vm-test-running" ]
[ -e "$state/volumes/loopforge-vm-test-images/bundle-factory.qcow2" ]

run_tool >"$tmp_dir/default-dry-run.out"
grep -Fq 'dry-run: ok domains=2 volumes=2 pools=3 networks=2 bridges=3' \
  "$tmp_dir/default-dry-run.out"
[ ! -s "$command_log" ]

VM_TOOL_TEST_UID=0 run_tool >"$tmp_dir/root-default-dry-run.out"
grep -Fq 'dry-run: ok domains=2 volumes=2 pools=3 networks=2 bridges=3' \
  "$tmp_dir/root-default-dry-run.out"
[ ! -s "$command_log" ]

if run_tool --destroy >"$tmp_dir/nonroot-destroy.out" 2>"$tmp_dir/nonroot-destroy.err"; then
  printf 'Cleanup destroy must require root\n' >&2
  exit 1
fi
grep -Fq 'Root privilege is required; rerun:' "$tmp_dir/nonroot-destroy.err"
grep -Fq -- '--destroy' "$tmp_dir/nonroot-destroy.err"

VM_TOOL_TEST_UID=0 run_tool --destroy >"$tmp_dir/cleanup.out"
grep -Fq 'missing-pool-target pool=loopforge-vm-test-missingtarget' "$tmp_dir/cleanup.out"
grep -Fq 'cleanup: ok domains=2 volumes=2 pools=3 networks=2 bridges=3' "$tmp_dir/cleanup.out"
[ ! -e "$state/domains/loopforge-vm-test-running" ]
[ ! -e "$state/volumes/loopforge-vm-test-images/bundle-factory.qcow2" ]
[ ! -e "$state/pools/loopforge-vm-test-cache" ]
[ ! -e "$state/pools/loopforge-vm-test-missingtarget" ]
[ ! -e "$state/networks/loopforge-vm-test-net" ]
[ ! -e "$state/bridges/lf-deadbeef" ]
[ -e "$state/domains/unrelated-domain" ]
[ -e "$state/pools/unrelated-pool" ]
[ -e "$state/networks/unrelated-net" ]
[ -e "$state/bridges/virbr0" ]

overlay_delete_line="$(grep -n '^vol-delete loopforge-vm-test-images/' "$command_log" | cut -d: -f1)"
overlay_pool_line="$(grep -n '^pool-undefine loopforge-vm-test-images$' "$command_log" | cut -d: -f1)"
[ "$overlay_delete_line" -lt "$overlay_pool_line" ]
if grep -Fq 'pool-start loopforge-vm-test-missingtarget' "$command_log"; then
  printf 'Cleanup tool must not start pools with missing targets\n' >&2
  exit 1
fi

VM_TOOL_TEST_UID=0 run_tool --destroy >"$tmp_dir/repeat.out"
grep -Fq 'cleanup: ok domains=0 volumes=0 pools=0 networks=0 bridges=0' "$tmp_dir/repeat.out"

reset_state
run_tool --dry-run >"$tmp_dir/nonroot-explicit-dry-run.out"
grep -Fq 'dry-run: ok domains=2 volumes=2 pools=3 networks=2 bridges=3' \
  "$tmp_dir/nonroot-explicit-dry-run.out"
[ ! -s "$command_log" ]

reset_state
for failure in pool-start pool-refresh vol-delete pool-destroy pool-undefine \
  destroy-domain undefine-domain net-destroy net-undefine ip-delete; do
  reset_state
  if VM_TOOL_TEST_UID=0 VM_TOOL_FAIL="$failure" run_tool --destroy \
    >"$tmp_dir/fail-$failure.out" 2>"$tmp_dir/fail-$failure.err"; then
    printf 'Cleanup tool must propagate failure: %s\n' "$failure" >&2
    exit 1
  fi
  if grep -Fq 'cleanup: ok' "$tmp_dir/fail-$failure.out"; then
    printf 'Cleanup tool must not report success after failure: %s\n' "$failure" >&2
    exit 1
  fi
done

reset_state
if VM_TOOL_FAIL=list run_tool --dry-run >"$tmp_dir/read-fail.out" 2>"$tmp_dir/read-fail.err"; then
  printf 'Cleanup dry-run must propagate inventory failure\n' >&2
  exit 1
fi
grep -Fq 'Unable to inventory LoopForge domains' "$tmp_dir/read-fail.err"
[ ! -s "$command_log" ]

if run_tool --unknown >"$tmp_dir/unknown.out" 2>"$tmp_dir/unknown.err"; then
  printf 'Cleanup tool must reject unknown options\n' >&2
  exit 1
fi
grep -Fq 'Unknown option: --unknown' "$tmp_dir/unknown.err"

grep -Fq -- '--dry-run' < <("$tool" --help)
grep -Fq -- '--destroy' < <("$tool" --help)
if grep -Eq '(^|[[:space:]])rm([[:space:]]|$)|qemu-img|generated/simulation/vm' "$tool"; then
  printf 'Cleanup tool must not delete files or generated workspaces directly\n' >&2
  exit 1
fi
