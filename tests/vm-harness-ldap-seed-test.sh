#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
run_id="vm-m4-$$"
vm_set_id="m4-$$"
debug_run_id="vm-m4-bake-debug-$$"
debug_vm_set_id="m4-bake-debug-$$"
generated_root="$repo_root/generated/simulation/vm"
cleanup() {
  [ "${VM_TEST_KEEP_TMP:-0}" -eq 1 ] ||
    rm -rf "$tmp_dir" "$generated_root/$run_id" \
      "$generated_root/sets/$vm_set_id" \
      "$generated_root/$debug_run_id" \
      "$generated_root/sets/$debug_vm_set_id"
  rm -f "$generated_root/locks/$vm_set_id.lock" \
    "$generated_root/locks/$debug_vm_set_id.lock"
}
trap cleanup EXIT

env_file="$tmp_dir/harness.env"
stub_bin="$tmp_dir/bin"
stub_state="$tmp_dir/state"
mkdir -p "$stub_bin" "$stub_state"

base_image="$tmp_dir/noble-server-cloudimg-amd64.img"
printf 'stub cloud image for %s\n' "$run_id" >"$base_image"

sed \
  -e "s/^HARNESS_RUN_ID=.*/HARNESS_RUN_ID=$run_id/" \
  -e "s/^HARNESS_SET_ID=.*/HARNESS_SET_ID=$vm_set_id/" \
  -e "s|^VM_BASE_IMAGE_PATH=.*|VM_BASE_IMAGE_PATH=$base_image|" \
  -e 's/^VM_OPERATOR_SSH_TIMEOUT_SECONDS=.*/VM_OPERATOR_SSH_TIMEOUT_SECONDS=5/' \
  -e 's/^VM_OPERATOR_SSH_POLL_SECONDS=.*/VM_OPERATOR_SSH_POLL_SECONDS=1/' \
  -e 's/^VM_DEBUG_PRESERVE_FAILED_BAKE=.*/VM_DEBUG_PRESERVE_FAILED_BAKE=1/' \
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
state_dir="${VM_STUB_STATE:-}"
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
    target="${2:?resize target required}"
    size="${3:?resize size required}"
    if [ -n "$state_dir" ]; then
      printf '%s %s\n' "$target" "$size" >>"$state_dir/qemu-img-resize"
    fi
    ;;
  info)
    image="${@: -1}"
    case "$image" in
      */sets/*/libvirt/disks/*)
        printf 'libvirt-managed volume inspected directly: %s\n' "$image" >&2
        exit 49
        ;;
    esac
    [ -s "$image" ] || exit 1
    if [ "${VM_STUB_FAIL_MODE:-}" = image-info ]; then
      printf 'forced image info failure\n' >&2
      exit 45
    fi
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
cloud_init_command="$(printf '%s\n%s\n' "$*" "$script")"
if printf '%s\n' "$cloud_init_command" | grep -Fq 'cloud-init status --wait'; then
  if printf '%s\n' "$cloud_init_command" | grep -Fq '|| true'; then
    printf 'cloud-init readiness must not tolerate failure\n' >&2
    exit 48
  fi
  printf '%s\n' "cloud-init $host" >>"$state_dir/calls"
  if [ "${VM_STUB_FAIL_MODE:-}" = cloud-init ]; then
    printf 'forced cloud-init failure\n' >&2
    exit 47
  fi
  exit 0
fi
file_host="$(printf '%s\n' "$host" | tr -c 'A-Za-z0-9_.-' '_')"
printf '%s\n' "$script" >"$state_dir/ssh-$file_host-$(date +%s%N).sh"
case "${VM_STUB_FAIL_MODE:-}" in
  apt)
    if printf '%s\n' "$script" | grep -Fq 'apt-get install'; then
      printf 'forced apt failure\n' >&2
      exit 42
    fi
    ;;
  slapd)
    if printf '%s\n' "$script" | grep -Fq 'systemctl enable --now slapd'; then
      printf 'forced slapd failure\n' >&2
      exit 43
    fi
    ;;
  ldap-consumer)
    if printf '%s\n' "$script" | grep -Fq 'uid=test-user'; then
      printf 'forced ldap consumer failure\n' >&2
      exit 44
    fi
    ;;
  ldap-empty)
    if printf '%s\n' "$script" | grep -Fq 'systemctl enable --now slapd'; then
      exit 0
    fi
    ;;
  ldap-add)
    if printf '%s\n' "$script" | grep -Fq 'apply_ldif'; then
      printf 'forced ldapadd failure\n' >&2
      exit 46
    fi
    ;;
esac
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
STUB
chmod +x "$stub_bin/ssh"

assert_operator_seed_policy() {
  local user_data
  user_data="${1:?user data required}"
  [ -f "$user_data" ]
  grep -Fq 'lock_passwd: true' "$user_data"
  grep -Fq 'disable_root: true' "$user_data"
  grep -Fq 'path: /etc/ssh/sshd_config.d/40-loopforge-operator.conf' "$user_data"
  grep -Fq 'owner: root:root' "$user_data"
  grep -Fq "Match User ci-operator" "$user_data"
  grep -Fq 'AuthenticationMethods publickey' "$user_data"
  grep -Fq 'PasswordAuthentication no' "$user_data"
  grep -Fq 'KbdInteractiveAuthentication no' "$user_data"
  grep -Fq 'PermitEmptyPasswords no' "$user_data"
  grep -Fq '/usr/sbin/sshd -t && systemctl enable --now ssh && systemctl reload ssh' \
    "$user_data"
  if grep -Fq 'ssh_pwauth:' "$user_data" || grep -Eq 'systemctl[[:space:]]+restart[[:space:]]+ssh' "$user_data"; then
    printf 'VM seed must not trigger a cloud-init SSH restart: %s\n' "$user_data" >&2
    exit 1
  fi
}

invalid_debug_env="$tmp_dir/harness-invalid-debug.env"
sed 's/^VM_DEBUG_PRESERVE_FAILED_BAKE=.*/VM_DEBUG_PRESERVE_FAILED_BAKE=yes/' \
  "$env_file" >"$invalid_debug_env"
if PATH="$stub_bin:$PATH" VM_STUB_STATE="$stub_state" \
  "$repo_root/simulation/vm/simulate.sh" --env "$invalid_debug_env" preflight \
  >"$tmp_dir/preflight-invalid-debug.out" 2>&1; then
  printf 'VM bake debug preservation must reject non-boolean values\n' >&2
  exit 1
fi
grep -Fq 'VM_DEBUG_PRESERVE_FAILED_BAKE must be 0 or 1' \
  "$tmp_dir/preflight-invalid-debug.out"

[ -f "$repo_root/simulation/vm/ldap/50-harness-seed.ldif" ]
grep -Fq 'uid=gerrit-admin' "$repo_root/simulation/vm/ldap/50-harness-seed.ldif"
grep -Fq 'cn=jenkins-admins' "$repo_root/simulation/vm/ldap/50-harness-seed.ldif"

PATH="$stub_bin:$PATH" VM_STUB_STATE="$stub_state" \
  "$repo_root/simulation/vm/simulate.sh" --env "$env_file" init-run >"$tmp_dir/init-run.out"
grep -Fxq "init-run: ok set-id=$vm_set_id run-id=$run_id" "$tmp_dir/init-run.out"

PATH="$stub_bin:$PATH" VM_STUB_STATE="$stub_state" \
  "$repo_root/simulation/vm/simulate.sh" --env "$env_file" create >"$tmp_dir/create.out"
grep -Fxq "create: ok set-id=$vm_set_id baseline-prereqs=ready baseline-snapshot=ready" "$tmp_dir/create.out"

marker="$generated_root/sets/$vm_set_id/.loopforge-vm-baseline-prereqs.env"
[ -f "$marker" ]
grep -Fq 'status=ready' "$marker"
grep -Fq 'schema=2' "$marker"
grep -Fq 'apt_mirror=http://mirrors.tuna.tsinghua.edu.cn/ubuntu/' "$marker"
grep -Fq 'ldap_bind_dn=cn=readonly,dc=example,dc=test' "$marker"
grep -Fq 'base_image_fingerprint=' "$marker"
grep -Fq 'base_image_sha256=' "$marker"
network_xml="$generated_root/sets/$vm_set_id/libvirt/network.xml"
grep -Eq "<bridge name='lf-[0-9a-f]{12}'" "$network_xml"
! grep -Fq "<bridge name='loopforge-vm-" "$network_xml"
grep -Fq "<domain name='example.test' localOnly='yes'/>" "$network_xml"
grep -Fq "<hostname>ldap.example.test</hostname>" "$network_xml"
grep -Fq "<hostname>gerrit.example.test</hostname>" "$network_xml"
! grep -Fq "<hostname>ldap</hostname>" "$network_xml"
! grep -Eq "<host mac='52:54:00:[0-9a-f:]{8}' name='ldap' ip='192\\.168\\.126\\.[0-9]+'" "$network_xml"
grep -Eq "<host mac='52:54:00:[0-9a-f:]{8}' ip='192\\.168\\.126\\.[0-9]+'" "$network_xml"
ldap_network_config="$generated_root/sets/$vm_set_id/libvirt/seeds/ldap/network-config"
gerrit_network_config="$generated_root/sets/$vm_set_id/libvirt/seeds/gerrit/network-config"
grep -Fq 'nameservers:' "$ldap_network_config"
grep -Fq '        - 192.168.126.1' "$ldap_network_config"
grep -Fq '      search:' "$ldap_network_config"
grep -Fq '        - example.test' "$ldap_network_config"
grep -Fq 'nameservers:' "$gerrit_network_config"
grep -Fq '        - 192.168.126.1' "$gerrit_network_config"
grep -Fq '      search:' "$gerrit_network_config"
grep -Fq '        - example.test' "$gerrit_network_config"
for machine in bundle-factory ldap gerrit jenkins-controller jenkins-agent; do
  grep -Fq 'shut off' "$stub_state/domains/loopforge-vm-$vm_set_id-$machine.state"
  grep -Fq 'disk_virtual_size_bytes=21474836480' \
    "$generated_root/sets/$vm_set_id/libvirt/machines/$machine.env"
  grep -Fq 'disk_ownership=libvirt-managed' \
    "$generated_root/sets/$vm_set_id/libvirt/machines/$machine.env"
  grep -Fq "volume_name=$machine.qcow2" \
    "$generated_root/sets/$vm_set_id/libvirt/machines/$machine.env"
done

create_log="$(find "$generated_root/$run_id/host/logs/harness" -name 'create-*.log' -print | sort | tail -1)"
grep -Fq 'apt-mirror=http://mirrors.tuna.tsinghua.edu.cn/ubuntu/' "$create_log"
grep -Fq 'base-image=ready source=bake' "$create_log"
grep -Fq 'base-image-ownership=libvirt-managed' "$create_log"
grep -Fq 'base-image-bake=ready' "$create_log"
grep -Fq 'source=base-image' "$create_log"
grep -Fq 'ldap-service=ready host=ldap.example.test port=389' "$create_log"
grep -Fq 'ldap-consumer=gerrit reachable host=ldap.example.test port=389' "$create_log"
grep -Fq 'ldap-consumer=jenkins-controller reachable host=ldap.example.test port=389' "$create_log"
grep -Fq 'ldap-seed-entry=ready type=user id=jenkins-admin' "$create_log"
grep -Fq 'ldap-seed-entry=ready type=group id=jenkins-admins' "$create_log"
grep -Fq 'ldap-consumer-bind-search=ready machine=gerrit id=test-user' "$create_log"
grep -Fq 'baseline-prereqs=ready marker=' "$create_log"
awk '
  /^cloud-init / && !cloud_init { cloud_init=NR }
  /^os-baseline / && !os_baseline { os_baseline=NR }
  END { exit !(cloud_init && os_baseline && cloud_init < os_baseline) }
' "$stub_state/calls"
[ ! -e "$generated_root/sets/$vm_set_id/.loopforge-vm-bake-debug.env" ]
if find "$generated_root/sets/$vm_set_id/libvirt" -maxdepth 1 \
  -type d -name 'bake-work-*' -print -quit | grep -q .; then
  printf 'successful debug-enabled bake must remove its work directory\n' >&2
  exit 1
fi
[ ! -e "$stub_state/domains/loopforge-vm-$vm_set_id-base-image-bake.state" ]
for machine in bundle-factory ldap gerrit jenkins-controller jenkins-agent; do
  assert_operator_seed_policy \
    "$generated_root/sets/$vm_set_id/libvirt/seeds/$machine/user-data"
done

ldap_evidence="$(find "$generated_root/$run_id/host/evidence/harness" -name 'create-ldap-*.json' -print | sort | tail -1)"
[ -n "$ldap_evidence" ]
python3 - "$ldap_evidence" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    evidence = json.load(handle)
assert evidence["verification_mode"] == "vm-simulation"
assert evidence["ldap_endpoint"] == "ldap://ldap.example.test:389"
assert evidence["ldap_label"] == "simulation-only"
assert evidence["seeded_accounts"] == ["gerrit-admin", "jenkins-admin", "test-user"]
assert evidence["seeded_groups"] == ["gerrit-admins", "jenkins-admins"]
assert evidence["local_bind_search"] == "pass"
assert evidence["consumer_bind_search"] == {"gerrit": "pass", "jenkins-controller": "pass"}
assert evidence["redaction"] == "secrets-not-recorded"
PY
! grep -Fq 'readonly-password' "$ldap_evidence"

baked_marker="$generated_root/sets/$vm_set_id/libvirt/base-image.env"
[ -f "$baked_marker" ]
grep -Fq 'schema=7' "$baked_marker"
grep -Fq 'status=ready' "$baked_marker"
grep -Fq 'image_ownership=libvirt-managed' "$baked_marker"
grep -Fq "baked_image=$generated_root/sets/$vm_set_id/libvirt/disks/base.qcow2" "$baked_marker"
grep -Fq "storage_pool_name=loopforge-vm-$vm_set_id-images" "$baked_marker"
grep -Fq 'volume_name=base.qcow2' "$baked_marker"
grep -Fq 'disk_size=20G' "$baked_marker"
grep -Fq 'packages=ca-certificates,curl,fontconfig,git,ldap-utils,nfs-common,nfs-kernel-server,openjdk-21-jre,openjdk-21-jre-headless,openssh-client,openssh-server,rsync,slapd,tar,unzip,wget' "$baked_marker"
grep -Eq "/sets/$vm_set_id/libvirt/bake-work-[^/]+/base-build\\.qcow2 20G$" "$stub_state/qemu-img-resize"

grep -Fq 'os-baseline' "$stub_state/calls"
grep -Fq 'ldap-service' "$stub_state/calls"
grep -Fq 'ldap-consumer' "$stub_state/calls"

apt_install_count="$(grep -R -l -F 'apt-get install' "$stub_state"/ssh-*.sh | wc -l)"
[ "$apt_install_count" -eq 1 ]

for script in "$stub_state"/ssh-*.sh; do
  if grep -Fq 'apt-get install' "$script"; then
    grep -Fq 'mirrors.tuna.tsinghua.edu.cn/ubuntu/' "$script"
    grep -Fq 'dpkg-query -W' "$script"
    grep -Fq 'check_package_command "$package"' "$script"
  fi
done

grep -R -Fq 'LDAP_BIND_PASSWORD=' "$stub_state"/ssh-*.sh
! grep -R -Fq -- '-w readonly-password' "$stub_state"/ssh-*.sh
grep -R -Fq 'uid=test-user' "$stub_state"/ssh-*.sh
grep -R -Fq 'systemctl is-active --quiet slapd' "$stub_state"/ssh-*.sh
grep -R -Fq -- '-H ldap://127.0.0.1:389' "$stub_state"/ssh-*.sh
grep -R -Fq 'ldap://$ldap_host:$ldap_port' "$stub_state"/ssh-*.sh
grep -R -Fq 'grep -Fxi "dn: $expected_dn"' "$stub_state"/ssh-*.sh
grep -R -Fq 'Already exists (68)' "$stub_state"/ssh-*.sh
grep -R -Fq 'deadline=$((SECONDS + ldap_timeout))' "$stub_state"/ssh-*.sh
grep -R -Fq 'sleep "$ldap_poll"' "$stub_state"/ssh-*.sh
grep -R -Fq 'getent hosts "$ldap_host"' "$stub_state"/ssh-*.sh
grep -R -Fq '</dev/tcp/$ldap_host/$ldap_port' "$stub_state"/ssh-*.sh
consumer_script_count=0
for script in "$stub_state"/ssh-*.sh; do
  if grep -Fq 'LDAP consumer diagnostics' "$script"; then
    consumer_script_count=$((consumer_script_count + 1))
    grep -Fq 'getent hosts "$ldap_host"' "$script"
    grep -Fq '</dev/tcp/$ldap_host/$ldap_port' "$script"
    grep -Fq 'ldapsearch -x -H ldap://$ldap_host:$ldap_port' "$script"
    ! grep -Fq 'deadline=$((SECONDS + ldap_timeout))' "$script"
    ! grep -Fq 'sleep "$ldap_poll"' "$script"
  fi
done
[ "$consumer_script_count" -eq 2 ]

runtime_env="$generated_root/$run_id/host/rendered/harness.runtime.env"
rendered_env="$generated_root/$run_id/host/rendered/harness.env"
grep -Fq 'HARNESS_LDAP_HOST=ldap.example.test' "$runtime_env"
grep -Fq 'HARNESS_LDAP_HOST=ldap.example.test' "$rendered_env"
grep -Fq 'HARNESS_LDAP_BIND_PASSWORD=readonly-password' "$runtime_env"
grep -Fq 'HARNESS_LDAP_BIND_PASSWORD=readonly-password' "$rendered_env"
grep -Fq 'VM_DEBUG_PRESERVE_FAILED_BAKE=1' "$runtime_env"
grep -Fq 'VM_DEBUG_PRESERVE_FAILED_BAKE=1' "$rendered_env"
grep -Fq 'HARNESS_LDAP_BIND_PASSWORD=readonly-password' "$generated_root/$run_id/host/source-inputs/harness.env"
if grep -R --include='*.env' -Fq 'HARNESS_LDAP_BIND_PASSWORD=simulation-owned-redacted' "$generated_root/$run_id"; then
  printf 'VM runtime files must not replace the simulation LDAP bind password with a redaction marker\n' >&2
  exit 1
fi

marker_backup="$tmp_dir/baseline-prereqs.env"
cp "$marker" "$marker_backup"
sed -i 's/^status=ready$/status=broken/' "$marker"
PATH="$stub_bin:$PATH" VM_STUB_STATE="$stub_state" \
  "$repo_root/simulation/vm/simulate.sh" --env "$env_file" status >"$tmp_dir/status-stale.out"
grep -Eq 'LDAP[[:space:]]+stale' "$tmp_dir/status-stale.out"
if PATH="$stub_bin:$PATH" VM_STUB_STATE="$stub_state" \
  "$repo_root/simulation/vm/simulate.sh" --env "$env_file" audit-state >"$tmp_dir/audit-stale.out" 2>&1; then
  printf 'audit-state must fail for a stale baseline prerequisite marker\n' >&2
  exit 1
fi
grep -Fq 'Stale VM baseline prerequisite marker' "$tmp_dir/audit-stale.out"
mv "$marker_backup" "$marker"

machine_metadata="$generated_root/sets/$vm_set_id/libvirt/machines/gerrit.env"
machine_metadata_backup="$tmp_dir/gerrit.env"
cp "$machine_metadata" "$machine_metadata_backup"
marker_sha_before="$(sha256sum "$marker" | awk '{print $1}')"
sed -i 's/^base_image_fingerprint=.*/base_image_fingerprint=incompatible/' "$machine_metadata"
if PATH="$stub_bin:$PATH" VM_STUB_STATE="$stub_state" \
  "$repo_root/simulation/vm/simulate.sh" --env "$env_file" create >"$tmp_dir/create-incompatible.out" 2>&1; then
  printf 'create must reject incompatible existing VM disk metadata\n' >&2
  exit 1
fi
incompatible_log="$(find "$generated_root/$run_id/host/logs/harness" -name 'create-*.log' -print | sort | tail -1)"
grep -Fq 'Select a fresh HARNESS_RUN_ID and HARNESS_SET_ID' "$incompatible_log"
[ "$(sha256sum "$marker" | awk '{print $1}')" = "$marker_sha_before" ]
grep -Fq 'base_image_fingerprint=incompatible' "$machine_metadata"
mv "$machine_metadata_backup" "$machine_metadata"

run_fail_closed_case() {
  local mode case_bake_domain case_base_image case_run_id case_vm_set_id case_env case_generated case_marker case_failure_text
  mode="${1:?mode required}"
  case_failure_text="${2:?failure text required}"
  case_run_id="vm-m4-$mode-$$"
  case_vm_set_id="m4-$mode-$$"
  case_env="$tmp_dir/harness-$mode.env"
  case_generated="$generated_root/$case_run_id"
  case_marker="$generated_root/sets/$case_vm_set_id/.loopforge-vm-baseline-prereqs.env"
  case_bake_domain="loopforge-vm-$case_vm_set_id-base-image-bake"
  case_base_image="$base_image"
  if [ "$mode" = apt ] || [ "$mode" = image-info ] || [ "$mode" = cloud-init ]; then
    case_base_image="$tmp_dir/noble-server-cloudimg-amd64-$mode.img"
    printf 'stub cloud image for forced %s failure\n' "$mode" >"$case_base_image"
  fi

  sed \
    -e "s/^HARNESS_RUN_ID=.*/HARNESS_RUN_ID=$case_run_id/" \
    -e "s/^HARNESS_SET_ID=.*/HARNESS_SET_ID=$case_vm_set_id/" \
    -e "s|^VM_BASE_IMAGE_PATH=.*|VM_BASE_IMAGE_PATH=$case_base_image|" \
    -e 's/^VM_OPERATOR_SSH_TIMEOUT_SECONDS=.*/VM_OPERATOR_SSH_TIMEOUT_SECONDS=5/' \
    -e 's/^VM_OPERATOR_SSH_POLL_SECONDS=.*/VM_OPERATOR_SSH_POLL_SECONDS=1/' \
    "$repo_root/simulation/vm/examples/vm.env.example" >"$case_env"

  PATH="$stub_bin:$PATH" VM_STUB_STATE="$stub_state" \
    "$repo_root/simulation/vm/simulate.sh" --env "$case_env" init-run >"$tmp_dir/init-run-$mode.out"

  : >"$stub_state/calls"
  if PATH="$stub_bin:$PATH" VM_STUB_STATE="$stub_state" VM_STUB_FAIL_MODE="$mode" \
    "$repo_root/simulation/vm/simulate.sh" --env "$case_env" create >"$tmp_dir/create-$mode.out" 2>&1; then
    printf 'create must fail closed for forced %s failure\n' "$mode" >&2
    exit 1
  fi
  grep -Fq 'create: failed reason=vm-set-create' "$tmp_dir/create-$mode.out"
  ! grep -Fq 'baseline-prereqs=ready' "$tmp_dir/create-$mode.out"
  [ ! -f "$case_marker" ]
  if [ -d "$case_generated/host/logs/harness" ]; then
    case_create_log="$(find "$case_generated/host/logs/harness" -name 'create-*.log' -print | sort | tail -1)"
    [ -n "$case_create_log" ]
    grep -Fq "$case_failure_text" "$case_create_log"
  fi
  [ ! -e "$stub_state/domains/$case_bake_domain.state" ]
  if [ "$mode" = cloud-init ] && grep -Fq 'os-baseline ' "$stub_state/calls"; then
    printf 'package installation must not run after cloud-init failure\n' >&2
    exit 1
  fi
  if [ -d "$generated_root/sets/$case_vm_set_id/libvirt" ] &&
    find "$generated_root/sets/$case_vm_set_id/libvirt" -maxdepth 1 \
      -type d -name 'bake-work-*' -print -quit | grep -q .; then
    printf 'default bake failure cleanup must remove its work directory\n' >&2
    exit 1
  fi
  rm -rf "$case_generated" "$generated_root/sets/$case_vm_set_id"
}

run_fail_closed_case apt 'forced apt failure'
run_fail_closed_case cloud-init 'forced cloud-init failure'
run_fail_closed_case image-info 'VM baked base image is not a valid libvirt-managed qcow2 volume'
run_fail_closed_case slapd 'forced slapd failure'
run_fail_closed_case ldap-consumer 'forced ldap consumer failure'
run_fail_closed_case ldap-empty 'Missing exact VM LDAP seed proof'
run_fail_closed_case ldap-add 'forced ldapadd failure'

debug_env="$tmp_dir/harness-bake-debug.env"
debug_base_image="$tmp_dir/noble-server-cloudimg-amd64-bake-debug.img"
printf 'stub cloud image for %s\n' "$debug_run_id" >"$debug_base_image"
sed \
  -e "s/^HARNESS_RUN_ID=.*/HARNESS_RUN_ID=$debug_run_id/" \
  -e "s/^HARNESS_SET_ID=.*/HARNESS_SET_ID=$debug_vm_set_id/" \
  -e "s|^VM_BASE_IMAGE_PATH=.*|VM_BASE_IMAGE_PATH=$debug_base_image|" \
  -e 's/^VM_OPERATOR_SSH_TIMEOUT_SECONDS=.*/VM_OPERATOR_SSH_TIMEOUT_SECONDS=5/' \
  -e 's/^VM_OPERATOR_SSH_POLL_SECONDS=.*/VM_OPERATOR_SSH_POLL_SECONDS=1/' \
  -e 's/^VM_DEBUG_PRESERVE_FAILED_BAKE=.*/VM_DEBUG_PRESERVE_FAILED_BAKE=1/' \
  "$repo_root/simulation/vm/examples/vm.env.example" >"$debug_env"

PATH="$stub_bin:$PATH" VM_STUB_STATE="$stub_state" \
  "$repo_root/simulation/vm/simulate.sh" --env "$debug_env" init-run \
  >"$tmp_dir/init-run-bake-debug.out"
if PATH="$stub_bin:$PATH" VM_STUB_STATE="$stub_state" VM_STUB_FAIL_MODE=apt \
  "$repo_root/simulation/vm/simulate.sh" --env "$debug_env" create \
  >"$tmp_dir/create-bake-debug.out" 2>&1; then
  printf 'debug-enabled bake must still fail closed\n' >&2
  exit 1
fi
grep -Fq 'create: failed reason=vm-set-create' "$tmp_dir/create-bake-debug.out"

debug_set_dir="$generated_root/sets/$debug_vm_set_id"
debug_marker="$debug_set_dir/.loopforge-vm-bake-debug.env"
debug_domain="loopforge-vm-$debug_vm_set_id-base-image-bake"
[ -f "$debug_marker" ]
[ "$(stat -c '%a' "$debug_marker")" = 600 ]
grep -Fq 'schema=1' "$debug_marker"
grep -Fq 'status=failed-preserved' "$debug_marker"
grep -Fq "domain=$debug_domain" "$debug_marker"
grep -Fq 'cleanup_command=destroy' "$debug_marker"
debug_work_dir="$(sed -n 's/^work_dir=//p' "$debug_marker")"
debug_bake_disk="$(sed -n 's/^bake_disk=//p' "$debug_marker")"
debug_seed_iso="$(sed -n 's/^seed_iso=//p' "$debug_marker")"
debug_domain_xml="$(sed -n 's/^domain_xml=//p' "$debug_marker")"
[ -d "$debug_work_dir" ]
[ -f "$debug_bake_disk" ]
[ -f "$debug_seed_iso" ]
[ -f "$debug_domain_xml" ]
assert_operator_seed_policy "$debug_work_dir/seed/user-data"
grep -Fq 'running' "$stub_state/domains/$debug_domain.state"
debug_create_log="$(find "$generated_root/$debug_run_id/host/logs/harness" \
  -name 'create-*.log' -print | sort | tail -1)"
grep -Fq 'base-image-bake-debug=preserved' "$debug_create_log"
grep -Fq 'cleanup=destroy' "$debug_create_log"

debug_marker_sha="$(sha256sum "$debug_marker" | awk '{print $1}')"
if PATH="$stub_bin:$PATH" VM_STUB_STATE="$stub_state" \
  "$repo_root/simulation/vm/simulate.sh" --env "$debug_env" create \
  >"$tmp_dir/create-bake-debug-rerun.out" 2>&1; then
  printf 'create must not replace preserved bake evidence\n' >&2
  exit 1
fi
debug_rerun_log="$(find "$generated_root/$debug_run_id/host/logs/harness" \
  -name 'create-*.log' -print | sort | tail -1)"
grep -Fq 'Preserved VM base-image bake state exists' "$debug_rerun_log"
[ "$(sha256sum "$debug_marker" | awk '{print $1}')" = "$debug_marker_sha" ]
[ -d "$debug_work_dir" ]
grep -Fq 'running' "$stub_state/domains/$debug_domain.state"

PATH="$stub_bin:$PATH" VM_STUB_STATE="$stub_state" \
  "$repo_root/simulation/vm/simulate.sh" --env "$debug_env" destroy \
  >"$tmp_dir/destroy-bake-debug.out"
grep -Fxq "destroy: ok set-id=$debug_vm_set_id removed" \
  "$tmp_dir/destroy-bake-debug.out"
[ ! -e "$debug_set_dir" ]
[ ! -e "$stub_state/domains/$debug_domain.state" ]
