#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
fake_bin="$tmp_dir/bin"
run_id="preflight-no-render-$$"
run_dir="$repo_root/generated/simulation/docker/$run_id"
trap 'rm -rf "$tmp_dir" "$run_dir"' EXIT

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

state_dir="$run_dir/state"

PATH="$fake_bin:$PATH" \
HARNESS_RUN_ID="$run_id" \
HARNESS_PROJECT_NAME="$run_id" \
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
