#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
rg_bin="$(command -v rg)"

# shellcheck source=/dev/null
. "$repo_root/scripts/jenkins-agent-setup.sh"

fake_bin="$tmp_dir/bin"
calls="$tmp_dir/calls.log"
mkdir -p "$fake_bin"
: >"$calls"

cat >"$fake_bin/systemctl" <<'EOF'
#!/usr/bin/env bash
set -eu
printf 'systemctl %s\n' "$*" >>"$FAKE_CALLS"
case "$*" in
  "show ssh.service --property=LoadState --value")
    printf '%s\n' "${FAKE_SSH_LOAD_STATE:-loaded}"
    ;;
  "show sshd.service --property=LoadState --value")
    printf '%s\n' "${FAKE_SSHD_LOAD_STATE:-not-found}"
    ;;
  "is-active --quiet ssh.service")
    [ "${FAKE_SSH_ACTIVE:-yes}" = yes ]
    ;;
  "is-active --quiet sshd.service")
    [ "${FAKE_SSHD_ACTIVE:-yes}" = yes ]
    ;;
  "show ssh.service --property=MainPID --value")
    printf '%s\n' "${FAKE_SSH_MAIN_PID:-4100}"
    ;;
  "show sshd.service --property=MainPID --value")
    printf '%s\n' "${FAKE_SSHD_MAIN_PID:-4200}"
    ;;
  *) exit 2 ;;
esac
EOF

cat >"$fake_bin/pgrep" <<'EOF'
#!/usr/bin/env bash
set -eu
printf 'pgrep %s\n' "$*" >>"$FAKE_CALLS"
[ "${FAKE_PGREP_SUCCESS:-yes}" = yes ] || exit 1
printf '%s\n' "${FAKE_PGREP_PID:-5100}"
EOF

cat >"$fake_bin/ps" <<'EOF'
#!/usr/bin/env bash
set -eu
printf 'ps %s\n' "$*" >>"$FAKE_CALLS"
pid=""
while [ "$#" -gt 0 ]; do
  if [ "$1" = -p ]; then
    pid="$2"
    break
  fi
  shift
done
[ -n "$pid" ] || exit 2
case "$pid" in
  4100|4200|5100) printf '%s\n' "${FAKE_PS_ARGS:-/usr/sbin/sshd -D}" ;;
  *) exit 1 ;;
esac
EOF

chmod +x "$fake_bin/systemctl" "$fake_bin/pgrep" "$fake_bin/ps"
export PATH="$fake_bin:/usr/bin:/bin"
export FAKE_CALLS="$calls"

expect_failure() {
  local expected
  expected="$1"
  shift
  if ("$@") >"$tmp_dir/failure.out" 2>&1; then
    printf 'Expected failure containing: %s\n' "$expected" >&2
    exit 1
  fi
  grep -Fq "$expected" "$tmp_dir/failure.out"
}

HARNESS_MODE=vm-simulation
HARNESS_ENVIRONMENT=jenkins-agent
JENKINS_AGENT_VERIFICATION_MODE=vm-simulation
check_os_sshd_process
grep -Fq 'systemctl show ssh.service --property=MainPID --value' "$calls"
if grep -Fq 'pgrep ' "$calls"; then
  printf 'VM SSH readiness must not discover sshd with pgrep\n' >&2
  exit 1
fi

FAKE_SSH_ACTIVE=no expect_failure 'Target OS SSH service is not active: ssh.service' \
  check_os_sshd_process
FAKE_SSH_MAIN_PID=0 expect_failure 'Target OS SSH service has no valid MainPID: ssh.service' \
  check_os_sshd_process
FAKE_PS_ARGS=/usr/bin/unrelated expect_failure 'Target OS sshd process is not running' \
  check_os_sshd_process
FAKE_SSH_LOAD_STATE=not-found FAKE_SSHD_LOAD_STATE=loaded check_os_sshd_process
grep -Fq 'systemctl show sshd.service --property=MainPID --value' "$calls"
FAKE_SSH_LOAD_STATE=not-found FAKE_SSHD_LOAD_STATE=not-found \
  expect_failure 'Target OS SSH service unit is not loaded' check_os_sshd_process

: >"$calls"
HARNESS_MODE=docker-simulation
HARNESS_ENVIRONMENT=jenkins-agent-target
JENKINS_AGENT_VERIFICATION_MODE=docker-simulation
check_os_sshd_process
grep -Fq 'pgrep -xo -u 0 sshd' "$calls"
if grep -Fq 'systemctl ' "$calls"; then
  printf 'Docker SSH readiness must not query systemd\n' >&2
  exit 1
fi

FAKE_PGREP_SUCCESS=no expect_failure 'Docker target sshd daemon process is not running' \
  check_os_sshd_process
FAKE_PS_ARGS=/usr/bin/unrelated expect_failure 'Target OS sshd process is not running' \
  check_os_sshd_process

state_dir="$tmp_dir/state-dir"
mkdir -p "$state_dir/state" "$state_dir/bootstrap"
printf 'installed\n' >"$state_dir/state/install.status"
printf 'configured\n' >"$state_dir/state/runtime.status"
printf 'bootstrap\n' >"$state_dir/bootstrap/jenkins-agent-bootstrap.txt"
JENKINS_AGENT_STATE_DIR="$state_dir"
verify_staged_artifacts() { :; }
validate_agent_render_inputs() { :; }
check_os_dependency_expectations() { :; }
check_runtime_account() { :; }
check_remote_fs_ownership() { :; }
check_ssh_reachability() { printf 'SSH-2.0-OpenSSH_test\n'; }

check_runtime_readiness
[ ! -e "$state_dir/run/os-sshd.pid" ]
mkdir -p "$state_dir/run"
printf 'legacy-pid\n' >"$state_dir/run/os-sshd.pid"
check_runtime_readiness
grep -Fxq 'legacy-pid' "$state_dir/run/os-sshd.pid"

if "$rg_bin" -n 'os-sshd\.pid|^PidFile ' "$repo_root/scripts/jenkins-agent-setup.sh"; then
  printf 'Jenkins agent helper must not reference the obsolete SSH PID marker\n' >&2
  exit 1
fi
