#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/scripts" "$tmp_dir/home/logs" "$tmp_dir/bin"
ln -s "$repo_root/scripts/common.sh" "$tmp_dir/scripts/common.sh"

test_script="$tmp_dir/scripts/jenkins-runtime-plugin-load-lib-test.sh"
sed '${/^main "\$@"$/d;}' "$repo_root/scripts/jenkins-controller-setup.sh" >"$test_script"
cat >>"$test_script" <<'TEST_BODY'

JENKINS_HOME="$1"
JENKINS_LOG_DIR="$JENKINS_HOME/logs"
log="$JENKINS_HOME/logs/jenkins-controller.log"
journal_fixture="$JENKINS_HOME/journal.fixture"
export journal_fixture
PATH="$2:$PATH"
export PATH

run_with_privilege() {
  sh -c "$1"
}

assert_fails_with() {
  local expected status output
  expected="$1"
  shift
  set +e
  output="$("$@" 2>&1)"
  status=$?
  set -e
  [ "$status" -ne 0 ] || {
    printf 'Expected command to fail: %s\n' "$*" >&2
    exit 1
  }
  printf '%s\n' "$output" | grep -Fq "$expected" || {
    printf 'Expected failure containing: %s\nActual output:\n%s\n' "$expected" "$output" >&2
    exit 1
  }
}

cat >"$log" <<'LOG'
INFO Jenkins is fully up and running
INFO Plugin load completed
LOG
JENKINS_VERIFICATION_MODE=docker-simulation
check_runtime_plugin_load_log

cat >"$log" <<'LOG'
SEVERE Failed Loading plugin Matrix Project Plugin v849.v0cd64ed7e531
WARNING Update required: JUnit Plugin v1304.vc85a_b_ca_96613
SEVERE Failed to load: Matrix Project Plugin
LOG
assert_fails_with 'Jenkins runtime log contains plugin load failure marker' \
  check_runtime_plugin_load_log

cat >"$journal_fixture" <<'LOG'
INFO Jenkins is fully up and running
INFO Plugin load completed
LOG
for JENKINS_VERIFICATION_MODE in vm-simulation target-deployment; do
  check_runtime_plugin_load_log
  if find "$JENKINS_LOG_DIR" -maxdepth 1 -name 'jenkins-systemd-plugin-load.*' | grep -q .; then
    printf 'Systemd plugin journal capture was not removed\n' >&2
    exit 1
  fi
done

cat >"$journal_fixture" <<'LOG'
SEVERE Failed Loading plugin Matrix Project Plugin v849.v0cd64ed7e531
WARNING Update required: JUnit Plugin v1304.vc85a_b_ca_96613
SEVERE Failed to load: Matrix Project Plugin
LOG
JENKINS_VERIFICATION_MODE=vm-simulation
assert_fails_with 'Jenkins runtime log contains plugin load failure marker' \
  check_runtime_plugin_load_log
if find "$JENKINS_LOG_DIR" -maxdepth 1 -name 'jenkins-systemd-plugin-load.*' | grep -q .; then
  printf 'Failed systemd plugin journal capture was not removed\n' >&2
  exit 1
fi
TEST_BODY

cat >"$tmp_dir/bin/journalctl" <<'JOURNALCTL'
#!/usr/bin/env bash
cat "$journal_fixture"
JOURNALCTL
chmod +x "$tmp_dir/bin/journalctl"

bash "$test_script" "$tmp_dir/home" "$tmp_dir/bin"
