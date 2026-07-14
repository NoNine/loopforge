#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/scripts" "$tmp_dir/bin"
ln -s "$repo_root/scripts/common.sh" "$tmp_dir/scripts/common.sh"

test_script="$tmp_dir/scripts/gerrit-download-failure-visibility-lib-test.sh"
sed '${/^main "\$@"$/d;}' "$repo_root/scripts/gerrit-setup.sh" >"$test_script"
cat >>"$test_script" <<'TEST_BODY'

work_dir="$1"
PATH="$2:$PATH"
export PATH
GERRIT_ARTIFACT_OUTPUT_DIR="$work_dir/preparing/gerrit-artifacts-bundle/gerrit"
GERRIT_DOWNLOAD_ARTIFACTS=1
GERRIT_WAR_SOURCE=""
mkdir -p "$GERRIT_ARTIFACT_OUTPUT_DIR"

status=0
(prepare_real_gerrit_war) >"$work_dir/helper.out" 2>&1 || status=$?
[ "$status" -ne 0 ] || {
  printf 'Expected Gerrit download failure\n' >&2
  exit 1
}

grep -Fq 'wget: simulated Gerrit download failure' "$work_dir/helper.out" || {
  printf 'Gerrit wget failure was missing from helper output\n' >&2
  exit 1
}

download_log="$(factory_download_log_path)"
grep -Fq 'simulation-only public internet use: downloading Gerrit application artifact in bundle factory' "$download_log"
if grep -Fq 'wget: simulated Gerrit download failure' "$download_log"; then
  printf 'Gerrit wget failure must not be hidden in the factory download log\n' >&2
  exit 1
fi
TEST_BODY

cat >"$tmp_dir/bin/wget" <<'WGET'
#!/usr/bin/env bash
printf 'wget: simulated Gerrit download failure\n' >&2
exit 4
WGET
chmod +x "$tmp_dir/bin/wget"

bash "$test_script" "$tmp_dir" "$tmp_dir/bin"
