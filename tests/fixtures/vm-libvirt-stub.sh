#!/usr/bin/env bash
set -euo pipefail
state_dir="${VM_STUB_STATE:?VM_STUB_STATE required}"
if [ "${1:-}" = "-c" ]; then
  shift 2
fi
cmd="${1:-}"
shift || true
record_call() {
  [ -z "${VM_STUB_CALLS:-}" ] || printf '%s\n' "$*" >>"$VM_STUB_CALLS"
}
domain_in_list() {
  local needle item
  needle="${1:?domain required}"
  for item in ${VM_STUB_SHUTDOWN_STICKS:-}; do
    [ "$item" != "$needle" ] || return 0
  done
  return 1
}
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
    record_call "shutdown $domain"
    domain_in_list "$domain" || printf 'shut off\n' >"$state_dir/domains/$domain.state"
    ;;
  destroy)
    domain="${1:?domain required}"
    record_call "destroy $domain"
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
