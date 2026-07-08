#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
run_id="vm-m3-$$"
vm_set_id="m3-$$"
generated_root="$repo_root/generated/simulation/vm"
trap 'rm -rf "$tmp_dir" "$generated_root/$run_id" "$generated_root/vm-sets/$vm_set_id"' EXIT

env_file="$tmp_dir/harness.env"
stub_bin="$tmp_dir/bin"
stub_state="$tmp_dir/state"
mkdir -p "$stub_bin" "$stub_state"

base_image="$tmp_dir/noble-server-cloudimg-amd64.img"
printf 'stub cloud image\n' >"$base_image"

sed \
  -e "s/^HARNESS_RUN_ID=.*/HARNESS_RUN_ID=$run_id/" \
  -e "s/^LOOPFORGE_VM_SET_ID=.*/LOOPFORGE_VM_SET_ID=$vm_set_id/" \
  -e "s|^VM_BASE_IMAGE_PATH=.*|VM_BASE_IMAGE_PATH=$base_image|" \
  -e 's/^VM_OPERATOR_SSH_TIMEOUT_SECONDS=.*/VM_OPERATOR_SSH_TIMEOUT_SECONDS=5/' \
  -e 's/^VM_OPERATOR_SSH_POLL_SECONDS=.*/VM_OPERATOR_SSH_POLL_SECONDS=1/' \
  "$repo_root/simulation/vm/example.env" >"$env_file"

cat >"$stub_bin/virsh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
state_dir="${VM_STUB_STATE:?VM_STUB_STATE required}"
if [ "${1:-}" = "-c" ]; then
  shift 2
fi
cmd="${1:-}"
shift || true
case "$cmd" in
  uri)
    printf 'qemu:///system\n'
    ;;
  list)
    if [ "${1:-}" = "--all" ] && [ "${2:-}" = "--name" ]; then
      find "$state_dir/domains" -type f -name '*.state' -printf '%f\n' 2>/dev/null |
        sed 's/\.state$//' | sort
    else
      printf '\n'
    fi
    ;;
  net-list)
    if [ -f "$state_dir/network.name" ]; then
      cat "$state_dir/network.name"
    fi
    ;;
  pool-list)
    printf '\n'
    ;;
  net-info)
    if [ -f "$state_dir/network.active" ]; then
      printf 'Active: yes\n'
    else
      printf 'Active: no\n'
    fi
    ;;
  net-define)
    xml="${1:?xml required}"
    sed -n "s:.*<name>\\(.*\\)</name>.*:\\1:p" "$xml" >"$state_dir/network.name"
    ;;
  net-start)
    printf '%s\n' "$1" >"$state_dir/network.name"
    touch "$state_dir/network.active"
    ;;
  dominfo)
    domain="${1:?domain required}"
    [ -f "$state_dir/domains/$domain.state" ] || exit 1
    ;;
  define)
    xml="${1:?xml required}"
    domain="$(sed -n "s:.*<name>\\(.*\\)</name>.*:\\1:p" "$xml" | head -1)"
    mkdir -p "$state_dir/domains"
    printf 'shut off\n' >"$state_dir/domains/$domain.state"
    ;;
  domstate)
    domain="${1:?domain required}"
    cat "$state_dir/domains/$domain.state"
    ;;
  start)
    domain="${1:?domain required}"
    printf 'running\n' >"$state_dir/domains/$domain.state"
    ;;
  shutdown)
    domain="${1:?domain required}"
    printf 'shut off\n' >"$state_dir/domains/$domain.state"
    ;;
  net-dhcp-leases)
    mac=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --mac) mac="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    case "$mac" in
      *:*) octet=$((0x$(printf '%s' "$mac" | awk -F: '{print $6}'))) ;;
      *) octet=20 ;;
    esac
    printf ' 0  %s  ipv4  192.168.126.%s/24  host  *\n' "$mac" "$octet"
    ;;
  *)
    printf 'unexpected virsh command: %s %s\n' "$cmd" "$*" >&2
    exit 1
    ;;
esac
STUB
chmod +x "$stub_bin/virsh"

cat >"$stub_bin/qemu-img" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  create)
    output="${@: -1}"
    mkdir -p "$(dirname "$output")"
    printf 'qcow2 stub\n' >"$output"
    ;;
  resize)
    ;;
  *)
    printf 'unexpected qemu-img command: %s\n' "$*" >&2
    exit 1
    ;;
esac
STUB
chmod +x "$stub_bin/qemu-img"

cat >"$stub_bin/cloud-localds" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
while [ "$#" -gt 0 ]; do
  case "$1" in
    --network-config=*) shift ;;
    *) output="$1"; shift; break ;;
  esac
done
mkdir -p "$(dirname "$output")"
printf 'seed stub\n' >"$output"
STUB
chmod +x "$stub_bin/cloud-localds"

for tool in virt-install; do
  cat >"$stub_bin/$tool" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
  chmod +x "$stub_bin/$tool"
done

cat >"$stub_bin/ssh-keygen" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = "-F" ]; then
  host="$2"
  file=""
  shift 2
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -f) file="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  grep -Fq "$host" "$file"
  exit $?
fi
out=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -f) out="$2"; shift 2 ;;
    *) shift ;;
  esac
done
[ -n "$out" ] || exit 1
printf 'private key stub\n' >"$out"
printf 'ssh-ed25519 public-key-stub\n' >"$out.pub"
STUB
chmod +x "$stub_bin/ssh-keygen"

cat >"$stub_bin/ssh-keyscan" <<'STUB'
#!/usr/bin/env bash
host="${@: -1}"
printf '%s ssh-ed25519 host-key-stub\n' "$host"
STUB
chmod +x "$stub_bin/ssh-keyscan"

cat >"$stub_bin/ssh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
last="${@: -1}"
if [ "$last" = "printf ready" ]; then
  printf ready
elif printf '%s\n' "$*" | grep -Fq 'cloud-init status --wait'; then
  exit 0
else
  printf '%s\n' "$*" >"${VM_STUB_STATE:?}/interactive-ssh.args"
fi
STUB
chmod +x "$stub_bin/ssh"

PATH="$stub_bin:$PATH" VM_STUB_STATE="$stub_state" \
  "$repo_root/simulation/vm/simulate.sh" --env "$env_file" init-run >"$tmp_dir/init-run.out"
grep -Fxq "init-run: ok run-id=$run_id" "$tmp_dir/init-run.out"

PATH="$stub_bin:$PATH" VM_STUB_STATE="$stub_state" \
  "$repo_root/simulation/vm/simulate.sh" --env "$env_file" create >"$tmp_dir/create.out"
grep -Fxq "create: ok vm-set=$vm_set_id domains=defined" "$tmp_dir/create.out"
marker="$generated_root/vm-sets/$vm_set_id/.loopforge-vm-set.env"
grep -Fq "vm_set_id=$vm_set_id" "$marker"
grep -Fq 'VM_PROVISIONING_MODEL=cloud-image-clone' "$generated_root/$run_id/host/rendered/harness.runtime.env"
for machine in bundle-factory ldap gerrit jenkins-controller jenkins-agent; do
  [ -f "$generated_root/vm-sets/$vm_set_id/libvirt/disks/$machine.qcow2" ]
  [ -f "$generated_root/vm-sets/$vm_set_id/libvirt/seeds/$machine-seed.iso" ]
  [ -f "$generated_root/vm-sets/$vm_set_id/libvirt/machines/$machine.env" ]
done

PATH="$stub_bin:$PATH" VM_STUB_STATE="$stub_state" \
  "$repo_root/simulation/vm/simulate.sh" --env "$env_file" up >"$tmp_dir/up.out"
grep -Fxq "up: ok vm-set=$vm_set_id ssh=ready" "$tmp_dir/up.out"
grep -Fq 'ssh_host=192.168.126.' "$generated_root/vm-sets/$vm_set_id/libvirt/machines/gerrit.env"

PATH="$stub_bin:$PATH" VM_STUB_STATE="$stub_state" \
  "$repo_root/simulation/vm/simulate.sh" --env "$env_file" status >"$tmp_dir/status.out"
grep -Fq 'status: running' "$tmp_dir/status.out"
grep -Fq 'Target SSH' "$tmp_dir/status.out"
grep -Fq 'gerrit              ci-operator   192.168.126.' "$tmp_dir/status.out"
grep -Fq 'jenkins-controller  ci-operator   192.168.126.' "$tmp_dir/status.out"
grep -Fq 'jenkins-agent       ci-operator   192.168.126.' "$tmp_dir/status.out"
grep -Fq 'ready' "$tmp_dir/status.out"
! grep -Fq 'VM domains' "$tmp_dir/status.out"
! grep -Fq 'vm-resources=' "$tmp_dir/status.out"
! grep -Fq 'domain=' "$tmp_dir/status.out"

PATH="$stub_bin:$PATH" VM_STUB_STATE="$stub_state" \
  "$repo_root/simulation/vm/simulate.sh" --env "$env_file" ssh --role gerrit
grep -Fq 'ci-operator@192.168.126.' "$stub_state/interactive-ssh.args"

PATH="$stub_bin:$PATH" VM_STUB_STATE="$stub_state" \
  "$repo_root/simulation/vm/simulate.sh" --env "$env_file" down >"$tmp_dir/down.out"
grep -Fxq "down: ok vm-set=$vm_set_id" "$tmp_dir/down.out"
grep -Fq 'shut off' "$stub_state/domains/loopforge-vm-$run_id-$vm_set_id-gerrit.state"
