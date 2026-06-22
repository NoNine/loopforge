#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

run_id="port-test-$$"
state_dir="$tmp_dir/state"
staging_dir="$tmp_dir/staging"
evidence_dir="$tmp_dir/evidence"
log_dir="$tmp_dir/logs"

render() {
  HARNESS_RUN_ID="$run_id" \
  HARNESS_PROJECT_NAME="port-test-$$" \
  HARNESS_STATE_DIR="$state_dir" \
  HARNESS_STAGING_DIR="$staging_dir" \
  HARNESS_EVIDENCE_DIR="$evidence_dir" \
  HARNESS_LOG_DIR="$log_dir" \
    "$repo_root/simulation/docker/simulate.sh" render-config
}

render >"$tmp_dir/render-1.out"
env_file="$state_dir/rendered/harness.env"

gerrit_port="$(sed -n 's/^HARNESS_GERRIT_HTTP_HOST_PORT=//p' "$env_file")"
jenkins_port="$(sed -n 's/^HARNESS_JENKINS_HTTP_HOST_PORT=//p' "$env_file")"

case "$gerrit_port" in
  ''|*[!0-9]*) printf 'Expected numeric Gerrit host port, got %s\n' "$gerrit_port" >&2; exit 1 ;;
esac
case "$jenkins_port" in
  ''|*[!0-9]*) printf 'Expected numeric Jenkins host port, got %s\n' "$jenkins_port" >&2; exit 1 ;;
esac
[ "$gerrit_port" != "$jenkins_port" ] || {
  printf 'Expected distinct Gerrit and Jenkins host ports\n' >&2
  exit 1
}

grep -Fq "render-config: ok run-id=$run_id" "$tmp_dir/render-1.out"
! grep -Fq "gerrit_url=" "$tmp_dir/render-1.out"
! grep -Fq "jenkins_url=" "$tmp_dir/render-1.out"

render >"$tmp_dir/render-2.out"
grep -Fq "HARNESS_GERRIT_HTTP_HOST_PORT=$gerrit_port" "$env_file"
grep -Fq "HARNESS_JENKINS_HTTP_HOST_PORT=$jenkins_port" "$env_file"

explicit_gerrit_port="$(python3 - <<'PY'
import socket

with socket.socket() as sock:
    sock.bind(("127.0.0.1", 0))
    print(sock.getsockname()[1])
PY
)"
explicit_jenkins_port="$(python3 - "$explicit_gerrit_port" <<'PY'
import socket
import sys

blocked = int(sys.argv[1])
while True:
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
    if port != blocked:
        print(port)
        break
PY
)"

HARNESS_RUN_ID="$run_id-explicit" \
HARNESS_PROJECT_NAME="port-test-explicit-$$" \
HARNESS_STATE_DIR="$tmp_dir/explicit-state" \
HARNESS_STAGING_DIR="$tmp_dir/explicit-staging" \
HARNESS_EVIDENCE_DIR="$tmp_dir/explicit-evidence" \
HARNESS_LOG_DIR="$tmp_dir/explicit-logs" \
HARNESS_GERRIT_HTTP_HOST_PORT="$explicit_gerrit_port" \
HARNESS_JENKINS_HTTP_HOST_PORT="$explicit_jenkins_port" \
  "$repo_root/simulation/docker/simulate.sh" render-config >"$tmp_dir/explicit.out"
grep -Fq "render-config: ok run-id=$run_id-explicit" "$tmp_dir/explicit.out"
! grep -Fq "gerrit_url=" "$tmp_dir/explicit.out"
! grep -Fq "jenkins_url=" "$tmp_dir/explicit.out"
grep -Fq "HARNESS_GERRIT_HTTP_HOST_PORT=$explicit_gerrit_port" "$tmp_dir/explicit-state/rendered/harness.env"
grep -Fq "HARNESS_JENKINS_HTTP_HOST_PORT=$explicit_jenkins_port" "$tmp_dir/explicit-state/rendered/harness.env"

set +e
HARNESS_RUN_ID="$run_id-invalid" \
HARNESS_PROJECT_NAME="port-test-invalid-$$" \
HARNESS_STATE_DIR="$tmp_dir/invalid-state" \
HARNESS_STAGING_DIR="$tmp_dir/invalid-staging" \
HARNESS_EVIDENCE_DIR="$tmp_dir/invalid-evidence" \
HARNESS_LOG_DIR="$tmp_dir/invalid-logs" \
HARNESS_GERRIT_HTTP_HOST_PORT=not-a-port \
  "$repo_root/simulation/docker/simulate.sh" render-config >"$tmp_dir/invalid.out" 2>&1
invalid_rc=$?
set -e
[ "$invalid_rc" -ne 0 ] || {
  printf 'Expected nonnumeric explicit port to fail\n' >&2
  exit 1
}
grep -Fq 'HARNESS_GERRIT_HTTP_HOST_PORT must be a numeric TCP port' "$tmp_dir/invalid.out"

busy_port_file="$tmp_dir/busy-port"
python3 - "$busy_port_file" <<'PY' &
import pathlib
import socket
import sys
import time

port_file = pathlib.Path(sys.argv[1])
sock = socket.socket()
sock.bind(("127.0.0.1", 0))
sock.listen(1)
port_file.write_text(str(sock.getsockname()[1]))
try:
    time.sleep(30)
finally:
    sock.close()
PY
busy_pid=$!
trap 'kill "$busy_pid" 2>/dev/null || true; rm -rf "$tmp_dir"' EXIT

for _ in 1 2 3 4 5; do
  [ -s "$busy_port_file" ] && break
  sleep 0.2
done
[ -s "$busy_port_file" ] || {
  printf 'Timed out waiting for busy port helper\n' >&2
  exit 1
}
busy_port="$(cat "$busy_port_file")"

set +e
HARNESS_RUN_ID="$run_id-busy" \
HARNESS_PROJECT_NAME="port-test-busy-$$" \
HARNESS_STATE_DIR="$tmp_dir/busy-state" \
HARNESS_STAGING_DIR="$tmp_dir/busy-staging" \
HARNESS_EVIDENCE_DIR="$tmp_dir/busy-evidence" \
HARNESS_LOG_DIR="$tmp_dir/busy-logs" \
HARNESS_GERRIT_HTTP_HOST_PORT="$busy_port" \
  "$repo_root/simulation/docker/simulate.sh" render-config >"$tmp_dir/busy.out" 2>&1
busy_rc=$?
set -e
[ "$busy_rc" -ne 0 ] || {
  printf 'Expected occupied explicit port to fail\n' >&2
  exit 1
}
grep -Fq "HARNESS_GERRIT_HTTP_HOST_PORT is not available on 127.0.0.1: $busy_port" "$tmp_dir/busy.out"
