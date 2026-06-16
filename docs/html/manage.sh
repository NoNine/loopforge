#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LOG_DIR="${REPO_ROOT}/logs"
PORT="${PORT:-4173}"
HOST="${HOST:-127.0.0.1}"
SERVER_PID_FILE="${LOG_DIR}/docs-html-server.pid"
SERVER_LOG_FILE="${LOG_DIR}/docs-html-server.log"
TUNNEL_PID_FILE="${LOG_DIR}/docs-html-devtunnel.pid"
TUNNEL_LOG_FILE="${LOG_DIR}/docs-html-devtunnel.log"

usage() {
  cat <<'EOF'
Usage:
  docs/html/manage.sh start
  docs/html/manage.sh stop
  docs/html/manage.sh status
  docs/html/manage.sh tunnel-start
  docs/html/manage.sh tunnel-stop
  docs/html/manage.sh tunnel-status

Environment:
  PORT  Local docs server port. Default: 4173.
  HOST  Local docs server bind host. Default: 127.0.0.1.
EOF
}

ensure_log_dir() {
  mkdir -p "${LOG_DIR}"
}

is_running() {
  local pid_file="$1"
  [ -f "${pid_file}" ] || return 1
  local pid
  pid="$(cat "${pid_file}")"
  [ -n "${pid}" ] && kill -0 "${pid}" >/dev/null 2>&1
}

start_server() {
  ensure_log_dir
  if is_running "${SERVER_PID_FILE}"; then
    printf 'server already running pid=%s url=http://%s:%s/ log=%s\n' \
      "$(cat "${SERVER_PID_FILE}")" "${HOST}" "${PORT}" "${SERVER_LOG_FILE}"
    return 0
  fi
  setsid env HOST="${HOST}" PORT="${PORT}" node "${SCRIPT_DIR}/server.mjs" \
    >"${SERVER_LOG_FILE}" 2>&1 </dev/null &
  printf '%s\n' "$!" > "${SERVER_PID_FILE}"
  sleep 1
  if ! is_running "${SERVER_PID_FILE}"; then
    printf 'server failed to start; log=%s\n' "${SERVER_LOG_FILE}" >&2
    tail -40 "${SERVER_LOG_FILE}" >&2 || true
    exit 1
  fi
  printf 'server started pid=%s url=http://%s:%s/ log=%s\n' \
    "$(cat "${SERVER_PID_FILE}")" "${HOST}" "${PORT}" "${SERVER_LOG_FILE}"
}

stop_pid() {
  local name="$1"
  local pid_file="$2"
  if ! is_running "${pid_file}"; then
    rm -f "${pid_file}"
    printf '%s not running\n' "${name}"
    return 0
  fi
  local pid
  pid="$(cat "${pid_file}")"
  kill "${pid}" >/dev/null 2>&1 || true
  for _ in $(seq 1 20); do
    if ! kill -0 "${pid}" >/dev/null 2>&1; then
      rm -f "${pid_file}"
      printf '%s stopped pid=%s\n' "${name}" "${pid}"
      return 0
    fi
    sleep 0.2
  done
  kill -9 "${pid}" >/dev/null 2>&1 || true
  rm -f "${pid_file}"
  printf '%s killed pid=%s\n' "${name}" "${pid}"
}

server_status() {
  if is_running "${SERVER_PID_FILE}"; then
    printf 'server running pid=%s url=http://%s:%s/ log=%s\n' \
      "$(cat "${SERVER_PID_FILE}")" "${HOST}" "${PORT}" "${SERVER_LOG_FILE}"
  else
    printf 'server not running url=http://%s:%s/ log=%s\n' "${HOST}" "${PORT}" "${SERVER_LOG_FILE}"
  fi
}

tunnel_start() {
  ensure_log_dir
  if is_running "${TUNNEL_PID_FILE}"; then
    printf 'tunnel already running pid=%s log=%s\n' "$(cat "${TUNNEL_PID_FILE}")" "${TUNNEL_LOG_FILE}"
    tail -20 "${TUNNEL_LOG_FILE}" || true
    return 0
  fi
  command -v devtunnel >/dev/null 2>&1 || {
    printf 'Missing devtunnel CLI.\n' >&2
    exit 1
  }
  devtunnel user show >/dev/null 2>&1 || {
    printf 'Run devtunnel user login -d before tunnel-start.\n' >&2
    exit 1
  }
  setsid devtunnel host -p "${PORT}" --protocol http --allow-anonymous \
    >"${TUNNEL_LOG_FILE}" 2>&1 </dev/null &
  printf '%s\n' "$!" > "${TUNNEL_PID_FILE}"
  sleep 3
  if ! is_running "${TUNNEL_PID_FILE}"; then
    printf 'tunnel failed to start; log=%s\n' "${TUNNEL_LOG_FILE}" >&2
    tail -40 "${TUNNEL_LOG_FILE}" >&2 || true
    exit 1
  fi
  printf 'tunnel started pid=%s log=%s\n' "$(cat "${TUNNEL_PID_FILE}")" "${TUNNEL_LOG_FILE}"
  tail -40 "${TUNNEL_LOG_FILE}" || true
}

tunnel_status() {
  if is_running "${TUNNEL_PID_FILE}"; then
    printf 'tunnel running pid=%s log=%s\n' "$(cat "${TUNNEL_PID_FILE}")" "${TUNNEL_LOG_FILE}"
    tail -20 "${TUNNEL_LOG_FILE}" || true
  else
    printf 'tunnel not running log=%s\n' "${TUNNEL_LOG_FILE}"
  fi
}

case "${1:-}" in
  start) start_server ;;
  stop) stop_pid server "${SERVER_PID_FILE}" ;;
  status) server_status ;;
  tunnel-start) tunnel_start ;;
  tunnel-stop) stop_pid tunnel "${TUNNEL_PID_FILE}" ;;
  tunnel-status) tunnel_status ;;
  --help|-h|"") usage ;;
  *) usage >&2; exit 2 ;;
esac
