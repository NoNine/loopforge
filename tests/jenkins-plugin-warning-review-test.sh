#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/scripts" "$tmp_dir/artifacts"
ln -s "$repo_root/scripts/common.sh" "$tmp_dir/scripts/common.sh"

real_awk="$(command -v awk)"
mkdir -p "$tmp_dir/bin"
cat >"$tmp_dir/bin/awk" <<'AWK_WRAPPER'
#!/usr/bin/env bash
case "$1" in
  *IGNORECASE*)
    printf 'test awk wrapper: IGNORECASE is not portable to mawk\n' >&2
    exit 2
    ;;
esac
exec "$REAL_AWK" "$@"
AWK_WRAPPER
chmod +x "$tmp_dir/bin/awk"

test_script="$tmp_dir/scripts/jenkins-plugin-warning-review-lib-test.sh"
sed '${/^main "\$@"$/d;}' "$repo_root/scripts/jenkins-controller-setup.sh" >"$test_script"
cat >>"$test_script" <<'TEST_BODY'

JENKINS_ARTIFACT_OUTPUT_DIR="$1"
accepted_output="$2"
review_report="$JENKINS_ARTIFACT_OUTPUT_DIR/plugin-review-report.txt"

cat >"$review_report" <<'REPORT'
No available updates
No security warnings
No security advisories
REPORT

assume_yes=0
inspect_plugin_review_report "$review_report" >"$accepted_output"

grep -Fq 'plugin_warning_count=0' "$JENKINS_ARTIFACT_OUTPUT_DIR/plugin-warning-review.metadata"
grep -Fq 'plugin_warning_report=plugin-review-report.txt' "$JENKINS_ARTIFACT_OUTPUT_DIR/plugin-warning-review.metadata"
grep -Fq 'plugin_warning_accepted_by_yes=false' "$JENKINS_ARTIFACT_OUTPUT_DIR/plugin-warning-review.metadata"
if grep -Fq 'operator acceptance recorded for Jenkins plugin warning review' "$accepted_output"; then
  printf 'Clean no-update report must not require --yes acceptance\n' >&2
  exit 1
fi

cat >"$review_report" <<'REPORT'
Some plugins have updates:
credentials 1502.v5c95e620ddfe has update 1503.vexample

Security warnings:
SECURITY-0000 Synthetic warning for regression coverage
ldap (780.vcb_33c9a_e4332): SECURITY-3654 RCE vulnerability in LDAP plugin
Update required: JUnit Plugin v1304.vc85a_b_ca_96613
REPORT

set +e
assume_yes=0
output="$(inspect_plugin_review_report "$review_report" 2>&1)"
status=$?
set -e

[ "$status" -ne 0 ] || {
  printf 'Expected warning review without --yes to fail\n' >&2
  exit 1
}
printf '%s\n' "$output" | grep -Fq 'rerun with --yes after operator review'
printf '%s\n' "$output" | grep -Fq 'ldap (780.vcb_33c9a_e4332): SECURITY-3654 RCE vulnerability in LDAP plugin'
printf '%s\n' "$output" | grep -Fq 'Update required: JUnit Plugin v1304.vc85a_b_ca_96613'

assume_yes=1
inspect_plugin_review_report "$review_report" >"$accepted_output"

[ -f "$JENKINS_ARTIFACT_OUTPUT_DIR/plugin-warning-review.metadata" ] || {
  printf 'Expected plugin warning review metadata\n' >&2
  exit 1
}

grep -Fq 'plugin_warning_count=6' "$JENKINS_ARTIFACT_OUTPUT_DIR/plugin-warning-review.metadata"
grep -Fq 'plugin_warning_report=plugin-review-report.txt' "$JENKINS_ARTIFACT_OUTPUT_DIR/plugin-warning-review.metadata"
grep -Fq 'plugin_warning_accepted_by_yes=true' "$JENKINS_ARTIFACT_OUTPUT_DIR/plugin-warning-review.metadata"
grep -Fq 'operator acceptance recorded for Jenkins plugin warning review' "$accepted_output"
TEST_BODY

REAL_AWK="$real_awk" PATH="$tmp_dir/bin:$PATH" bash "$test_script" "$tmp_dir/artifacts" "$tmp_dir/accepted.out"
