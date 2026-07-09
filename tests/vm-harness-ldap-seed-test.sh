#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
run_id="vm-m4-$$"
vm_set_id="m4-$$"
generated_root="$repo_root/generated/simulation/vm"
baked_cache_dir=""
case_baked_cache_dirs="$tmp_dir/case-baked-cache-dirs"
trap 'if [ -f "$case_baked_cache_dirs" ]; then xargs -r rm -rf <"$case_baked_cache_dirs"; fi; rm -rf "$tmp_dir" "$generated_root/$run_id" "$generated_root/vm-sets/$vm_set_id" "$baked_cache_dir"' EXIT

env_file="$tmp_dir/harness.env"
stub_bin="$tmp_dir/bin"
stub_state="$tmp_dir/state"
mkdir -p "$stub_bin" "$stub_state"

base_image="$tmp_dir/noble-server-cloudimg-amd64.img"
printf 'stub cloud image for %s\n' "$run_id" >"$base_image"

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
  destroy)
    domain="${1:?domain required}"
    printf 'shut off\n' >"$state_dir/domains/$domain.state"
    ;;
  undefine)
    domain="${1:?domain required}"
    rm -f "$state_dir/domains/$domain.state"
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
state_dir="${VM_STUB_STATE:-}"
case "${1:-}" in
  create)
    output="${@: -1}"
    mkdir -p "$(dirname "$output")"
    printf 'qcow2 stub\n' >"$output"
    ;;
  resize)
    target="${2:?resize target required}"
    size="${3:?resize size required}"
    if [ -n "$state_dir" ]; then
      printf '%s %s\n' "$target" "$size" >>"$state_dir/qemu-img-resize"
    fi
    ;;
  info)
    image="${2:?image required}"
    [ -s "$image" ] || exit 1
    if [ "${VM_STUB_FAIL_MODE:-}" = image-info ]; then
      printf 'forced image info failure\n' >&2
      exit 45
    fi
    printf 'image: %s\nfile format: qcow2\n' "$image"
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
grep -Eq "<bridge name='lf-[0-9a-f]{8}'" "$network_xml"
! grep -Fq "<bridge name='loopforge-vm-" "$network_xml"
grep -Fq "<hostname>ldap.example.test</hostname>" "$network_xml"
grep -Fq "<hostname>gerrit.example.test</hostname>" "$network_xml"
! grep -Fq "<hostname>ldap</hostname>" "$network_xml"
! grep -Eq "<host mac='52:54:00:[0-9a-f:]{8}' name='ldap' ip='192\\.168\\.126\\.[0-9]+'" "$network_xml"
grep -Eq "<host mac='52:54:00:[0-9a-f:]{8}' ip='192\\.168\\.126\\.[0-9]+'" "$network_xml"
ldap_network_config="$generated_root/vm-sets/$vm_set_id/libvirt/seeds/ldap/network-config"
gerrit_network_config="$generated_root/vm-sets/$vm_set_id/libvirt/seeds/gerrit/network-config"
grep -Fq 'nameservers:' "$ldap_network_config"
grep -Fq '        - 192.168.126.1' "$ldap_network_config"
grep -Fq '      search:' "$ldap_network_config"
grep -Fq '        - example.test' "$ldap_network_config"
grep -Fq 'nameservers:' "$gerrit_network_config"
grep -Fq '        - 192.168.126.1' "$gerrit_network_config"
grep -Fq '      search:' "$gerrit_network_config"
grep -Fq '        - example.test' "$gerrit_network_config"
for machine in bundle-factory ldap gerrit jenkins-controller jenkins-agent; do
  grep -Fq 'shut off' "$stub_state/domains/loopforge-vm-$run_id-$vm_set_id-$machine.state"
done

create_log="$(find "$generated_root/$run_id/host/logs/harness" -name 'create-*.log' -print | sort | tail -1)"
grep -Fq 'apt-mirror=http://mirrors.tuna.tsinghua.edu.cn/ubuntu/' "$create_log"
grep -Fq 'base-image-cache=miss' "$create_log"
grep -Fq 'base-image-permissions=ready' "$create_log"
grep -Fq 'base-image-bake=ready' "$create_log"
grep -Fq 'source=base-image' "$create_log"
grep -Fq 'ldap-service=ready host=ldap.example.test port=389' "$create_log"
grep -Fq 'ldap-consumer=gerrit reachable host=ldap.example.test port=389' "$create_log"
grep -Fq 'ldap-consumer=jenkins-controller reachable host=ldap.example.test port=389' "$create_log"

baked_marker="$(find "$generated_root/base-images" -name .loopforge-vm-base-image.env -print 2>/dev/null |
  while IFS= read -r marker_file; do
    if grep -Fxq "source_image=$base_image" "$marker_file"; then
      printf '%s\n' "$marker_file"
      break
    fi
  done)"
[ -n "$baked_marker" ]
baked_cache_dir="$(dirname "$baked_marker")"
grep -Fq 'status=ready' "$baked_marker"
grep -Fq 'disk_size=20G' "$baked_marker"
grep -Fq 'packages=ca-certificates,curl,fontconfig,git,ldap-utils,openjdk-21-jre,openjdk-21-jre-headless,openssh-client,openssh-server,rsync,slapd,tar,unzip,wget' "$baked_marker"
grep -Eq '/base-images/.*/bake-work/base-build\.qcow2 20G$' "$stub_state/qemu-img-resize"

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
grep -R -Fq 'ldapsearch -x -H ldap://127.0.0.1:389' "$stub_state"/ssh-*.sh
grep -R -Fq 'ldap://$ldap_host:$ldap_port' "$stub_state"/ssh-*.sh
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
grep -Fq 'HARNESS_LDAP_BIND_PASSWORD=simulation-owned-redacted' "$runtime_env"
grep -Fq 'HARNESS_LDAP_BIND_PASSWORD=simulation-owned-redacted' "$rendered_env"
if grep -R --include='*.env' -Fq 'HARNESS_LDAP_BIND_PASSWORD=readonly-password' "$generated_root/$run_id"; then
  printf 'VM runtime files must not persist the raw LDAP bind password\n' >&2
  exit 1
fi

cache_hit_run_id="vm-m4-cache-hit-$$"
cache_hit_vm_set_id="m4-cache-hit-$$"
cache_hit_env="$tmp_dir/harness-cache-hit.env"
sed \
  -e "s/^HARNESS_RUN_ID=.*/HARNESS_RUN_ID=$cache_hit_run_id/" \
  -e "s/^LOOPFORGE_VM_SET_ID=.*/LOOPFORGE_VM_SET_ID=$cache_hit_vm_set_id/" \
  -e "s|^VM_BASE_IMAGE_PATH=.*|VM_BASE_IMAGE_PATH=$base_image|" \
  -e 's/^VM_OPERATOR_SSH_TIMEOUT_SECONDS=.*/VM_OPERATOR_SSH_TIMEOUT_SECONDS=5/' \
  -e 's/^VM_OPERATOR_SSH_POLL_SECONDS=.*/VM_OPERATOR_SSH_POLL_SECONDS=1/' \
  "$repo_root/simulation/vm/example.env" >"$cache_hit_env"

before_cache_hit_apt_count="$(grep -R -l -F 'apt-get install' "$stub_state"/ssh-*.sh | wc -l)"
PATH="$stub_bin:$PATH" VM_STUB_STATE="$stub_state" \
  "$repo_root/simulation/vm/simulate.sh" --env "$cache_hit_env" init-run >"$tmp_dir/init-run-cache-hit.out"
PATH="$stub_bin:$PATH" VM_STUB_STATE="$stub_state" \
  "$repo_root/simulation/vm/simulate.sh" --env "$cache_hit_env" create >"$tmp_dir/create-cache-hit.out"
grep -Fxq "create: ok vm-set=$cache_hit_vm_set_id baseline-prereqs=ready" "$tmp_dir/create-cache-hit.out"
cache_hit_log="$(find "$generated_root/$cache_hit_run_id/host/logs/harness" -name 'create-*.log' -print | sort | tail -1)"
grep -Fq 'base-image-cache=hit' "$cache_hit_log"
after_cache_hit_apt_count="$(grep -R -l -F 'apt-get install' "$stub_state"/ssh-*.sh | wc -l)"
[ "$after_cache_hit_apt_count" -eq "$before_cache_hit_apt_count" ]
rm -rf "$generated_root/$cache_hit_run_id" "$generated_root/vm-sets/$cache_hit_vm_set_id"

run_fail_closed_case() {
  local mode case_baked_cache_dir case_base_image case_run_id case_vm_set_id case_env case_generated case_marker case_failure_text
  mode="${1:?mode required}"
  case_failure_text="${2:?failure text required}"
  case_run_id="vm-m4-$mode-$$"
  case_vm_set_id="m4-$mode-$$"
  case_env="$tmp_dir/harness-$mode.env"
  case_generated="$generated_root/$case_run_id"
  case_marker="$generated_root/vm-sets/$case_vm_set_id/.loopforge-vm-baseline-prereqs.env"
  case_base_image="$base_image"
  if [ "$mode" = apt ] || [ "$mode" = image-info ]; then
    case_base_image="$tmp_dir/noble-server-cloudimg-amd64-$mode.img"
    printf 'stub cloud image for forced %s failure\n' "$mode" >"$case_base_image"
  fi

  sed \
    -e "s/^HARNESS_RUN_ID=.*/HARNESS_RUN_ID=$case_run_id/" \
    -e "s/^LOOPFORGE_VM_SET_ID=.*/LOOPFORGE_VM_SET_ID=$case_vm_set_id/" \
    -e "s|^VM_BASE_IMAGE_PATH=.*|VM_BASE_IMAGE_PATH=$case_base_image|" \
    -e 's/^VM_OPERATOR_SSH_TIMEOUT_SECONDS=.*/VM_OPERATOR_SSH_TIMEOUT_SECONDS=5/' \
    -e 's/^VM_OPERATOR_SSH_POLL_SECONDS=.*/VM_OPERATOR_SSH_POLL_SECONDS=1/' \
    "$repo_root/simulation/vm/example.env" >"$case_env"

  PATH="$stub_bin:$PATH" VM_STUB_STATE="$stub_state" \
    "$repo_root/simulation/vm/simulate.sh" --env "$case_env" init-run >"$tmp_dir/init-run-$mode.out"

  if PATH="$stub_bin:$PATH" VM_STUB_STATE="$stub_state" VM_STUB_FAIL_MODE="$mode" \
    "$repo_root/simulation/vm/simulate.sh" --env "$case_env" create >"$tmp_dir/create-$mode.out" 2>&1; then
    printf 'create must fail closed for forced %s failure\n' "$mode" >&2
    exit 1
  fi
  if [ -f "$case_generated/host/rendered/base-image-fingerprint.txt" ]; then
    case_baked_cache_dir="$generated_root/base-images/$(cat "$case_generated/host/rendered/base-image-fingerprint.txt")"
    printf '%s\n' "$case_baked_cache_dir" >>"$case_baked_cache_dirs"
  fi

  grep -Fq 'create: failed reason=vm-set-create' "$tmp_dir/create-$mode.out"
  ! grep -Fq 'baseline-prereqs=ready' "$tmp_dir/create-$mode.out"
  [ ! -f "$case_marker" ]
  if [ -d "$case_generated/host/logs/harness" ]; then
    case_create_log="$(find "$case_generated/host/logs/harness" -name 'create-*.log' -print | sort | tail -1)"
    [ -n "$case_create_log" ]
    grep -Fq "$case_failure_text" "$case_create_log"
  fi
  rm -rf "$case_generated" "$generated_root/vm-sets/$case_vm_set_id" "$case_baked_cache_dir"
}

run_fail_closed_case apt 'forced apt failure'
run_fail_closed_case image-info 'VM baked base image is not a readable qcow2 image'
run_fail_closed_case slapd 'forced slapd failure'
run_fail_closed_case ldap-consumer 'forced ldap consumer failure'
