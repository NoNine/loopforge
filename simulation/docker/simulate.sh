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
. "$simulation_lib_dir/identity.sh"
. "$simulation_lib_dir/locking.sh"
. "$simulation_lib_dir/state.sh"
. "$simulation_lib_dir/permissions.sh"
. "$simulation_lib_dir/logs.sh"
. "$simulation_lib_dir/evidence.sh"
docker_lib_dir="$script_dir/lib"
. "$docker_lib_dir/config.sh"
. "$docker_lib_dir/compose.sh"
. "$docker_lib_dir/ports.sh"
. "$docker_lib_dir/role-env.sh"
. "$docker_lib_dir/artifacts.sh"
. "$docker_lib_dir/evidence.sh"
. "$docker_lib_dir/commands.sh"

usage() {
  cat <<'USAGE'
Usage:
  simulation/docker/simulate.sh <command> [options]

Commands:
  run
  ssh --role <gerrit|jenkins-controller|jenkins-agent>

Phases:
  preflight
  init-run
  create
  start
  status
  ssh --role <gerrit|jenkins-controller|jenkins-agent>
  prepare-artifacts [--role <gerrit|jenkins-controller|jenkins-agent>]
  stage-artifacts [--role <gerrit|jenkins-controller|jenkins-agent>]
  configure-role [--role <gerrit|jenkins-controller|jenkins-agent>]
  validate-role [--role <gerrit|jenkins-controller|jenkins-agent>]
  configure-integration
  validate-integration
  prove-integration
  audit-state
  stop
  restore-baseline
  clean
  destroy

Options:
  --env FILE        Harness env file for bootstrap and init-run.
  --role ROLE       Role for role-scoped commands.
  -h, --help        Show this help.

The harness is the Docker simulation CLI. It owns strict role and cross-role
integration phases. Public internet fallback on target hosts is
simulation-only.
USAGE
}

parse_env_and_role_args() {
  local role_required role
  role_required="${1:?role_required required}"
  shift
  role=""
  HARNESS_ENV_FILE="${HARNESS_ENV_FILE:-$docker_env_example}"
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
        die "Unknown option for Docker harness command: $1"
        ;;
    esac
  done
  if [ "$role_required" -eq 1 ] && [ -z "$role" ]; then
    die "Missing --role; expected gerrit, jenkins-controller, or jenkins-agent"
  fi
  PARSED_ROLE="$role"
}

parse_env_only_args() {
  local env_file
  env_file="${HARNESS_ENV_FILE:-$docker_env_example}"
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
        die "Unknown option for Docker harness command: $1"
        ;;
    esac
  done
  HARNESS_ENV_FILE="$env_file"
}

main() {
  local command_name env_file
  env_file="$docker_env_example"
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
      cmd_run
      ;;
    preflight)
      shift
      parse_env_only_args "$@"
      docker_command_with_lock shared cmd_preflight
      ;;
    init-run)
      shift
      parse_env_only_args "$@"
      cmd_init_run
      ;;
    create)
      shift
      parse_env_only_args "$@"
      docker_command_with_lock exclusive cmd_create
      ;;
    start)
      shift
      parse_env_only_args "$@"
      docker_command_with_lock exclusive cmd_start
      ;;
    status)
      shift
      parse_env_only_args "$@"
      docker_command_with_lock shared cmd_status
      ;;
    ssh)
      shift
      parse_env_and_role_args 1 "$@"
      docker_command_with_lock shared cmd_ssh "$PARSED_ROLE"
      ;;
    prepare-artifacts)
      shift
      parse_env_and_role_args 0 "$@"
      docker_command_with_lock exclusive cmd_prepare_artifacts "$PARSED_ROLE"
      ;;
    stage-artifacts)
      shift
      parse_env_and_role_args 0 "$@"
      docker_command_with_lock exclusive cmd_stage_artifacts "$PARSED_ROLE"
      ;;
    configure-role)
      shift
      parse_env_and_role_args 0 "$@"
      docker_command_with_lock exclusive cmd_configure_role "$PARSED_ROLE"
      ;;
    validate-role)
      shift
      parse_env_and_role_args 0 "$@"
      docker_command_with_lock exclusive cmd_validate_role "$PARSED_ROLE"
      ;;
    configure-integration)
      shift
      parse_env_only_args "$@"
      docker_command_with_lock exclusive cmd_configure_integration
      ;;
    validate-integration)
      shift
      parse_env_only_args "$@"
      docker_command_with_lock exclusive cmd_validate_integration
      ;;
    prove-integration)
      shift
      parse_env_only_args "$@"
      docker_command_with_lock exclusive cmd_prove_integration
      ;;
    audit-state)
      shift
      parse_env_only_args "$@"
      docker_command_with_lock shared cmd_audit_state
      ;;
    stop)
      shift
      parse_env_only_args "$@"
      docker_command_with_lock exclusive cmd_stop
      ;;
    restore-baseline)
      shift
      parse_env_only_args "$@"
      docker_command_with_lock exclusive cmd_restore_baseline
      ;;
    clean)
      shift
      parse_env_only_args "$@"
      docker_command_with_lock exclusive cmd_clean
      ;;
    destroy)
      shift
      parse_env_only_args "$@"
      docker_command_with_lock exclusive cmd_destroy
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
