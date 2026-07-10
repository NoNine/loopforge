#!/usr/bin/env bash

roles=(gerrit jenkins-controller jenkins-agent)

validate_role_name() {
  case "${1:-}" in
    gerrit|jenkins-controller|jenkins-agent) ;;
    *) die "Unknown role '${1:-}'; expected gerrit, jenkins-controller, or jenkins-agent" ;;
  esac
}

helper_for_role() {
  case "${1:-}" in
    gerrit) printf '%s\n' scripts/gerrit-setup.sh ;;
    jenkins-controller) printf '%s\n' scripts/jenkins-controller-setup.sh ;;
    jenkins-agent) printf '%s\n' scripts/jenkins-agent-setup.sh ;;
    *) die "Unknown role '${1:-}'; expected gerrit, jenkins-controller, or jenkins-agent" ;;
  esac
}

role_helpers_root_for_operator() {
  printf '/home/%s/loopforge\n' "${1:?operator account required}"
}

role_helper_path_for_operator() {
  local operator role
  operator="${1:?operator account required}"
  role="${2:?role required}"
  printf '%s/%s\n' \
    "$(role_helpers_root_for_operator "$operator")" \
    "$(helper_for_role "$role")"
}

role_helper_source_paths() {
  printf '%s\n' \
    scripts/common.sh \
    scripts/gerrit-setup.sh \
    scripts/jenkins-controller-setup.sh \
    scripts/jenkins-agent-setup.sh \
    templates/gerrit \
    templates/jenkins-controller \
    templates/jenkins-agent
}

parse_role() {
  local role=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
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
        die "Unknown option for role-scoped command: $1"
        ;;
    esac
  done

  [ -n "$role" ] || die "Missing --role; expected gerrit, jenkins-controller, or jenkins-agent"
  validate_role_name "$role"
  printf '%s\n' "$role"
}

parse_optional_role() {
  local role=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
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
        die "Unknown option for role command: $1"
        ;;
    esac
  done

  if [ -n "$role" ]; then
    validate_role_name "$role"
  fi
  printf '%s\n' "$role"
}
