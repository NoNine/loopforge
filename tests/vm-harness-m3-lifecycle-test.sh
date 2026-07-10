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

cp "$repo_root/tests/fixtures/vm-libvirt-stub.sh" "$stub_bin/virsh"
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
