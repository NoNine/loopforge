#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/scripts" "$tmp_dir/plugins" "$tmp_dir/artifacts"
ln -s "$repo_root/scripts/common.sh" "$tmp_dir/scripts/common.sh"

baseline="$repo_root/docs/baselines/version-baseline.md"
native_manual="$repo_root/docs/operations/native/jenkins-controller.md"
env_example="$repo_root/examples/jenkins-controller.env.example"
helper="$repo_root/scripts/jenkins-controller-setup.sh"

baseline_pins="$tmp_dir/baseline-pins.txt"
native_pins="$tmp_dir/native-pins.txt"
example_pins="$tmp_dir/example-pins.txt"
helper_pins="$tmp_dir/helper-pins.txt"

awk '
  $0 == "## Jenkins Direct Plugin Baseline" { section = 1; next }
  section && $0 == "```text" { pins = 1; next }
  pins && $0 == "```" { exit }
  pins { print }
' "$baseline" >"$baseline_pins"
awk '
  /cat > plugins\.intent\.txt <<'"'"'EOF'"'"'/ { pins = 1; next }
  pins && $0 == "EOF" { exit }
  pins { print }
' "$native_manual" >"$native_pins"
sed -n 's/^JENKINS_PLUGIN_LIST="\(.*\)"$/\1/p' "$env_example" |
  tr ',' '\n' >"$example_pins"
sed -n 's/.*JENKINS_PLUGIN_LIST="${JENKINS_PLUGIN_LIST:-\([^}]*\)}".*/\1/p' "$helper" |
  tr ',' '\n' >"$helper_pins"

[ "$(wc -l <"$baseline_pins" | tr -d ' ')" -eq 12 ] || {
  printf 'Jenkins direct plugin baseline must contain exactly 12 pins\n' >&2
  exit 1
}
for pins in "$native_pins" "$example_pins" "$helper_pins"; do
  diff -u "$baseline_pins" "$pins" >/dev/null || {
    printf 'Jenkins direct plugin pins drifted from the version baseline: %s\n' "$pins" >&2
    exit 1
  }
done

if rg -q 'tmp_plugins_seed|<accepted-direct-plugin>|/tmp/jenkins-plugin-facts' "$native_manual"; then
  printf 'Native Jenkins plugin review must not use placeholder or temporary inventories\n' >&2
  exit 1
fi
for pattern in \
  '--plugin-file ~/jenkins-artifacts-bundle/jenkins/plugins.intent.txt' \
  'plugins.resolved.txt' \
  '--list' \
  'Resulting plugin list' \
  'Do not use `--skip-failed-plugins`'; do
  rg -Fq -- "$pattern" "$native_manual" || {
    printf 'Native Jenkins plugin review is missing operator guidance: %s\n' "$pattern" >&2
    exit 1
  }
done
if rg -q 'invalid direct plugin pin at line|resolved_plugin_count=|manifest=.*unzip -p|while IFS=: read -r name expected_version' \
  "$native_manual"; then
  printf 'Native Jenkins plugin review must not reproduce helper validation logic\n' >&2
  exit 1
fi

old_validator_pattern='validate_plugin_dependency_''closure'
old_lock_pattern='plugins\.expected-''lock\.txt'
old_lock_diff_pattern='Downloaded or reviewed Jenkins plugin artifacts do not ''match'
if rg -q "$old_validator_pattern|$old_lock_pattern|$old_lock_diff_pattern" "$repo_root/scripts/jenkins-controller-setup.sh"; then
  printf 'Generic plugin closure validation must not be present\n' >&2
  exit 1
fi

for path in "$helper" "$env_example" "$baseline" "$native_manual"; do
  rg -q 'configuration-as-code:2100\.vb_fd699d2a_09c' "$path" || {
    printf 'Updated configuration-as-code direct pin is missing from %s\n' "$path" >&2
    exit 1
  }
  rg -q 'credentials:1506\.v948b_b_b_7dec44' "$path" || {
    printf 'Updated credentials direct pin is missing from %s\n' "$path" >&2
    exit 1
  }
  rg -q 'gerrit-trigger:3\.1983\.v57096fe9923c' "$path" || {
    printf 'Updated gerrit-trigger direct pin is missing from %s\n' "$path" >&2
    exit 1
  }
done

if rg -q 'configuration-as-code:2088\.ve3b_42c663c80|credentials:1502\.v5c95e620ddfe|gerrit-trigger:3\.1971\.v217d381e3a_5a_' \
  "$helper" "$env_example" "$baseline" "$native_manual"; then
  printf 'Stale Jenkins direct plugin pin remains in product defaults\n' >&2
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
assert_direct_plugin_pins_in_dir "$plugin_dir"
plugin_fact_stream "$plugin_dir" | grep -Fq 'structs:362.va_0a_839590b_61'

reset_plugins
make_plugin "$artifact_dir/build" matrix-project 849.v0cd64ed7e531
make_plugin "$artifact_dir/build" junit 1304.vc85a_b_ca_96613
assert_fails_with 'Direct Jenkins plugin pin drift for junit' \
  assert_direct_plugin_pins_in_dir "$plugin_dir"

reset_plugins
make_plugin "$artifact_dir/build" matrix-project 849.v0cd64ed7e531
assert_fails_with 'Accepted direct Jenkins plugin pin is missing from resolved plugin artifacts: junit' \
  assert_direct_plugin_pins_in_dir "$plugin_dir"
TEST_BODY

bash "$test_script" "$tmp_dir/artifacts"
