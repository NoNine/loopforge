#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
run_id="vm-m3-$$"
vm_set_id="m3-$$"
generated_root="$repo_root/generated/simulation/vm"
cleanup() {
  [ "${VM_TEST_KEEP_TMP:-0}" -eq 1 ] ||
    rm -rf "$tmp_dir" "$generated_root/$run_id" "$generated_root/vm-sets/$vm_set_id" \
      "$generated_root/vm-destroy-recovery-$$" "$generated_root/vm-sets/destroy-recovery-$$"
}
trap cleanup EXIT

env_file="$tmp_dir/harness.env"
stub_bin="$tmp_dir/bin"
stub_state="$tmp_dir/state"
virsh_calls="$tmp_dir/virsh.calls"
mkdir -p "$stub_bin" "$stub_state"

base_image="$tmp_dir/noble-server-cloudimg-amd64.img"
printf 'stub cloud image\n' >"$base_image"

sed \
  -e "s/^HARNESS_RUN_ID=.*/HARNESS_RUN_ID=$run_id/" \
  -e "s/^LOOPFORGE_VM_SET_ID=.*/LOOPFORGE_VM_SET_ID=$vm_set_id/" \
  -e "s|^VM_BASE_IMAGE_PATH=.*|VM_BASE_IMAGE_PATH=$base_image|" \
  -e 's/^VM_OPERATOR_SSH_TIMEOUT_SECONDS=.*/VM_OPERATOR_SSH_TIMEOUT_SECONDS=5/' \
  -e 's/^VM_OPERATOR_SSH_POLL_SECONDS=.*/VM_OPERATOR_SSH_POLL_SECONDS=1/' \
  "$repo_root/simulation/vm/examples/vm.env.example" >"$env_file"

cp "$repo_root/tests/fixtures/vm-libvirt-stub.sh" "$stub_bin/virsh"
chmod +x "$stub_bin/virsh"

cat >"$stub_bin/getent" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-} ${2:-}" in
  "passwd libvirt-qemu") printf 'libvirt-qemu:x:64055:131:Libvirt QEMU,,,:/var/lib/libvirt:/usr/sbin/nologin\n' ;;
  "group kvm") printf 'kvm:x:131:\n' ;;
  *) /usr/bin/getent "$@" ;;
esac
STUB
chmod +x "$stub_bin/getent"

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
  if printf '%s\n' "$*" | grep -Fq '|| true'; then
    printf 'cloud-init readiness must not tolerate failure\n' >&2
    exit 48
  fi
  if [ "${VM_STUB_FAIL_CLOUD_INIT:-0}" = 1 ]; then
    printf 'forced cloud-init failure\n' >&2
    exit 47
  fi
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
grep -Fq 'ownership_schema_version=6' "$marker"
grep -Fq 'disk_ownership=libvirt-managed' "$marker"
grep -Fq 'VM_PROVISIONING_MODEL=cloud-image-clone' "$generated_root/$run_id/host/rendered/harness.runtime.env"
base_volume="$generated_root/vm-sets/$vm_set_id/libvirt/disks/base.qcow2"
vm_set_ssh_dir="$generated_root/vm-sets/$vm_set_id/target-ssh"
vm_set_ssh_identity="$vm_set_ssh_dir/ci-operator"
[ -f "$base_volume" ]
[ -f "$vm_set_ssh_identity" ]
[ -f "$vm_set_ssh_identity.pub" ]
[ ! -f "$generated_root/$run_id/host/target-ssh/ci-operator" ]
[ "$(stat -c %a "$vm_set_ssh_dir")" = 700 ]
[ "$(stat -c %a "$vm_set_ssh_identity")" = 600 ]
[ "$(stat -c %a "$vm_set_ssh_identity.pub")" = 644 ]
[ -f "$generated_root/vm-sets/$vm_set_id/libvirt/base-image.env" ]
grep -Fq "base_image=$base_volume" "$marker"
grep -Fq "base_image_pool_name=loopforge-vm-$run_id-$vm_set_id-images" "$marker"
grep -Fq "base_image_volume_name=base.qcow2" "$marker"
network_xml="$generated_root/vm-sets/$vm_set_id/libvirt/network.xml"
grep -Eq "<bridge name='lf-[0-9a-f]{8}'" "$network_xml"
! grep -Fq "<bridge name='loopforge-vm-" "$network_xml"
grep -Fq "<domain name='example.test' localOnly='yes'/>" "$network_xml"
grep -Fq "<hostname>ldap.example.test</hostname>" "$network_xml"
! grep -Fq "<hostname>ldap</hostname>" "$network_xml"
! grep -Eq "<host mac='52:54:00:[0-9a-f:]{8}' name='ldap' ip='192\\.168\\.126\\.[0-9]+'" "$network_xml"
grep -Eq "<host mac='52:54:00:[0-9a-f:]{8}' ip='192\\.168\\.126\\.[0-9]+'" "$network_xml"
for path in \
  "$generated_root/vm-sets/$vm_set_id" \
  "$generated_root/vm-sets/$vm_set_id/libvirt" \
  "$generated_root/vm-sets/$vm_set_id/libvirt/disks" \
  "$generated_root/vm-sets/$vm_set_id/libvirt/seeds"; do
  [ "$(stat -c %a "$path")" = 711 ]
done
[ "$(stat -c %a "$generated_root/vm-sets/$vm_set_id/libvirt/machines")" = 700 ]
[ "$(stat -c %a "$generated_root/vm-sets/$vm_set_id/libvirt/volumes")" = 700 ]
for machine in bundle-factory ldap gerrit jenkins-controller jenkins-agent; do
  [ -f "$generated_root/vm-sets/$vm_set_id/libvirt/disks/$machine.qcow2" ]
  [ -f "$generated_root/vm-sets/$vm_set_id/libvirt/seeds/$machine-seed.iso" ]
  [ -f "$generated_root/vm-sets/$vm_set_id/libvirt/machines/$machine.env" ]
  volume_xml="$generated_root/vm-sets/$vm_set_id/libvirt/volumes/$machine.xml"
  grep -Fq '<permissions><mode>0600</mode><owner>64055</owner><group>131</group></permissions>' "$volume_xml"
  [ "$(stat -c %a "$generated_root/vm-sets/$vm_set_id/libvirt/seeds/$machine")" = 700 ]
  [ "$(stat -c %a "$generated_root/vm-sets/$vm_set_id/libvirt/seeds/$machine-seed.iso")" = 644 ]
  grep -Fq 'disk_ownership=libvirt-managed' \
    "$generated_root/vm-sets/$vm_set_id/libvirt/machines/$machine.env"
  grep -Fq "volume_name=$machine.qcow2" \
    "$generated_root/vm-sets/$vm_set_id/libvirt/machines/$machine.env"
  grep -Fq "base_image=$base_volume" \
    "$generated_root/vm-sets/$vm_set_id/libvirt/machines/$machine.env"
  grep -Fq "<disk type='file' device='disk'>" \
    "$generated_root/vm-sets/$vm_set_id/libvirt/machines/$machine.xml"
  grep -Fq "<source file='$generated_root/vm-sets/$vm_set_id/libvirt/disks/$machine.qcow2'/>" \
    "$generated_root/vm-sets/$vm_set_id/libvirt/machines/$machine.xml"
  grep -Fq 'shut off' "$stub_state/domains/loopforge-vm-$run_id-$vm_set_id-$machine.state"
done

if PATH="$stub_bin:$PATH" VM_STUB_STATE="$stub_state" VM_STUB_FAIL_CLOUD_INIT=1 \
  "$repo_root/simulation/vm/simulate.sh" --env "$env_file" up >"$tmp_dir/up-cloud-init-failure.out" 2>&1; then
  printf 'up must fail when cloud-init completion fails\n' >&2
  exit 1
fi
grep -Fq 'up: failed reason=vm-set-up' "$tmp_dir/up-cloud-init-failure.out"
cloud_init_failure_log="$(find "$generated_root/$run_id/host/logs/harness" \
  -name 'up-*.log' -print | sort | tail -1)"
grep -Fq 'forced cloud-init failure' "$cloud_init_failure_log"

PATH="$stub_bin:$PATH" VM_STUB_STATE="$stub_state" \
  "$repo_root/simulation/vm/simulate.sh" --env "$env_file" up >"$tmp_dir/up.out"
grep -Fxq "up: ok vm-set=$vm_set_id ssh=ready" "$tmp_dir/up.out"
grep -Fq 'ssh_host=192.168.126.' "$generated_root/vm-sets/$vm_set_id/libvirt/machines/gerrit.env"

PATH="$stub_bin:$PATH" VM_STUB_STATE="$stub_state" \
  "$repo_root/simulation/vm/simulate.sh" --env "$env_file" status >"$tmp_dir/status.out"
grep -Fq 'status: running' "$tmp_dir/status.out"
grep -Fq 'LDAP          ready' "$tmp_dir/status.out"
grep -Fq 'Gerrit URL    http://gerrit.example.test:8080/' "$tmp_dir/status.out"
grep -Fq 'Jenkins URL   http://jenkins-controller.example.test:8080/login' "$tmp_dir/status.out"
grep -Fq '  *For host DNS, run simulation/vm/tools/configure-systemd-resolved.sh --help' "$tmp_dir/status.out"
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

: >"$virsh_calls"
PATH="$stub_bin:$PATH" VM_STUB_STATE="$stub_state" VM_STUB_CALLS="$virsh_calls" \
  "$repo_root/simulation/vm/simulate.sh" --env "$env_file" down >"$tmp_dir/down.out"
grep -Fxq "down: ok vm-set=$vm_set_id" "$tmp_dir/down.out"
grep -Fq 'shut off' "$stub_state/domains/loopforge-vm-$run_id-$vm_set_id-gerrit.state"
down_log="$(find "$generated_root/$run_id/host/logs/harness" -name 'down-*.log' -print | sort | tail -1)"
[ "$(grep -c '^shutdown-request ' "$down_log")" -eq 5 ]
awk '
  /^shutdown-request / { requests++; last_request = NR }
  /^shutdown-state / && !first_state { first_state = NR }
  END { exit !(requests == 5 && first_state && last_request < first_state) }
' "$down_log"
[ "$(grep -c '^shutdown ' "$virsh_calls")" -eq 5 ]
! grep -Fq 'destroy ' "$virsh_calls"

PATH="$stub_bin:$PATH" VM_STUB_STATE="$stub_state" \
  "$repo_root/simulation/vm/simulate.sh" --env "$env_file" up >"$tmp_dir/up-after-down.out"
grep -Fxq "up: ok vm-set=$vm_set_id ssh=ready" "$tmp_dir/up-after-down.out"

stuck_domain="loopforge-vm-$run_id-$vm_set_id-gerrit"
: >"$virsh_calls"
PATH="$stub_bin:$PATH" VM_STUB_STATE="$stub_state" VM_STUB_CALLS="$virsh_calls" \
  VM_STUB_SHUTDOWN_STICKS="$stuck_domain" \
  "$repo_root/simulation/vm/simulate.sh" --env "$env_file" down >"$tmp_dir/down-fallback.out"
grep -Fxq "down: ok vm-set=$vm_set_id" "$tmp_dir/down-fallback.out"
fallback_down_log="$(find "$generated_root/$run_id/host/logs/harness" -name 'down-*.log' -print | sort | tail -1)"
grep -Fq "shutdown-force machine=gerrit domain=$stuck_domain method=destroy" "$fallback_down_log"
grep -Fxq "destroy $stuck_domain" "$virsh_calls"
[ "$(grep -c '^destroy ' "$virsh_calls")" -eq 1 ]
grep -Fq 'shut off' "$stub_state/domains/$stuck_domain.state"

if [ "${VM_TEST_INCLUDE_M5:-0}" -eq 1 ]; then
  vm_set_ssh_public_key="$(cat "$vm_set_ssh_identity.pub")"
  snapshot_dir="$generated_root/vm-sets/$vm_set_id/snapshots"
  for machine in bundle-factory ldap gerrit jenkins-controller jenkins-agent; do
    record="$snapshot_dir/$machine.env"
    [ -f "$record" ]
    grep -Fq 'schema=1' "$record"
    grep -Fq "snapshot_name=loopforge-clean-baseline" "$record"
    [ -f "$stub_state/snapshots/loopforge-vm-$run_id-$vm_set_id-$machine/loopforge-clean-baseline" ]
  done

  seed_iso="$generated_root/vm-sets/$vm_set_id/libvirt/seeds/bundle-factory-seed.iso"
  seed_before="$(stat -c '%i:%Y:%a' "$seed_iso")"
  PATH="$stub_bin:$PATH" VM_STUB_STATE="$stub_state" \
    "$repo_root/simulation/vm/simulate.sh" --env "$env_file" create >"$tmp_dir/create-reuse.out"
  grep -Fxq "create: ok vm-set=$vm_set_id baseline-prereqs=ready baseline-snapshot=ready" \
    "$tmp_dir/create-reuse.out"
  [ "$(stat -c '%i:%Y:%a' "$seed_iso")" = "$seed_before" ]
  [ "$(cat "$vm_set_ssh_identity.pub")" = "$vm_set_ssh_public_key" ]
  reuse_log="$(find "$generated_root/$run_id/host/logs/harness" -name 'create-*.log' -print | sort | tail -1)"
  grep -Fq 'baseline-snapshot=ready source=existing' "$reuse_log"

  mkdir -p "$generated_root/$run_id/host/state"
  touch "$generated_root/$run_id/host/state/mutable-marker"
  printf 'retained\n' >"$generated_root/$run_id/host/artifacts/exported/m5.txt"
  printf 'retained\n' >"$generated_root/$run_id/target/evidence/gerrit/m5.txt"

  PATH="$stub_bin:$PATH" VM_STUB_STATE="$stub_state" \
    "$repo_root/simulation/vm/simulate.sh" --env "$env_file" up >"$tmp_dir/m5-up.out"

  if PATH="$stub_bin:$PATH" VM_STUB_STATE="$stub_state" \
    "$repo_root/simulation/vm/simulate.sh" --env "$env_file" clean >"$tmp_dir/clean-running.out"; then
    printf 'clean must require the VM set to be down\n' >&2
    exit 1
  fi
  grep -Fq 'clean: failed reason=vm-set-running' "$tmp_dir/clean-running.out"

  PATH="$stub_bin:$PATH" VM_STUB_STATE="$stub_state" \
    "$repo_root/simulation/vm/simulate.sh" --env "$env_file" down >"$tmp_dir/m5-down.out"

  : >"$virsh_calls"
  PATH="$stub_bin:$PATH" VM_STUB_STATE="$stub_state" VM_STUB_CALLS="$virsh_calls" \
    "$repo_root/simulation/vm/simulate.sh" --env "$env_file" restore-baseline >"$tmp_dir/restore-baseline.out"
  grep -Fxq "restore-baseline: ok vm-set=$vm_set_id baseline=restored" "$tmp_dir/restore-baseline.out"
  [ "$(grep -c '^snapshot-revert ' "$virsh_calls")" -eq 5 ]
  ! grep -Fq 'shutdown ' "$virsh_calls"
  ! grep -Fq 'destroy ' "$virsh_calls"
  gerrit_machine_metadata="$generated_root/vm-sets/$vm_set_id/libvirt/machines/gerrit.env"
  gerrit_machine_metadata_before="$(mktemp "$tmp_dir/gerrit.env.XXXXXX")"
  cp "$gerrit_machine_metadata" "$gerrit_machine_metadata_before"
  sed -i 's/^base_image_fingerprint=.*/base_image_fingerprint=clean-must-not-care/' \
    "$gerrit_machine_metadata"

  : >"$virsh_calls"
  PATH="$stub_bin:$PATH" VM_STUB_STATE="$stub_state" VM_STUB_CALLS="$virsh_calls" \
    "$repo_root/simulation/vm/simulate.sh" --env "$env_file" clean >"$tmp_dir/clean.out"
  grep -Fxq "clean: ok vm-set=$vm_set_id generated-state=cleaned" "$tmp_dir/clean.out"
  ! grep -Fq 'snapshot-revert ' "$virsh_calls"
  [ ! -e "$generated_root/$run_id/host/state" ]
  [ ! -e "$generated_root/$run_id/host/rendered" ]
  [ ! -e "$generated_root/$run_id/host/runtime-inputs" ]
  [ ! -e "$generated_root/$run_id/host/target-ssh" ]
  [ -f "$vm_set_ssh_identity" ]
  [ "$(cat "$vm_set_ssh_identity.pub")" = "$vm_set_ssh_public_key" ]
  [ -f "$generated_root/$run_id/host/artifacts/exported/m5.txt" ]
  [ -f "$generated_root/$run_id/target/evidence/gerrit/m5.txt" ]
  [ ! -f "$generated_root/$run_id/.loopforge-vm-run.env" ]
  [ ! -f "$generated_root/$run_id/host/rendered/harness.runtime.env" ]
  for machine in bundle-factory ldap gerrit jenkins-controller jenkins-agent; do
    grep -Fq 'shut off' "$stub_state/domains/loopforge-vm-$run_id-$vm_set_id-$machine.state"
  done
  cp "$gerrit_machine_metadata_before" "$gerrit_machine_metadata"

  if PATH="$stub_bin:$PATH" VM_STUB_STATE="$stub_state" \
    "$repo_root/simulation/vm/simulate.sh" --env "$env_file" audit-state >"$tmp_dir/audit-clean.out" 2>&1; then
    printf 'audit-state must fail after clean removes rendered runtime config\n' >&2
    exit 1
  fi
  grep -Fq 'Missing VM harness runtime config' "$tmp_dir/audit-clean.out"

  PATH="$stub_bin:$PATH" VM_STUB_STATE="$stub_state" \
    "$repo_root/simulation/vm/simulate.sh" --env "$env_file" init-run >"$tmp_dir/init-run-after-clean.out"
  grep -Fxq "init-run: ok run-id=$run_id" "$tmp_dir/init-run-after-clean.out"
  grep -Fq "HARNESS_TARGET_SSH_IDENTITY_FILE=$vm_set_ssh_identity" \
    "$generated_root/$run_id/host/rendered/harness.runtime.env"
  [ "$(cat "$vm_set_ssh_identity.pub")" = "$vm_set_ssh_public_key" ]
  PATH="$stub_bin:$PATH" VM_STUB_STATE="$stub_state" \
    "$repo_root/simulation/vm/simulate.sh" --env "$env_file" create >"$tmp_dir/create-after-clean.out"
  grep -Fxq "create: ok vm-set=$vm_set_id baseline-prereqs=ready baseline-snapshot=ready" \
    "$tmp_dir/create-after-clean.out"
  PATH="$stub_bin:$PATH" VM_STUB_STATE="$stub_state" \
    "$repo_root/simulation/vm/simulate.sh" --env "$env_file" up >"$tmp_dir/up-after-clean.out"
  grep -Fxq "up: ok vm-set=$vm_set_id ssh=ready" "$tmp_dir/up-after-clean.out"
  PATH="$stub_bin:$PATH" VM_STUB_STATE="$stub_state" \
    "$repo_root/simulation/vm/simulate.sh" --env "$env_file" down >"$tmp_dir/down-after-clean.out"
  grep -Fxq "down: ok vm-set=$vm_set_id" "$tmp_dir/down-after-clean.out"

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
  [ ! -e "$base_volume" ]
  [ -f "$generated_root/$run_id/host/artifacts/exported/m5.txt" ]
  [ -f "$generated_root/$run_id/target/evidence/gerrit/m5.txt" ]

  PATH="$stub_bin:$PATH" VM_STUB_STATE="$stub_state" \
    "$repo_root/simulation/vm/simulate.sh" --env "$env_file" audit-state >"$tmp_dir/audit-destroy.out"
  grep -Fxq 'audit-state: ok' "$tmp_dir/audit-destroy.out"
  audit_log="$(find "$generated_root/$run_id/host/logs/harness" -name 'audit-state-*.log' -print | sort | tail -1)"
  grep -Fq 'vm-set=absent vm-resources=absent' "$audit_log"

  recovery_run_id="vm-destroy-recovery-$$"
  recovery_vm_set_id="destroy-recovery-$$"
  recovery_env="$tmp_dir/harness-destroy-recovery.env"
  sed \
    -e "s/^HARNESS_RUN_ID=.*/HARNESS_RUN_ID=$recovery_run_id/" \
    -e "s/^LOOPFORGE_VM_SET_ID=.*/LOOPFORGE_VM_SET_ID=$recovery_vm_set_id/" \
    -e "s|^VM_BASE_IMAGE_PATH=.*|VM_BASE_IMAGE_PATH=$base_image|" \
    -e 's/^VM_OPERATOR_SSH_TIMEOUT_SECONDS=.*/VM_OPERATOR_SSH_TIMEOUT_SECONDS=5/' \
    -e 's/^VM_OPERATOR_SSH_POLL_SECONDS=.*/VM_OPERATOR_SSH_POLL_SECONDS=1/' \
    "$repo_root/simulation/vm/examples/vm.env.example" >"$recovery_env"
  PATH="$stub_bin:$PATH" VM_STUB_STATE="$stub_state" \
    "$repo_root/simulation/vm/simulate.sh" --env "$recovery_env" init-run >"$tmp_dir/init-run-destroy-recovery.out"
  PATH="$stub_bin:$PATH" VM_STUB_STATE="$stub_state" \
    "$repo_root/simulation/vm/simulate.sh" --env "$recovery_env" create >"$tmp_dir/create-destroy-recovery.out"
  rm -rf "$generated_root/$recovery_run_id" "$generated_root/vm-sets/$recovery_vm_set_id"
  PATH="$stub_bin:$PATH" VM_STUB_STATE="$stub_state" \
    "$repo_root/simulation/vm/simulate.sh" --env "$recovery_env" destroy >"$tmp_dir/destroy-recovery.out"
  grep -Fxq "destroy: ok vm-set=$recovery_vm_set_id removed" "$tmp_dir/destroy-recovery.out"
  [ ! -d "$stub_state/pools/loopforge-vm-$recovery_run_id-$recovery_vm_set_id-images" ]
  [ ! -f "$stub_state/domains/loopforge-vm-$recovery_run_id-$recovery_vm_set_id-gerrit.state" ]
fi
