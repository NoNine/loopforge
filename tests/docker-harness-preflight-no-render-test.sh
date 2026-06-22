#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
fake_bin="$tmp_dir/bin"
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$fake_bin"
cat >"$fake_bin/docker" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  *"compose version"*) printf 'Docker Compose version v2.0.0\n' ;;
  *) exit 0 ;;
esac
SH
chmod +x "$fake_bin/docker"

state_dir="$tmp_dir/state"
staging_dir="$tmp_dir/staging"
evidence_dir="$tmp_dir/evidence"
log_dir="$tmp_dir/logs"

PATH="$fake_bin:$PATH" \
HARNESS_RUN_ID="preflight-no-render-$$" \
HARNESS_PROJECT_NAME="preflight-no-render-$$" \
HARNESS_STATE_DIR="$state_dir" \
HARNESS_STAGING_DIR="$staging_dir" \
HARNESS_EVIDENCE_DIR="$evidence_dir" \
HARNESS_LOG_DIR="$log_dir" \
  "$repo_root/simulation/docker/simulate.sh" preflight >"$tmp_dir/preflight.out"

[ ! -e "$state_dir/rendered/harness.env" ] || {
  printf 'preflight unexpectedly created rendered harness env\n' >&2
  exit 1
}
[ ! -e "$state_dir/rendered/harness.runtime.env" ] || {
  printf 'preflight unexpectedly created runtime harness env\n' >&2
  exit 1
}
[ ! -d "$state_dir/rendered/runtime-inputs" ] || {
  printf 'preflight unexpectedly created runtime input copies\n' >&2
  exit 1
}
