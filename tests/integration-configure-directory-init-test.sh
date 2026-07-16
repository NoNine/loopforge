#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

helper_copy="$tmp_dir/integration-setup.sh"
cp "$repo_root/scripts/integration-setup.sh" "$helper_copy"
sed -i '${/^main "\$@"$/d;}' "$helper_copy"

# shellcheck source=/dev/null
. "$helper_copy"

INTEGRATION_STATE_DIR="$tmp_dir/generated/state/integration"
INTEGRATION_LOG_DIR="$tmp_dir/generated/logs/integration"
INTEGRATION_EVIDENCE_DIR="$tmp_dir/generated/evidence/integration"

load_inputs() { :; }
require_runtime_mode_supported_for_mutation() { :; }
confirm_mutation() { :; }
configure_gerrit_ssh_impl() { :; }
configure_agent_ssh_impl() { :; }
ensure_shared_integration_storage() { :; }
configure_trigger_server_impl() { :; }

for path in \
  "$INTEGRATION_STATE_DIR" \
  "$INTEGRATION_LOG_DIR" \
  "$INTEGRATION_EVIDENCE_DIR"; do
  [ ! -e "$path" ]
done

output="$(cmd_configure_integration)"
printf '%s\n' "$output" | grep -Fq 'status=pass command=configure-integration'

[ "$(stat -c %a "$INTEGRATION_STATE_DIR")" = 700 ]
[ "$(stat -c %a "$INTEGRATION_STATE_DIR/status")" = 700 ]
[ "$(stat -c %a "$INTEGRATION_LOG_DIR")" = 750 ]
[ "$(stat -c %a "$INTEGRATION_EVIDENCE_DIR")" = 750 ]

log_file="$(find "$INTEGRATION_LOG_DIR" -maxdepth 1 -type f -name 'configure-integration-*.log' -print -quit)"
[ -n "$log_file" ]
[ "$(stat -c %a "$log_file")" = 640 ]
[ "$(stat -c %a "$INTEGRATION_STATE_DIR/status/configure-integration.status")" = 600 ]

printf 'Integration configure directory initialization passed\n'
