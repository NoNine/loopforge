#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir" 2>/dev/null || true' EXIT

function_body="$(
  awk '
    /^gerrit_account_can_vote_verified\(\) \{/ { capture = 1 }
    capture { print }
    capture && /^}/ { exit }
  ' "$repo_root/scripts/integration-setup.sh"
)"

cat >"$tmp_dir/harness.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
JENKINS_GERRIT_INTEGRATION_ACCOUNT=jenkins-gerrit
JENKINS_GERRIT_INTEGRATION_PASSWORD=integration-password
gerrit_curl() {
  cat "\$GERRIT_CURL_RESPONSE_FILE"
}
$function_body
gerrit_account_can_vote_verified verification-disposable-gerrit
EOF
chmod +x "$tmp_dir/harness.sh"

cat >"$tmp_dir/labels-array.json" <<'EOF'
)]}'
[
  {
    "name": "Code-Review",
    "project_name": "All-Projects"
  },
  {
    "name": "Verified",
    "project_name": "All-Projects",
    "values": {
      "-1": "Fails",
      " 0": "No score",
      "+1": "Verified"
    }
  }
]
EOF

GERRIT_CURL_RESPONSE_FILE="$tmp_dir/labels-array.json" "$tmp_dir/harness.sh"

cat >"$tmp_dir/labels-object.json" <<'EOF'
)]}'
{
  "Verified": {
    "name": "Verified",
    "project_name": "All-Projects"
  }
}
EOF

GERRIT_CURL_RESPONSE_FILE="$tmp_dir/labels-object.json" "$tmp_dir/harness.sh"

cat >"$tmp_dir/no-verified.json" <<'EOF'
)]}'
[
  {
    "name": "Code-Review",
    "project_name": "All-Projects"
  }
]
EOF

set +e
GERRIT_CURL_RESPONSE_FILE="$tmp_dir/no-verified.json" "$tmp_dir/harness.sh"
rc=$?
set -e

[ "$rc" -ne 0 ] || {
  printf 'Expected voteable label parser to reject response without Verified\n' >&2
  exit 1
}
