#!/usr/bin/env bash

set -euo pipefail

VM_LIBVIRT_URI="${VM_LIBVIRT_URI:-qemu:///system}"
resource_prefix="loopforge-vm-"
bridge_prefix="lf-"
dry_run=0

usage() {
  cat <<'USAGE'
Usage:
  simulation/vm/tools/cleanup-libvirt-resources.sh [--dry-run]

Options:
  --dry-run  Print the resources and ordered cleanup actions without mutation.
  -h, --help Show this help.

Without --dry-run, this tool permanently removes every LoopForge libvirt
domain, volume, pool, network, and bridge from qemu:///system and must run as
root. It does not remove generated workspaces or source cloud images.
USAGE
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --dry-run)
        dry_run=1
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        usage >&2
        die "Unknown option: $1"
        ;;
    esac
    shift
  done
}

list_matching_names() {
  local kind prefix
  kind="${1:?resource kind required}"
  prefix="${2:?resource prefix required}"
  virsh -c "$VM_LIBVIRT_URI" "$kind" --all --name |
    awk -v prefix="$prefix" 'index($0, prefix) == 1 { print }'
}

domain_state() {
  virsh -c "$VM_LIBVIRT_URI" domstate "${1:?domain required}"
}

pool_is_active() {
  virsh -c "$VM_LIBVIRT_URI" pool-info "${1:?pool required}" |
    awk -F: '$1 == "State" { gsub(/[[:space:]]/, "", $2); found = ($2 == "running") } END { exit !found }'
}

network_is_active() {
  virsh -c "$VM_LIBVIRT_URI" net-info "${1:?network required}" |
    awk -F: '$1 == "Active" { gsub(/[[:space:]]/, "", $2); found = ($2 == "yes") } END { exit !found }'
}

pool_type_and_target() {
  virsh -c "$VM_LIBVIRT_URI" pool-dumpxml "${1:?pool required}" |
    python3 -c '
import sys
import xml.etree.ElementTree as ET

root = ET.parse(sys.stdin).getroot()
pool_type = root.get("type", "")
target = root.findtext("./target/path") or ""
if not pool_type or not target or "\t" in target or "\n" in target:
    raise SystemExit("storage pool XML has no usable type and target path")
print(f"{pool_type}\t{target}")
'
}

list_active_pool_volumes() {
  virsh -c "$VM_LIBVIRT_URI" vol-list "${1:?pool required}" |
    awk 'NR > 2 && NF { print $1 }'
}

list_pool_volumes() {
  local pool pool_type target
  pool="${1:?pool required}"
  if pool_is_active "$pool"; then
    list_active_pool_volumes "$pool"
    return 0
  fi
  IFS=$'\t' read -r pool_type target < <(pool_type_and_target "$pool")
  [ "$pool_type" = dir ] ||
    die "Inactive LoopForge pool is not a directory pool: $pool"
  [ -d "$target" ] ||
    die "Inactive LoopForge pool target is missing: $pool ($target)"
  find "$target" -mindepth 1 -maxdepth 1 -type f -printf '%f\n' | sort
}

network_bridge() {
  virsh -c "$VM_LIBVIRT_URI" net-dumpxml "${1:?network required}" |
    python3 -c '
import sys
import xml.etree.ElementTree as ET

node = ET.parse(sys.stdin).getroot().find("./bridge")
if node is not None and node.get("name"):
    print(node.get("name"))
'
}

list_loopforge_bridges() {
  ip -o link show type bridge |
    awk -F': ' -v prefix="$bridge_prefix" 'index($2, prefix) == 1 { sub(/@.*/, "", $2); print $2 }'
}

bridge_exists() {
  ip link show "${1:?bridge required}" >/dev/null 2>&1
}

append_unique() {
  local -n target_array="${1:?array name required}"
  local value existing
  value="${2:-}"
  [ -n "$value" ] || return 0
  for existing in "${target_array[@]}"; do
    [ "$existing" != "$value" ] || return 0
  done
  target_array+=("$value")
}

inventory_resources() {
  local pool network bridge volume output
  output="$(list_matching_names list "$resource_prefix")" ||
    die "Unable to inventory LoopForge domains"
  domains=()
  [ -z "$output" ] || mapfile -t domains <<<"$output"
  output="$(list_matching_names pool-list "$resource_prefix")" ||
    die "Unable to inventory LoopForge pools"
  all_pools=()
  [ -z "$output" ] || mapfile -t all_pools <<<"$output"
  output="$(list_matching_names net-list "$resource_prefix")" ||
    die "Unable to inventory LoopForge networks"
  networks=()
  [ -z "$output" ] || mapfile -t networks <<<"$output"
  regular_pools=()
  base_pools=()
  volume_specs=()
  bridges=()

  for pool in "${all_pools[@]}"; do
    case "$pool" in
      loopforge-vm-base-*) base_pools+=("$pool") ;;
      *) regular_pools+=("$pool") ;;
    esac
    output="$(list_pool_volumes "$pool")" ||
      die "Unable to inventory LoopForge pool volumes: $pool"
    while IFS= read -r volume; do
      [ -n "$volume" ] || continue
      volume_specs+=("$pool"$'\t'"$volume")
    done <<<"$output"
  done

  for network in "${networks[@]}"; do
    bridge="$(network_bridge "$network")"
    append_unique bridges "$bridge"
  done
  output="$(list_loopforge_bridges)" ||
    die "Unable to inventory LoopForge bridges"
  while IFS= read -r bridge; do
    append_unique bridges "$bridge"
  done <<<"$output"
}

print_dry_run() {
  local domain state spec pool volume network bridge pool_state network_state
  printf 'dry-run uri=%s\n' "$VM_LIBVIRT_URI"
  for domain in "${domains[@]}"; do
    state="$(domain_state "$domain")"
    case "$state" in
      'shut off'|shut*) ;;
      *) printf 'would-destroy-domain name=%s state=%s\n' "$domain" "$state" ;;
    esac
    printf 'would-undefine-domain name=%s\n' "$domain"
  done
  for pool in "${regular_pools[@]}" "${base_pools[@]}"; do
    pool_state=inactive
    pool_is_active "$pool" && pool_state=running
    [ "$pool_state" = running ] || printf 'would-start-pool name=%s\n' "$pool"
    for spec in "${volume_specs[@]}"; do
      IFS=$'\t' read -r spec_pool volume <<<"$spec"
      [ "$spec_pool" = "$pool" ] || continue
      printf 'would-delete-volume pool=%s name=%s\n' "$pool" "$volume"
    done
    [ "$pool_state" != running ] || printf 'would-destroy-pool name=%s\n' "$pool"
    printf 'would-undefine-pool name=%s\n' "$pool"
  done
  for network in "${networks[@]}"; do
    network_state=inactive
    network_is_active "$network" && network_state=running
    [ "$network_state" != running ] || printf 'would-destroy-network name=%s\n' "$network"
    printf 'would-undefine-network name=%s\n' "$network"
  done
  for bridge in "${bridges[@]}"; do
    printf 'would-delete-bridge name=%s\n' "$bridge"
  done
  printf 'dry-run: ok domains=%s volumes=%s pools=%s networks=%s bridges=%s\n' \
    "${#domains[@]}" "${#volume_specs[@]}" "$(( ${#regular_pools[@]} + ${#base_pools[@]} ))" \
    "${#networks[@]}" "${#bridges[@]}"
}

undefine_domain() {
  local domain
  domain="${1:?domain required}"
  virsh -c "$VM_LIBVIRT_URI" undefine "$domain" \
    --managed-save --snapshots-metadata --nvram >/dev/null 2>&1 ||
    virsh -c "$VM_LIBVIRT_URI" undefine "$domain" \
      --managed-save --snapshots-metadata >/dev/null 2>&1 ||
    virsh -c "$VM_LIBVIRT_URI" undefine "$domain" >/dev/null
}

remove_domains() {
  local domain state
  for domain in "${domains[@]}"; do
    state="$(domain_state "$domain")"
    case "$state" in
      'shut off'|shut*) ;;
      *) virsh -c "$VM_LIBVIRT_URI" destroy "$domain" >/dev/null ;;
    esac
    undefine_domain "$domain"
    printf 'removed domain=%s\n' "$domain"
  done
}

remove_pool() {
  local pool spec spec_pool volume expected actual
  pool="${1:?pool required}"
  if ! pool_is_active "$pool"; then
    virsh -c "$VM_LIBVIRT_URI" pool-start "$pool" >/dev/null
  fi
  virsh -c "$VM_LIBVIRT_URI" pool-refresh "$pool" >/dev/null
  expected="$(for spec in "${volume_specs[@]}"; do
    IFS=$'\t' read -r spec_pool volume <<<"$spec"
    [ "$spec_pool" != "$pool" ] || printf '%s\n' "$volume"
  done | sort)"
  actual="$(list_active_pool_volumes "$pool" | sort)"
  [ "$actual" = "$expected" ] ||
    die "Pool volume inventory changed before cleanup: $pool"
  while IFS= read -r volume; do
    [ -n "$volume" ] || continue
    virsh -c "$VM_LIBVIRT_URI" vol-delete "$volume" --pool "$pool" >/dev/null
    printf 'removed volume=%s/%s\n' "$pool" "$volume"
  done <<<"$actual"
  [ -z "$(list_active_pool_volumes "$pool")" ] ||
    die "LoopForge pool still contains volumes: $pool"
  virsh -c "$VM_LIBVIRT_URI" pool-destroy "$pool" >/dev/null
  virsh -c "$VM_LIBVIRT_URI" pool-undefine "$pool" >/dev/null
  printf 'removed pool=%s\n' "$pool"
}

remove_pools() {
  local pool
  for pool in "${regular_pools[@]}"; do remove_pool "$pool"; done
  for pool in "${base_pools[@]}"; do remove_pool "$pool"; done
}

remove_networks() {
  local network
  for network in "${networks[@]}"; do
    if network_is_active "$network"; then
      virsh -c "$VM_LIBVIRT_URI" net-destroy "$network" >/dev/null
    fi
    virsh -c "$VM_LIBVIRT_URI" net-undefine "$network" >/dev/null
    printf 'removed network=%s\n' "$network"
  done
}

remove_bridges() {
  local bridge
  for bridge in "${bridges[@]}"; do
    bridge_exists "$bridge" || continue
    ip link delete "$bridge"
    printf 'removed bridge=%s\n' "$bridge"
  done
}

verify_cleanup() {
  local remaining
  remaining="$(list_matching_names list "$resource_prefix")" ||
    die "Unable to verify LoopForge domain cleanup"
  [ -z "$remaining" ] ||
    die "LoopForge domains remain after cleanup"
  remaining="$(list_matching_names pool-list "$resource_prefix")" ||
    die "Unable to verify LoopForge pool cleanup"
  [ -z "$remaining" ] ||
    die "LoopForge pools remain after cleanup"
  remaining="$(list_matching_names net-list "$resource_prefix")" ||
    die "Unable to verify LoopForge network cleanup"
  [ -z "$remaining" ] ||
    die "LoopForge networks remain after cleanup"
  remaining="$(list_loopforge_bridges)" ||
    die "Unable to verify LoopForge bridge cleanup"
  [ -z "$remaining" ] ||
    die "LoopForge bridges remain after cleanup"
}

main() {
  parse_args "$@"
  require_command virsh
  require_command ip
  require_command awk
  require_command python3
  require_command find
  virsh -c "$VM_LIBVIRT_URI" uri >/dev/null ||
    die "Unable to query libvirt URI: $VM_LIBVIRT_URI"
  if [ "$dry_run" -eq 0 ] && [ "$(id -u)" -ne 0 ]; then
    die "Root privilege is required; rerun: sudo $0"
  fi
  inventory_resources
  if [ "$dry_run" -eq 1 ]; then
    print_dry_run
    return 0
  fi
  remove_domains
  remove_pools
  remove_networks
  remove_bridges
  verify_cleanup
  printf 'cleanup: ok domains=%s volumes=%s pools=%s networks=%s bridges=%s\n' \
    "${#domains[@]}" "${#volume_specs[@]}" "$(( ${#regular_pools[@]} + ${#base_pools[@]} ))" \
    "${#networks[@]}" "${#bridges[@]}"
}

main "$@"
