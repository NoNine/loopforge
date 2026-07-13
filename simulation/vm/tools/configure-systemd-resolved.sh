#!/usr/bin/env bash

set -euo pipefail

tool_script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
vm_dir="$(CDPATH= cd -- "$tool_script_dir/.." && pwd)"
repo_root="$(CDPATH= cd -- "$vm_dir/../.." && pwd)"
simulation_lib_dir="$repo_root/simulation/lib"
. "$simulation_lib_dir/common.sh"
. "$simulation_lib_dir/quote.sh"
. "$simulation_lib_dir/env.sh"
. "$simulation_lib_dir/permissions.sh"
vm_lib_dir="$vm_dir/lib"
script_dir="$vm_dir"
. "$vm_lib_dir/paths.sh"
. "$vm_lib_dir/config.sh"
. "$vm_lib_dir/libvirt.sh"

mode=dry-run
mode_option_count=0

usage() {
  cat <<'USAGE'
Usage:
  simulation/vm/tools/configure-systemd-resolved.sh [--env FILE] [--dry-run|--apply|--revert]

Options:
  --env FILE Harness env file. Defaults to simulation/vm/examples/vm.env.example.
  --dry-run  Inspect selected VM DNS readiness without mutation. This is the default.
  --apply    Configure temporary systemd-resolved split DNS for the selected VM bridge.
  --revert   Revert temporary systemd-resolved settings for the selected VM bridge.
  -h, --help Show this help.

This helper never edits /etc/hosts, /etc/resolv.conf, NetworkManager,
dnsmasq, systemd unit files, or persistent network configuration.
USAGE
}

parse_args() {
  HARNESS_ENV_FILE="${HARNESS_ENV_FILE:-$vm_env_example}"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --env)
        [ "$#" -ge 2 ] || die "--env requires a file"
        HARNESS_ENV_FILE="$2"
        shift 2
        ;;
      --env=*)
        HARNESS_ENV_FILE="${1#--env=}"
        [ -n "$HARNESS_ENV_FILE" ] || die "--env requires a file"
        shift
        ;;
      --dry-run)
        mode_option_count=$((mode_option_count + 1))
        [ "$mode_option_count" -le 1 ] || die "Choose only one mode option"
        mode=dry-run
        shift
        ;;
      --apply)
        mode_option_count=$((mode_option_count + 1))
        [ "$mode_option_count" -le 1 ] || die "Choose only one mode option"
        mode=apply
        shift
        ;;
      --revert)
        mode_option_count=$((mode_option_count + 1))
        [ "$mode_option_count" -le 1 ] || die "Choose only one mode option"
        mode=revert
        shift
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
  done
}

require_noninteractive_sudo() {
  require_command sudo
  sudo -n true >/dev/null 2>&1 ||
    die "Non-interactive sudo is required for --$mode"
}

network_xml_value() {
  local kind network xml
  kind="${1:?kind required}"
  network="${2:?network required}"
  xml="$(virsh -c "$VM_LIBVIRT_URI" net-dumpxml "$network")" || return $?
  printf '%s\n' "$xml" | python3 -c '
import sys
import xml.etree.ElementTree as ET

kind = sys.argv[1]
root = ET.parse(sys.stdin).getroot()
if kind == "bridge":
    node = root.find("./bridge")
    value = node.get("name") if node is not None else ""
elif kind == "gateway":
    node = root.find("./ip")
    value = node.get("address") if node is not None else ""
else:
    raise SystemExit(f"unknown XML value: {kind}")
if not value:
    raise SystemExit(f"network XML has no {kind}")
print(value)
' "$kind"
}

network_is_active() {
  local network
  network="${1:?network required}"
  virsh -c "$VM_LIBVIRT_URI" net-info "$network" 2>/dev/null |
    awk -F: '$1 == "Active" { gsub(/[[:space:]]/, "", $2); if ($2 == "yes") found = 1 } END { exit !found }'
}

dns_query_libvirt() {
  local gateway name result
  gateway="${1:?gateway required}"
  name="${2:?name required}"
  if command -v dig >/dev/null 2>&1; then
    result="$(dig +short +time=2 +tries=1 "@$gateway" "$name" A 2>/dev/null |
      awk 'index($0, ".") { print; exit }')"
  elif command -v host >/dev/null 2>&1; then
    result="$(host "$name" "$gateway" 2>/dev/null |
      awk '/ has address / { print $NF; exit }')"
  else
    die "Missing required DNS query tool: dig or host"
  fi
  [ -n "$result" ] || return 1
  printf '%s\n' "$result"
}

dns_query_host() {
  local name
  name="${1:?name required}"
  getent ahostsv4 "$name" 2>/dev/null |
    awk '{ print $1; found = 1; exit } END { exit !found }'
}

resolve_selected_network() {
  local network bridge gateway
  require_command virsh
  require_command python3
  network="$(vm_libvirt_network_name)"
  virsh -c "$VM_LIBVIRT_URI" net-info "$network" >/dev/null 2>&1 ||
    die "Selected VM network is missing: $network"
  network_is_active "$network" ||
    die "Selected VM network is not active: $network"
  bridge="$(network_xml_value bridge "$network")" ||
    die "Unable to read selected VM network bridge: $network"
  gateway="$(network_xml_value gateway "$network")" ||
    die "Unable to read selected VM network gateway: $network"
  SELECTED_NETWORK="$network"
  SELECTED_BRIDGE="$bridge"
  SELECTED_GATEWAY="$gateway"
}

print_dns_status() {
  local gerrit_name jenkins_name gerrit_libvirt jenkins_libvirt
  local gerrit_host jenkins_host host_status
  gerrit_name="gerrit.$HARNESS_LDAP_DOMAIN"
  jenkins_name="jenkins-controller.$HARNESS_LDAP_DOMAIN"
  gerrit_libvirt="$(dns_query_libvirt "$SELECTED_GATEWAY" "$gerrit_name")" ||
    die "Libvirt DNS did not resolve $gerrit_name via $SELECTED_GATEWAY"
  jenkins_libvirt="$(dns_query_libvirt "$SELECTED_GATEWAY" "$jenkins_name")" ||
    die "Libvirt DNS did not resolve $jenkins_name via $SELECTED_GATEWAY"
  gerrit_host="$(dns_query_host "$gerrit_name" || true)"
  jenkins_host="$(dns_query_host "$jenkins_name" || true)"
  host_status=ready
  if [ "$gerrit_host" != "$gerrit_libvirt" ] || [ "$jenkins_host" != "$jenkins_libvirt" ]; then
    host_status=unresolved
    if [ -n "$gerrit_host" ] || [ -n "$jenkins_host" ]; then
      host_status=mismatch
    fi
  fi
  printf 'selected-network=%s\n' "$SELECTED_NETWORK"
  printf 'bridge=%s\n' "$SELECTED_BRIDGE"
  printf 'gateway=%s\n' "$SELECTED_GATEWAY"
  printf 'domain=%s\n' "$HARNESS_LDAP_DOMAIN"
  printf 'libvirt-dns=ready %s=%s %s=%s\n' \
    "$gerrit_name" "$gerrit_libvirt" "$jenkins_name" "$jenkins_libvirt"
  printf 'host-dns=%s %s=%s %s=%s\n' \
    "$host_status" "$gerrit_name" "${gerrit_host:-unresolved}" \
    "$jenkins_name" "${jenkins_host:-unresolved}"
}

apply_split_dns() {
  require_command systemd-resolve
  printf 'systemd-resolved-action=apply interface=%s dns=%s domain=~%s\n' \
    "$SELECTED_BRIDGE" "$SELECTED_GATEWAY" "$HARNESS_LDAP_DOMAIN"
  sudo -n systemd-resolve \
    --interface="$SELECTED_BRIDGE" \
    --set-dns="$SELECTED_GATEWAY" \
    --set-domain="~$HARNESS_LDAP_DOMAIN"
}

revert_split_dns() {
  require_command systemd-resolve
  printf 'systemd-resolved-action=revert interface=%s\n' "$SELECTED_BRIDGE"
  sudo -n systemd-resolve --interface="$SELECTED_BRIDGE" --revert
}

main() {
  parse_args "$@"
  vm_config_load "$HARNESS_ENV_FILE"
  case "$mode" in
    apply|revert) require_noninteractive_sudo ;;
  esac
  resolve_selected_network
  print_dns_status
  case "$mode" in
    dry-run)
      print_command_summary systemd-resolved "" "dry-run ok"
      ;;
    apply)
      apply_split_dns
      print_command_summary systemd-resolved apply "ok mode=apply"
      ;;
    revert)
      revert_split_dns
      print_command_summary systemd-resolved revert "ok mode=revert"
      ;;
    *)
      die "Unknown mode: $mode"
      ;;
  esac
}

main "$@"
