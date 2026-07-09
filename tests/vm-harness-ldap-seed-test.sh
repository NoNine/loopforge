#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
run_id="vm-m4-$$"
vm_set_id="m4-$$"
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

cat >"$stub_bin/virt-install" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
chmod +x "$stub_bin/virt-install"

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
state_dir="${VM_STUB_STATE:?VM_STUB_STATE required}"
target=""
for arg in "$@"; do
  case "$arg" in
    *@*) target="$arg" ;;
  esac
done
case "$target" in
  *@192.168.126.*) ;;
  *) target="unknown@unknown" ;;
esac
host="${target#*@}"
script="$(cat)"
if [ -z "$script" ] && [ "${@: -1}" = "printf ready" ]; then
  printf ready
  exit 0
fi
if printf '%s\n' "$script" | grep -Fq 'cloud-init status --wait'; then
  exit 0
fi
file_host="$(printf '%s\n' "$host" | tr -c 'A-Za-z0-9_.-' '_')"
printf '%s\n' "$script" >"$state_dir/ssh-$file_host-$(date +%s%N).sh"
case "$script" in
  *"apt-get install"*)
    printf '%s\n' "os-baseline $host" >>"$state_dir/calls"
    ;;
esac
case "$script" in
  *"systemctl enable --now slapd"*)
    printf '%s\n' "ldap-service $host" >>"$state_dir/calls"
    ;;
esac
case "$script" in
  *"uid=test-user"*)
    printf '%s\n' "ldap-consumer $host" >>"$state_dir/calls"
    ;;
esac
STUB
chmod +x "$stub_bin/ssh"

[ -f "$repo_root/simulation/vm/ldap/50-harness-seed.ldif" ]
grep -Fq 'uid=gerrit-admin' "$repo_root/simulation/vm/ldap/50-harness-seed.ldif"
grep -Fq 'cn=jenkins-admins' "$repo_root/simulation/vm/ldap/50-harness-seed.ldif"

PATH="$stub_bin:$PATH" VM_STUB_STATE="$stub_state" \
  "$repo_root/simulation/vm/simulate.sh" --env "$env_file" init-run >"$tmp_dir/init-run.out"
grep -Fxq "init-run: ok run-id=$run_id" "$tmp_dir/init-run.out"

PATH="$stub_bin:$PATH" VM_STUB_STATE="$stub_state" \
  "$repo_root/simulation/vm/simulate.sh" --env "$env_file" create >"$tmp_dir/create.out"
grep -Fxq "create: ok vm-set=$vm_set_id baseline-prereqs=ready" "$tmp_dir/create.out"

marker="$generated_root/vm-sets/$vm_set_id/.loopforge-vm-baseline-prereqs.env"
[ -f "$marker" ]
grep -Fq 'status=ready' "$marker"
grep -Fq 'apt_mirror=http://mirrors.tuna.tsinghua.edu.cn/ubuntu/' "$marker"
grep -Fq 'ldap_bind_dn=cn=readonly,dc=example,dc=test' "$marker"
network_xml="$generated_root/vm-sets/$vm_set_id/libvirt/network.xml"
grep -Eq "<bridge name='lf-[0-9a-f]{12}'" "$network_xml"
! grep -Fq "<bridge name='loopforge-vm-" "$network_xml"
for machine in bundle-factory ldap gerrit jenkins-controller jenkins-agent; do
  grep -Fq 'shut off' "$stub_state/domains/loopforge-vm-$run_id-$vm_set_id-$machine.state"
done

create_log="$(find "$generated_root/$run_id/host/logs/harness" -name 'create-*.log' -print | sort | tail -1)"
grep -Fq 'apt-mirror=http://mirrors.tuna.tsinghua.edu.cn/ubuntu/' "$create_log"
grep -Fq 'ldap-service=ready host=ldap port=389' "$create_log"
grep -Fq 'ldap-consumer=gerrit reachable host=ldap port=389' "$create_log"
grep -Fq 'ldap-consumer=jenkins-controller reachable host=ldap port=389' "$create_log"

grep -Fq 'os-baseline' "$stub_state/calls"
grep -Fq 'ldap-service' "$stub_state/calls"
grep -Fq 'ldap-consumer' "$stub_state/calls"

for script in "$stub_state"/ssh-*.sh; do
  if grep -Fq 'apt-get install' "$script"; then
    grep -Fq 'mirrors.tuna.tsinghua.edu.cn/ubuntu/' "$script"
  fi
done

grep -R -Fq 'LDAP_BIND_PASSWORD=' "$stub_state"/ssh-*.sh
! grep -R -Fq -- '-w readonly-password' "$stub_state"/ssh-*.sh
grep -R -Fq 'uid=test-user' "$stub_state"/ssh-*.sh

runtime_env="$generated_root/$run_id/host/rendered/harness.runtime.env"
rendered_env="$generated_root/$run_id/host/rendered/harness.env"
grep -Fq 'HARNESS_LDAP_BIND_PASSWORD=simulation-owned-redacted' "$runtime_env"
grep -Fq 'HARNESS_LDAP_BIND_PASSWORD=simulation-owned-redacted' "$rendered_env"
if grep -R --include='*.env' -Fq 'HARNESS_LDAP_BIND_PASSWORD=readonly-password' "$generated_root/$run_id"; then
  printf 'VM runtime files must not persist the raw LDAP bind password\n' >&2
  exit 1
fi
