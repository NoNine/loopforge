#!/usr/bin/env bash

set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
repo_root="$(CDPATH= cd -- "$script_dir/../.." && pwd)"
simulation_lib_dir="$repo_root/simulation/lib"
. "$simulation_lib_dir/common.sh"
. "$simulation_lib_dir/quote.sh"
. "$simulation_lib_dir/roles.sh"
. "$simulation_lib_dir/artifacts.sh"
. "$simulation_lib_dir/env.sh"
. "$simulation_lib_dir/state.sh"
. "$simulation_lib_dir/logs.sh"
. "$simulation_lib_dir/evidence.sh"
vm_lib_dir="$script_dir/lib"
. "$vm_lib_dir/paths.sh"
. "$vm_lib_dir/config.sh"
. "$vm_lib_dir/state.sh"
. "$vm_lib_dir/libvirt.sh"
. "$vm_lib_dir/ssh.sh"
. "$vm_lib_dir/artifacts.sh"
. "$vm_lib_dir/roles.sh"
. "$vm_lib_dir/integration.sh"
. "$vm_lib_dir/lifecycle.sh"

usage() {
  cat <<'USAGE'
Usage:
  simulation/vm/simulate.sh <command> [options]
  simulation/vm/simulate.sh [--env FILE] <command> [options]

Commands:
  run
  ssh --role <gerrit|jenkins-controller|jenkins-agent>

Phases:
  preflight
  init-run
  create
  up
  status
  ssh --role <gerrit|jenkins-controller|jenkins-agent>
  prepare-artifacts [--role <gerrit|jenkins-controller|jenkins-agent>]
  stage-artifacts [--role <gerrit|jenkins-controller|jenkins-agent>]
  configure-role [--role <gerrit|jenkins-controller|jenkins-agent>]
  validate-role [--role <gerrit|jenkins-controller|jenkins-agent>]
  configure-integration
  validate-integration
  prove-integration
  reboot [--role <gerrit|jenkins-controller|jenkins-agent>|--all]
  audit-state
  down
  clean
  destroy

Options:
  --env FILE        Harness env file for bootstrap and init-run.
  --role ROLE       Role for role-scoped commands.
  --all             Select all VM targets for reboot.
  -h, --help        Show this help.

This is the VM simulation CLI. M1 implements local read-only run state only;
commands that require VM or libvirt mutation report blocked until later
milestones implement them.
USAGE
}

parse_env_only_args() {
  local env_file
  env_file="${HARNESS_ENV_FILE:-$vm_env_example}"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --env)
        [ "$#" -ge 2 ] || die "--env requires a file"
        env_file="$2"
        shift 2
        ;;
      --env=*)
        env_file="${1#--env=}"
        [ -n "$env_file" ] || die "--env requires a file"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown option for VM harness command: $1"
        ;;
    esac
  done
  HARNESS_ENV_FILE="$env_file"
}

parse_env_and_role_args() {
  local role_required role
  role_required="${1:?role_required required}"
  shift
  role=""
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
      --role)
        [ "$#" -ge 2 ] || die "--role requires a value"
        role="$2"
        shift 2
        ;;
      --role=*)
        role="${1#--role=}"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown option for VM harness command: $1"
        ;;
    esac
  done
  if [ -n "$role" ]; then
    validate_role_name "$role"
  fi
  if [ "$role_required" -eq 1 ] && [ -z "$role" ]; then
    die "Missing --role; expected gerrit, jenkins-controller, or jenkins-agent"
  fi
  PARSED_ROLE="$role"
}

parse_reboot_args() {
  local role all
  role=""
  all=0
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
      --role)
        [ "$#" -ge 2 ] || die "--role requires a value"
        role="$2"
        shift 2
        ;;
      --role=*)
        role="${1#--role=}"
        shift
        ;;
      --all)
        all=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown option for VM harness command: $1"
        ;;
    esac
  done
  if [ -n "$role" ]; then
    validate_role_name "$role"
  fi
  if [ "$all" -eq 1 ] && [ -n "$role" ]; then
    die "Use either --role or --all for reboot, not both"
  fi
  if [ "$all" -eq 0 ] && [ -z "$role" ]; then
    die "Missing reboot target; use --role ROLE or --all"
  fi
  PARSED_REBOOT_ROLE="$role"
  PARSED_REBOOT_ALL="$all"
}

main() {
  local command_name env_file
  env_file="$vm_env_example"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --env)
        [ "$#" -ge 2 ] || die "--env requires a file"
        env_file="$2"
        shift 2
        ;;
      --env=*)
        env_file="${1#--env=}"
        [ -n "$env_file" ] || die "--env requires a file"
        shift
        ;;
      -h|--help|help)
        usage
        exit 0
        ;;
      *)
        break
        ;;
    esac
  done
  HARNESS_ENV_FILE="$env_file"
  command_name="${1:-}"
  case "$command_name" in
    run)
      shift
      parse_env_only_args "$@"
      vm_cmd_run
      ;;
    preflight)
      shift
      parse_env_only_args "$@"
      vm_cmd_preflight
      ;;
    init-run)
      shift
      parse_env_only_args "$@"
      vm_cmd_init_run
      ;;
    create|up|down|clean|destroy)
      shift
      parse_env_only_args "$@"
      "vm_cmd_$command_name"
      ;;
    status)
      shift
      parse_env_only_args "$@"
      vm_cmd_status
      ;;
    ssh)
      shift
      parse_env_and_role_args 1 "$@"
      vm_cmd_ssh "$PARSED_ROLE"
      ;;
    prepare-artifacts|stage-artifacts|configure-role|validate-role)
      shift
      parse_env_and_role_args 0 "$@"
      "vm_cmd_${command_name//-/_}" "$PARSED_ROLE"
      ;;
    configure-integration|validate-integration|prove-integration)
      shift
      parse_env_only_args "$@"
      "vm_cmd_${command_name//-/_}"
      ;;
    reboot)
      shift
      parse_reboot_args "$@"
      vm_cmd_reboot "$PARSED_REBOOT_ROLE" "$PARSED_REBOOT_ALL"
      ;;
    audit-state)
      shift
      parse_env_only_args "$@"
      vm_cmd_audit_state
      ;;
    "")
      usage
      exit 1
      ;;
    *)
      die "Unknown command: $command_name"
      ;;
  esac
}

main "$@"
