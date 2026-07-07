#!/usr/bin/env bash

validate_tcp_port_value() {
  local name value
  name="${1:?name required}"
  value="${2:?value required}"
  case "$value" in
    ''|*[!0-9]*)
      die "$name must be a numeric TCP port"
      ;;
  esac
  [ "$value" -ge 1 ] && [ "$value" -le 65535 ] ||
    die "$name must be between 1 and 65535"
}

loopback_port_owned_by_harness() {
  local service port container published
  service="${1:?service required}"
  port="${2:?port required}"
  command -v docker >/dev/null 2>&1 || return 1
  container="${HARNESS_PROJECT_NAME}-${service}"
  docker inspect "$container" >/dev/null 2>&1 || return 1
  published="$(docker inspect -f '{{range $p, $bindings := .NetworkSettings.Ports}}{{range $bindings}}{{if eq .HostIp "127.0.0.1"}}{{.HostPort}}{{"\n"}}{{end}}{{end}}{{end}}' "$container" 2>/dev/null || true)"
  printf '%s\n' "$published" | grep -Fxq "$port"
}

service_for_loopback_port_name() {
  case "$1" in
    HARNESS_GERRIT_HTTP_HOST_PORT) printf '%s\n' gerrit-target ;;
    HARNESS_JENKINS_HTTP_HOST_PORT) printf '%s\n' jenkins-controller-target ;;
    HARNESS_GERRIT_TARGET_SSH_HOST_PORT) printf '%s\n' gerrit-target ;;
    HARNESS_JENKINS_CONTROLLER_TARGET_SSH_HOST_PORT) printf '%s\n' jenkins-controller-target ;;
    HARNESS_JENKINS_AGENT_TARGET_SSH_HOST_PORT) printf '%s\n' jenkins-agent-target ;;
    *) die "Unknown loopback port name: $1" ;;
  esac
}

can_bind_loopback_port() {
  local port
  port="${1:?port required}"
  python3 - "$port" <<'PY'
import socket
import sys

port = int(sys.argv[1])
with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(("127.0.0.1", port))
PY
}

require_loopback_port_available() {
  local name port
  name="${1:?name required}"
  port="${2:?port required}"
  validate_tcp_port_value "$name" "$port"
  can_bind_loopback_port "$port" ||
    die "$name is not available on 127.0.0.1: $port"
}

require_loopback_port_available_or_owned() {
  local name port service
  name="${1:?name required}"
  port="${2:?port required}"
  service="$(service_for_loopback_port_name "$name")"
  validate_tcp_port_value "$name" "$port"
  if can_bind_loopback_port "$port" 2>/dev/null; then
    return 0
  fi
  loopback_port_owned_by_harness "$service" "$port" ||
    die "$name is not available on 127.0.0.1: $port"
}

choose_loopback_port() {
  python3 - <<'PY'
import socket

with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
    sock.bind(("127.0.0.1", 0))
    print(sock.getsockname()[1])
PY
}

rendered_env_value() {
  local name file
  name="${1:?name required}"
  file="${2:?file required}"
  [ -f "$file" ] || return 1
  sed -n "s/^$name=//p" "$file" | tail -1
}

resolve_browser_port() {
  local name requested persisted chosen other_port
  name="${1:?name required}"
  requested="${2:-}"
  other_port="${3:-}"

  if [ -n "$requested" ]; then
    require_loopback_port_available_or_owned "$name" "$requested"
    printf '%s\n' "$requested"
    return 0
  fi

  persisted="$(rendered_env_value "$name" "$HARNESS_RENDERED_ENV" || true)"
  if [ -n "$persisted" ]; then
    require_loopback_port_available_or_owned "$name" "$persisted"
    printf '%s\n' "$persisted"
    return 0
  fi

  while :; do
    chosen="$(choose_loopback_port)"
    require_loopback_port_available "$name" "$chosen"
    [ "$chosen" != "$other_port" ] || continue
    printf '%s\n' "$chosen"
    return 0
  done
}

resolve_browser_ports() {
  local gerrit_requested jenkins_requested gerrit_ssh_requested jenkins_controller_ssh_requested jenkins_agent_ssh_requested
  gerrit_requested="${HARNESS_GERRIT_HTTP_HOST_PORT:-}"
  jenkins_requested="${HARNESS_JENKINS_HTTP_HOST_PORT:-}"
  gerrit_ssh_requested="${HARNESS_GERRIT_TARGET_SSH_HOST_PORT:-}"
  jenkins_controller_ssh_requested="${HARNESS_JENKINS_CONTROLLER_TARGET_SSH_HOST_PORT:-}"
  jenkins_agent_ssh_requested="${HARNESS_JENKINS_AGENT_TARGET_SSH_HOST_PORT:-}"

  HARNESS_GERRIT_HTTP_HOST_PORT="$(resolve_browser_port HARNESS_GERRIT_HTTP_HOST_PORT "$gerrit_requested" "")"
  HARNESS_JENKINS_HTTP_HOST_PORT="$(resolve_browser_port HARNESS_JENKINS_HTTP_HOST_PORT "$jenkins_requested" "$HARNESS_GERRIT_HTTP_HOST_PORT")"
  HARNESS_GERRIT_TARGET_SSH_HOST_PORT="$(resolve_browser_port HARNESS_GERRIT_TARGET_SSH_HOST_PORT "$gerrit_ssh_requested" "$HARNESS_JENKINS_HTTP_HOST_PORT")"
  HARNESS_JENKINS_CONTROLLER_TARGET_SSH_HOST_PORT="$(resolve_browser_port HARNESS_JENKINS_CONTROLLER_TARGET_SSH_HOST_PORT "$jenkins_controller_ssh_requested" "$HARNESS_GERRIT_TARGET_SSH_HOST_PORT")"
  HARNESS_JENKINS_AGENT_TARGET_SSH_HOST_PORT="$(resolve_browser_port HARNESS_JENKINS_AGENT_TARGET_SSH_HOST_PORT "$jenkins_agent_ssh_requested" "$HARNESS_JENKINS_CONTROLLER_TARGET_SSH_HOST_PORT")"

  [ "$HARNESS_GERRIT_HTTP_HOST_PORT" != "$HARNESS_JENKINS_HTTP_HOST_PORT" ] ||
    die "HARNESS_GERRIT_HTTP_HOST_PORT and HARNESS_JENKINS_HTTP_HOST_PORT must be different"
  [ "$HARNESS_GERRIT_TARGET_SSH_HOST_PORT" != "$HARNESS_JENKINS_CONTROLLER_TARGET_SSH_HOST_PORT" ] ||
    die "HARNESS_GERRIT_TARGET_SSH_HOST_PORT and HARNESS_JENKINS_CONTROLLER_TARGET_SSH_HOST_PORT must be different"
  [ "$HARNESS_GERRIT_TARGET_SSH_HOST_PORT" != "$HARNESS_JENKINS_AGENT_TARGET_SSH_HOST_PORT" ] ||
    die "HARNESS_GERRIT_TARGET_SSH_HOST_PORT and HARNESS_JENKINS_AGENT_TARGET_SSH_HOST_PORT must be different"
  [ "$HARNESS_JENKINS_CONTROLLER_TARGET_SSH_HOST_PORT" != "$HARNESS_JENKINS_AGENT_TARGET_SSH_HOST_PORT" ] ||
    die "HARNESS_JENKINS_CONTROLLER_TARGET_SSH_HOST_PORT and HARNESS_JENKINS_AGENT_TARGET_SSH_HOST_PORT must be different"
  [ "$HARNESS_GERRIT_HTTP_HOST_PORT" != "$HARNESS_GERRIT_TARGET_SSH_HOST_PORT" ] ||
    die "HARNESS_GERRIT_HTTP_HOST_PORT and HARNESS_GERRIT_TARGET_SSH_HOST_PORT must be different"
  [ "$HARNESS_GERRIT_HTTP_HOST_PORT" != "$HARNESS_JENKINS_CONTROLLER_TARGET_SSH_HOST_PORT" ] ||
    die "HARNESS_GERRIT_HTTP_HOST_PORT and HARNESS_JENKINS_CONTROLLER_TARGET_SSH_HOST_PORT must be different"
  [ "$HARNESS_GERRIT_HTTP_HOST_PORT" != "$HARNESS_JENKINS_AGENT_TARGET_SSH_HOST_PORT" ] ||
    die "HARNESS_GERRIT_HTTP_HOST_PORT and HARNESS_JENKINS_AGENT_TARGET_SSH_HOST_PORT must be different"
  [ "$HARNESS_JENKINS_HTTP_HOST_PORT" != "$HARNESS_GERRIT_TARGET_SSH_HOST_PORT" ] ||
    die "HARNESS_JENKINS_HTTP_HOST_PORT and HARNESS_GERRIT_TARGET_SSH_HOST_PORT must be different"
  [ "$HARNESS_JENKINS_HTTP_HOST_PORT" != "$HARNESS_JENKINS_CONTROLLER_TARGET_SSH_HOST_PORT" ] ||
    die "HARNESS_JENKINS_HTTP_HOST_PORT and HARNESS_JENKINS_CONTROLLER_TARGET_SSH_HOST_PORT must be different"
  [ "$HARNESS_JENKINS_HTTP_HOST_PORT" != "$HARNESS_JENKINS_AGENT_TARGET_SSH_HOST_PORT" ] ||
    die "HARNESS_JENKINS_HTTP_HOST_PORT and HARNESS_JENKINS_AGENT_TARGET_SSH_HOST_PORT must be different"

  export HARNESS_GERRIT_HTTP_HOST_PORT HARNESS_JENKINS_HTTP_HOST_PORT
  export HARNESS_GERRIT_TARGET_SSH_HOST_PORT
  export HARNESS_JENKINS_CONTROLLER_TARGET_SSH_HOST_PORT
  export HARNESS_JENKINS_AGENT_TARGET_SSH_HOST_PORT
}
