#!/usr/bin/env bash

set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
repo_root="$(CDPATH= cd -- "$script_dir/.." && pwd)"

gerrit_env_file=""
jenkins_controller_env_file=""
jenkins_agent_env_file=""
dry_run=0
assume_yes=0
command_name=""

usage() {
  cat <<'USAGE'
Usage:
  scripts/integration-setup.sh \
    --gerrit-env FILE \
    --jenkins-controller-env FILE \
    --jenkins-agent-env FILE \
    [--dry-run] [--yes] <command>

Commands:
  configure-gerrit-ssh
  configure-agent-ssh
  configure-trigger
  validate-integration
  verify-trigger
  collect-evidence

Options:
  --gerrit-env FILE                Source reviewed Gerrit env values.
  --jenkins-controller-env FILE    Source reviewed Jenkins controller env values.
  --jenkins-agent-env FILE         Source reviewed Jenkins agent env values.
  --dry-run                        Parse inputs and report the blocked action.
  --yes                            Reserved for future reviewed mutations.
  -h, --help                       Show this help.

This is the shared cross-role integration command surface for Docker and future
VM orchestration. It is intentionally fail-closed until the later approved
integration implementation provides real Gerrit, Jenkins, and agent behavior.
USAGE
}

die_usage() {
  printf 'ERROR: %s\n' "$*" >&2
  usage >&2
  exit 1
}

load_env_file() {
  local label file
  label="${1:?label required}"
  file="${2:?file required}"
  [ -f "$file" ] || die_usage "Missing $label env file: $file"
  set -a
  # shellcheck disable=SC1090
  . "$file"
  set +a
}

load_inputs() {
  [ -n "$gerrit_env_file" ] || die_usage "Missing --gerrit-env FILE"
  [ -n "$jenkins_controller_env_file" ] ||
    die_usage "Missing --jenkins-controller-env FILE"
  [ -n "$jenkins_agent_env_file" ] ||
    die_usage "Missing --jenkins-agent-env FILE"
  load_env_file "Gerrit" "$gerrit_env_file"
  load_env_file "Jenkins controller" "$jenkins_controller_env_file"
  load_env_file "Jenkins agent" "$jenkins_agent_env_file"
}

value_or_default() {
  local name default_value
  name="${1:?name required}"
  default_value="${2:-not-set}"
  eval "printf '%s' \"\${$name:-$default_value}\""
}

blocked_command() {
  local command_name gerrit_endpoint jenkins_endpoint agent_endpoint
  command_name="${1:?command required}"
  load_inputs
  gerrit_endpoint="$(value_or_default GERRIT_HOST):$(value_or_default GERRIT_SSH_PORT)"
  jenkins_endpoint="$(value_or_default JENKINS_URL)"
  agent_endpoint="$(value_or_default JENKINS_AGENT_HOST):$(value_or_default JENKINS_AGENT_SSH_PORT)"

  printf 'status=blocked command=%s integration_surface=shared reason=not-implemented\n' "$command_name" >&2
  printf 'gerrit_endpoint=%s jenkins_endpoint=%s agent_endpoint=%s dry_run=%s yes=%s\n' \
    "$gerrit_endpoint" "$jenkins_endpoint" "$agent_endpoint" "$dry_run" "$assume_yes" >&2
  printf 'BLOCKED: %s requires the later approved real integration implementation; Step 11 has not started here and this scaffold will not mutate Gerrit, Jenkins, SSH keys, credentials, jobs, agents, or evidence.\n' "$command_name" >&2
  return 2
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --gerrit-env)
        [ "$#" -ge 2 ] || die_usage "--gerrit-env requires a value"
        gerrit_env_file="$2"
        shift 2
        ;;
      --gerrit-env=*)
        gerrit_env_file="${1#--gerrit-env=}"
        shift
        ;;
      --jenkins-controller-env)
        [ "$#" -ge 2 ] || die_usage "--jenkins-controller-env requires a value"
        jenkins_controller_env_file="$2"
        shift 2
        ;;
      --jenkins-controller-env=*)
        jenkins_controller_env_file="${1#--jenkins-controller-env=}"
        shift
        ;;
      --jenkins-agent-env)
        [ "$#" -ge 2 ] || die_usage "--jenkins-agent-env requires a value"
        jenkins_agent_env_file="$2"
        shift 2
        ;;
      --jenkins-agent-env=*)
        jenkins_agent_env_file="${1#--jenkins-agent-env=}"
        shift
        ;;
      --dry-run)
        dry_run=1
        shift
        ;;
      --yes)
        assume_yes=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      configure-gerrit-ssh|configure-agent-ssh|configure-trigger|validate-integration|verify-trigger|collect-evidence)
        command_name="$1"
        shift
        [ "$#" -eq 0 ] || die_usage "Unexpected arguments after command: $*"
        return 0
        ;;
      *)
        die_usage "Unknown option or command: $1"
        ;;
    esac
  done
  usage
  exit 1
}

main() {
  parse_args "$@"
  case "$command_name" in
    configure-gerrit-ssh|configure-agent-ssh|configure-trigger|validate-integration|verify-trigger|collect-evidence)
      blocked_command "$command_name"
      ;;
    *)
      die_usage "Unknown command: $command_name"
      ;;
  esac
}

main "$@"
