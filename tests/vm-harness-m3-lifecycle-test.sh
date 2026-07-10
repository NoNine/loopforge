#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
run_id="vm-m3-$$"
vm_set_id="m3-$$"
generated_root="$repo_root/generated/simulation/vm"
cleanup() {
  [ "${VM_TEST_KEEP_TMP:-0}" -eq 1 ] ||
    rm -rf "$tmp_dir" "$generated_root/$run_id" "$generated_root/vm-sets/$vm_set_id"
}
trap cleanup EXIT

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
    if [ -d "$state_dir/pools" ]; then
      find "$state_dir/pools" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort
    fi
    ;;
  pool-info)
    pool="${1:?pool required}"
    [ -d "$state_dir/pools/$pool" ] || exit 1
    if [ -f "$state_dir/pools/$pool/active" ]; then
      printf 'State: running\n'
    else
      printf 'State: inactive\n'
    fi
    ;;
  pool-dumpxml)
    pool="${1:?pool required}"
    target="$(cat "$state_dir/pools/$pool/target")"
    printf "<pool type='dir'><name>%s</name><target><path>%s</path></target></pool>\n" "$pool" "$target"
    ;;
  pool-define)
    xml="${1:?pool XML required}"
    pool="$(sed -n "s:.*<name>\\(.*\\)</name>.*:\\1:p" "$xml" | head -1)"
    target="$(sed -n "s:.*<path>\\(.*\\)</path>.*:\\1:p" "$xml" | head -1)"
    mkdir -p "$state_dir/pools/$pool/volumes" "$target"
    printf '%s\n' "$target" >"$state_dir/pools/$pool/target"
    ;;
  pool-start)
    pool="${1:?pool required}"
    touch "$state_dir/pools/$pool/active"
    ;;
  pool-refresh)
    pool="${1:?pool required}"
    [ -f "$state_dir/pools/$pool/active" ]
    ;;
  pool-destroy)
    rm -f "$state_dir/pools/${1:?pool required}/active"
    ;;
  pool-undefine)
    rm -rf "$state_dir/pools/${1:?pool required}"
    ;;
  vol-info)
    volume="${1:?volume required}"
    shift
    [ "${1:-}" = --pool ]
    pool="${2:?pool required}"
    target="$(cat "$state_dir/pools/$pool/target")"
    [ -f "$target/$volume" ]
    ;;
  vol-list)
    pool="${1:?pool required}"
    target="$(cat "$state_dir/pools/$pool/target")"
    find "$target" -maxdepth 1 -type f -printf '%f\n' 2>/dev/null | sort
    ;;
  vol-path)
    volume="${1:?volume required}"
    shift
    [ "${1:-}" = --pool ]
    pool="${2:?pool required}"
    target="$(cat "$state_dir/pools/$pool/target")"
    printf '%s/%s\n' "$target" "$volume"
    ;;
  vol-create)
    pool="${1:?pool required}"
    xml="${2:?volume XML required}"
    volume="$(sed -n "s:.*<name>\\(.*\\)</name>.*:\\1:p" "$xml" | head -1)"
    target="$(cat "$state_dir/pools/$pool/target")"
    mkdir -p "$target"
    printf 'libvirt-managed qcow2 stub\n' >"$target/$volume"
    chmod 000 "$target/$volume"
    cp "$xml" "$state_dir/pools/$pool/volumes/$volume.xml"
    ;;
  vol-dumpxml)
    [ "${VM_STUB_FAIL_MODE:-}" != image-info ] || {
      printf 'forced volume info failure\n' >&2
      exit 45
    }
    volume="${1:?volume required}"
    shift
    [ "${1:-}" = --pool ]
    pool="${2:?pool required}"
    target="$(cat "$state_dir/pools/$pool/target")"
    stored="$state_dir/pools/$pool/volumes/$volume.xml"
    if [ -f "$stored" ]; then
      cat "$stored"
    else
      printf "<volume type='file'><name>%s</name><capacity unit='bytes'>21474836480</capacity><target><path>%s/%s</path><format type='qcow2'/><permissions><mode>0644</mode><owner>0</owner><group>0</group></permissions></target><backingStore><path>%s</path><format type='qcow2'/></backingStore></volume>\n" \
        "$volume" "$target" "$volume" "${VM_BASE_IMAGE_PATH:?VM_BASE_IMAGE_PATH required}"
    fi
    ;;
  vol-download)
    volume="${1:?volume required}"
    output="${2:?output required}"
    shift 2
    [ "${1:-}" = --pool ]
    pool="${2:?pool required}"
    target="$(cat "$state_dir/pools/$pool/target")"
    cp "$target/$volume" "$output"
    ;;
  vol-delete)
    volume="${1:?volume required}"
    shift
    [ "${1:-}" = --pool ]
    pool="${2:?pool required}"
    target="$(cat "$state_dir/pools/$pool/target")"
    rm -f "$target/$volume" "$state_dir/pools/$pool/volumes/$volume.xml"
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
    cp "$xml" "$state_dir/network.xml"
    ;;
  net-dumpxml)
    cat "$state_dir/network.xml"
    ;;
  net-start)
    printf '%s\n' "$1" >"$state_dir/network.name"
    touch "$state_dir/network.active"
    ;;
  net-destroy)
    rm -f "$state_dir/network.active"
    ;;
  net-undefine)
    rm -f "$state_dir/network.name" "$state_dir/network.xml"
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
    cp "$xml" "$state_dir/domains/$domain.xml"
    ;;
  dumpxml)
    cat "$state_dir/domains/${1:?domain required}.xml"
    ;;
  domuuid)
    printf '%s\n' "${1:?domain required}" | sha256sum | awk '{print substr($1, 1, 32)}'
    ;;
  domstate)
    domain="${1:?domain required}"
    cat "$state_dir/domains/$domain.state"
    ;;
  start)
    domain="${1:?domain required}"
    if printf '%s\n' "$domain" | grep -Fq 'base-image-bake'; then
      [ -f "$state_dir/network.active" ] || {
        printf 'base-image bake requires an active VM network\n' >&2
        exit 47
      }
    fi
    printf 'running\n' >"$state_dir/domains/$domain.state"
    ;;
  shutdown)
    domain="${1:?domain required}"
    printf 'shut off\n' >"$state_dir/domains/$domain.state"
    ;;
  destroy)
    domain="${1:?domain required}"
    printf 'shut off\n' >"$state_dir/domains/$domain.state"
    ;;
  undefine)
    domain="${1:?domain required}"
    rm -rf "$state_dir/domains/$domain.state" "$state_dir/domains/$domain.xml" \
      "$state_dir/snapshots/$domain"
    ;;
  snapshot-create-as)
    domain="${1:?domain required}"
    shift
    [ "${1:-}" = --name ]
    snapshot="${2:?snapshot required}"
    mkdir -p "$state_dir/snapshots/$domain"
    touch "$state_dir/snapshots/$domain/$snapshot"
    ;;
  snapshot-info)
    domain="${1:?domain required}"
    shift
    [ "${1:-}" = --snapshotname ]
    [ -f "$state_dir/snapshots/$domain/${2:?snapshot required}" ]
    ;;
  snapshot-delete)
    rm -f "$state_dir/snapshots/${1:?domain required}/${2:?snapshot required}"
    ;;
  snapshot-revert)
    domain="${1:?domain required}"
    [ -f "$state_dir/snapshots/$domain/${2:?snapshot required}" ]
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
    printf '2026-07-09 08:00:00  %s  ipv4  192.168.126.%s/24  host  *\n' "$mac" "$octet"
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
    backing=""
    previous=""
    for arg in "$@"; do
      if [ "$previous" = -b ]; then backing="$arg"; fi
      previous="$arg"
    done
    mkdir -p "$(dirname "$output")"
    printf 'qcow2 stub\n' >"$output"
    [ -z "$backing" ] || printf '%s\n' "$backing" >"$output.backing"
    ;;
  resize)
    ;;
  info)
    image="${@: -1}"
    case "$image" in
      */vm-sets/*/libvirt/disks/*)
        printf 'libvirt-managed volume inspected directly: %s\n' "$image" >&2
        exit 49
        ;;
    esac
    [ -s "$image" ] || exit 1
    if printf '%s\n' "$*" | grep -Fq -- '--output=json'; then
      if [ -f "$image.backing" ]; then
        printf '{"format":"qcow2","virtual-size":21474836480,"full-backing-filename":"%s"}\n' "$(cat "$image.backing")"
      else
        printf '{"format":"qcow2","virtual-size":21474836480}\n'
      fi
    else
      printf 'image: %s\nfile format: qcow2\n' "$image"
    fi
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
elif [ "$last" = bash ] || [ "$last" = -s ]; then
  script="$(cat)"
  if printf '%s\n' "$script" | grep -Fq 'systemctl enable --now slapd'; then
    printf '%s\n' \
      'ldap-seed-entry=ready type=user id=gerrit-admin dn=uid=gerrit-admin,ou=people,dc=example,dc=test' \
      'ldap-seed-entry=ready type=user id=jenkins-admin dn=uid=jenkins-admin,ou=people,dc=example,dc=test' \
      'ldap-seed-entry=ready type=user id=test-user dn=uid=test-user,ou=people,dc=example,dc=test' \
      'ldap-seed-entry=ready type=group id=gerrit-admins dn=cn=gerrit-admins,ou=groups,dc=example,dc=test' \
      'ldap-seed-entry=ready type=group id=jenkins-admins dn=cn=jenkins-admins,ou=groups,dc=example,dc=test' \
      'ldap-seed-entry=ready type=endpoint id=test-user dn=uid=test-user,ou=people,dc=example,dc=test'
  elif printf '%s\n' "$script" | grep -Fq 'LDAP consumer diagnostics'; then
    machine="$(printf '%s\n' "$script" | sed -n 's/^consumer_machine=//p' | head -1)"
    printf 'ldap-consumer-bind-search=ready machine=%s id=test-user dn=uid=test-user,ou=people,dc=example,dc=test\n' "$machine"
  fi
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
grep -Fxq "create: ok vm-set=$vm_set_id baseline-prereqs=ready baseline-snapshot=ready" "$tmp_dir/create.out"
marker="$generated_root/vm-sets/$vm_set_id/.loopforge-vm-set.env"
grep -Fq "vm_set_id=$vm_set_id" "$marker"
grep -Fq 'ownership_schema_version=5' "$marker"
grep -Fq 'disk_ownership=libvirt-managed' "$marker"
grep -Fq 'VM_PROVISIONING_MODEL=cloud-image-clone' "$generated_root/$run_id/host/rendered/harness.runtime.env"
network_xml="$generated_root/vm-sets/$vm_set_id/libvirt/network.xml"
grep -Eq "<bridge name='lf-[0-9a-f]{8}'" "$network_xml"
! grep -Fq "<bridge name='loopforge-vm-" "$network_xml"
grep -Fq "<hostname>ldap.example.test</hostname>" "$network_xml"
! grep -Fq "<hostname>ldap</hostname>" "$network_xml"
! grep -Eq "<host mac='52:54:00:[0-9a-f:]{8}' name='ldap' ip='192\\.168\\.126\\.[0-9]+'" "$network_xml"
grep -Eq "<host mac='52:54:00:[0-9a-f:]{8}' ip='192\\.168\\.126\\.[0-9]+'" "$network_xml"
for machine in bundle-factory ldap gerrit jenkins-controller jenkins-agent; do
  [ -f "$generated_root/vm-sets/$vm_set_id/libvirt/disks/$machine.qcow2" ]
  [ -f "$generated_root/vm-sets/$vm_set_id/libvirt/seeds/$machine-seed.iso" ]
  [ -f "$generated_root/vm-sets/$vm_set_id/libvirt/machines/$machine.env" ]
  grep -Fq 'disk_ownership=libvirt-managed' \
    "$generated_root/vm-sets/$vm_set_id/libvirt/machines/$machine.env"
  grep -Fq "volume_name=$machine.qcow2" \
    "$generated_root/vm-sets/$vm_set_id/libvirt/machines/$machine.env"
  grep -Fq "<disk type='file' device='disk'>" \
    "$generated_root/vm-sets/$vm_set_id/libvirt/machines/$machine.xml"
  grep -Fq "<source file='$generated_root/vm-sets/$vm_set_id/libvirt/disks/$machine.qcow2'/>" \
    "$generated_root/vm-sets/$vm_set_id/libvirt/machines/$machine.xml"
  grep -Fq 'shut off' "$stub_state/domains/loopforge-vm-$run_id-$vm_set_id-$machine.state"
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

if [ "${VM_TEST_INCLUDE_M5:-0}" -eq 1 ]; then
  snapshot_dir="$generated_root/vm-sets/$vm_set_id/snapshots"
  for machine in bundle-factory ldap gerrit jenkins-controller jenkins-agent; do
    record="$snapshot_dir/$machine.env"
    [ -f "$record" ]
    grep -Fq 'schema=1' "$record"
    grep -Fq "snapshot_name=loopforge-clean-baseline" "$record"
    [ -f "$stub_state/snapshots/loopforge-vm-$run_id-$vm_set_id-$machine/loopforge-clean-baseline" ]
  done

  PATH="$stub_bin:$PATH" VM_STUB_STATE="$stub_state" \
    "$repo_root/simulation/vm/simulate.sh" --env "$env_file" create >"$tmp_dir/create-reuse.out"
  grep -Fxq "create: ok vm-set=$vm_set_id baseline-prereqs=ready baseline-snapshot=ready" \
    "$tmp_dir/create-reuse.out"
  reuse_log="$(find "$generated_root/$run_id/host/logs/harness" -name 'create-*.log' -print | sort | tail -1)"
  grep -Fq 'baseline-snapshot=ready source=existing' "$reuse_log"

  mkdir -p "$generated_root/$run_id/host/state"
  touch "$generated_root/$run_id/host/state/mutable-marker"
  printf 'retained\n' >"$generated_root/$run_id/host/artifacts/exported/m5.txt"
  printf 'retained\n' >"$generated_root/$run_id/target/evidence/gerrit/m5.txt"

  PATH="$stub_bin:$PATH" VM_STUB_STATE="$stub_state" \
    "$repo_root/simulation/vm/simulate.sh" --env "$env_file" up >"$tmp_dir/m5-up.out"
  PATH="$stub_bin:$PATH" VM_STUB_STATE="$stub_state" \
    "$repo_root/simulation/vm/simulate.sh" --env "$env_file" clean >"$tmp_dir/clean.out"
  grep -Fxq "clean: ok vm-set=$vm_set_id baseline=restored" "$tmp_dir/clean.out"
  [ ! -e "$generated_root/$run_id/host/state" ]
  [ -f "$generated_root/$run_id/host/artifacts/exported/m5.txt" ]
  [ -f "$generated_root/$run_id/target/evidence/gerrit/m5.txt" ]
  [ -f "$generated_root/$run_id/.loopforge-vm-run.env" ]
  [ -f "$generated_root/$run_id/host/rendered/harness.runtime.env" ]
  for machine in bundle-factory ldap gerrit jenkins-controller jenkins-agent; do
    grep -Fq 'shut off' "$stub_state/domains/loopforge-vm-$run_id-$vm_set_id-$machine.state"
  done

  PATH="$stub_bin:$PATH" VM_STUB_STATE="$stub_state" \
    "$repo_root/simulation/vm/simulate.sh" --env "$env_file" audit-state >"$tmp_dir/audit-clean.out"
  grep -Fxq 'audit-state: ok' "$tmp_dir/audit-clean.out"

  touch "$generated_root/vm-sets/$vm_set_id/libvirt/disks/unowned.qcow2"
  if PATH="$stub_bin:$PATH" VM_STUB_STATE="$stub_state" \
    "$repo_root/simulation/vm/simulate.sh" --env "$env_file" destroy >"$tmp_dir/destroy-unowned.out"; then
    printf 'destroy must reject an unowned volume in the selected pool\n' >&2
    exit 1
  fi
  [ -f "$stub_state/domains/loopforge-vm-$run_id-$vm_set_id-gerrit.state" ]
  rm -f "$generated_root/vm-sets/$vm_set_id/libvirt/disks/unowned.qcow2"

  PATH="$stub_bin:$PATH" VM_STUB_STATE="$stub_state" \
    "$repo_root/simulation/vm/simulate.sh" --env "$env_file" destroy >"$tmp_dir/destroy.out"
  grep -Fxq "destroy: ok vm-set=$vm_set_id removed" "$tmp_dir/destroy.out"
  [ ! -e "$generated_root/vm-sets/$vm_set_id" ]
  [ ! -e "$stub_state/network.name" ]
  [ ! -d "$stub_state/pools/loopforge-vm-$run_id-$vm_set_id-images" ]
  find "$stub_state/pools" -mindepth 1 -maxdepth 1 -type d \
    -name 'loopforge-vm-base-*' -print -quit | grep -q .
  [ -f "$generated_root/$run_id/host/artifacts/exported/m5.txt" ]
  [ -f "$generated_root/$run_id/target/evidence/gerrit/m5.txt" ]

  PATH="$stub_bin:$PATH" VM_STUB_STATE="$stub_state" \
    "$repo_root/simulation/vm/simulate.sh" --env "$env_file" audit-state >"$tmp_dir/audit-destroy.out"
  grep -Fxq 'audit-state: ok' "$tmp_dir/audit-destroy.out"
  audit_log="$(find "$generated_root/$run_id/host/logs/harness" -name 'audit-state-*.log' -print | sort | tail -1)"
  grep -Fq 'vm-set=absent vm-resources=absent' "$audit_log"
fi
