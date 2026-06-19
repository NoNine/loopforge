#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/scripts" "$tmp_dir/plugins" "$tmp_dir/artifacts"
ln -s "$repo_root/scripts/common.sh" "$tmp_dir/scripts/common.sh"

old_validator_pattern='validate_plugin_dependency_''closure'
old_lock_pattern='plugins\.expected-''lock\.txt'
old_lock_diff_pattern='Downloaded or reviewed Jenkins plugin artifacts do not ''match'
if rg -q "$old_validator_pattern|$old_lock_pattern|$old_lock_diff_pattern" "$repo_root/scripts/jenkins-controller-setup.sh"; then
  printf 'Generic plugin closure validation must not be present\n' >&2
  exit 1
fi

test_script="$tmp_dir/scripts/jenkins-plugin-direct-pin-lib-test.sh"
sed '${/^main "\$@"$/d;}' "$repo_root/scripts/jenkins-controller-setup.sh" >"$test_script"
cat >>"$test_script" <<'TEST_BODY'

artifact_dir="$1"
plugin_dir="$artifact_dir/plugins"
mkdir -p "$plugin_dir"
JENKINS_ARTIFACT_OUTPUT_DIR="$artifact_dir"
JENKINS_PLUGIN_LIST="matrix-project:849.v0cd64ed7e531,junit:1335.v6b_a_a_e18534e1"

make_plugin() {
  local dir name version archive
  dir="$1"
  name="$2"
  version="$3"
  archive="$plugin_dir/$name.jpi"
  mkdir -p "$dir/$name/META-INF"
  {
    printf 'Manifest-Version: 1.0\n'
    printf 'Short-Name: %s\n' "$name"
    printf 'Plugin-Version: %s\n' "$version"
  } >"$dir/$name/META-INF/MANIFEST.MF"
  python3 - "$dir/$name" "$archive" <<'PY'
import pathlib
import sys
import zipfile

plugin = pathlib.Path(sys.argv[1])
archive = pathlib.Path(sys.argv[2])
with zipfile.ZipFile(archive, "w") as zf:
    zf.write(plugin / "META-INF" / "MANIFEST.MF", "META-INF/MANIFEST.MF")
PY
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

reset_plugins() {
  rm -rf "$plugin_dir" "$artifact_dir/build"
  mkdir -p "$plugin_dir" "$artifact_dir/build"
}

reset_plugins
make_plugin "$artifact_dir/build" matrix-project 849.v0cd64ed7e531
make_plugin "$artifact_dir/build" junit 1335.v6b_a_a_e18534e1
make_plugin "$artifact_dir/build" structs 362.va_0a_839590b_61
generate_plugins_lock "$artifact_dir/plugins.lock.txt"
assert_direct_plugin_pins_in_lock "$artifact_dir/plugins.lock.txt"
grep -Fq 'structs:362.va_0a_839590b_61' "$artifact_dir/plugins.lock.txt"

reset_plugins
make_plugin "$artifact_dir/build" matrix-project 849.v0cd64ed7e531
make_plugin "$artifact_dir/build" junit 1304.vc85a_b_ca_96613
generate_plugins_lock "$artifact_dir/plugins.lock.txt"
assert_fails_with 'Direct Jenkins plugin pin drift for junit' \
  assert_direct_plugin_pins_in_lock "$artifact_dir/plugins.lock.txt"

reset_plugins
make_plugin "$artifact_dir/build" matrix-project 849.v0cd64ed7e531
generate_plugins_lock "$artifact_dir/plugins.lock.txt"
assert_fails_with 'Accepted direct Jenkins plugin pin is missing from plugins.lock.txt: junit' \
  assert_direct_plugin_pins_in_lock "$artifact_dir/plugins.lock.txt"
TEST_BODY

bash "$test_script" "$tmp_dir/artifacts"
