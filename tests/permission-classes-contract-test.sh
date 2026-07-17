#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

require_doc_text() {
  local pattern message
  pattern="${1:?pattern required}"
  message="${2:?message required}"
  grep -Fq -- "$pattern" "$repo_root/docs/contracts/directory-model.md" || {
    printf '%s\n' "$message" >&2
    exit 1
  }
}

require_source_text() {
  local file pattern message
  file="${1:?file required}"
  pattern="${2:?pattern required}"
  message="${3:?message required}"
  grep -Fq -- "$pattern" "$repo_root/$file" || {
    printf '%s\n' "$message" >&2
    exit 1
  }
}

require_doc_text 'Loopforge permissions are classified by data sensitivity' \
  'Directory model must define sensitivity-based permission classes'
require_doc_text 'A harness does not inherently own secrets' \
  'Directory model must reject blanket harness-secret wording'
require_doc_text '| Secret/private file | `0600` |' \
  'Directory model must define private file mode'
require_doc_text '| Review-sensitive file | `0640` |' \
  'Directory model must define review-sensitive file mode'
require_doc_text '| Public/read-only file | `0644` |' \
  'Directory model must define public/read-only file mode'
require_doc_text 'Docker documents that bind mounts are writable by default' \
  'Directory model must cite Docker bind-mount permission posture'
require_doc_text 'Jenkins documents `$JENKINS_HOME/secrets`' \
  'Directory model must cite Jenkins secret handling posture'

require_source_text simulation/lib/permissions.sh 'LF_MODE_PRIVATE_FILE=0600' \
  'Shared permission library must keep private files at 0600'
require_source_text simulation/lib/permissions.sh 'LF_MODE_PUBLIC_FILE=0644' \
  'Shared permission library must define public/read-only files as 0644'
require_source_text simulation/lib/permissions.sh 'LF_MODE_REVIEW_FILE=0640' \
  'Shared permission library must define review-sensitive files as 0640'

require_source_text simulation/lib/state.sh 'atomic_write_record "$marker" "${LF_MODE_PUBLIC_FILE:-0644}"' \
  'Run and checkpoint markers must be non-secret public/read-only metadata'
for config in simulation/docker/lib/config.sh simulation/vm/lib/config.sh; do
  require_source_text "$config" 'tmp="$(mktemp "${HARNESS_RUNTIME_ENV}.XXXXXX")"' \
    'Runtime env publication must stage through a same-directory temporary file'
  require_source_text "$config" 'chmod "$LF_MODE_PRIVATE_FILE" "$tmp"' \
    'Runtime env temporary files must use the private file mode'
  require_source_text "$config" 'mv -- "$tmp" "$HARNESS_RUNTIME_ENV"' \
    'Runtime env publication must atomically replace the destination'
done
require_source_text simulation/docker/lib/artifacts.sh 'find $(shell_quote "$tmp") -type f -exec chmod $LF_MODE_PUBLIC_FILE' \
  'Docker staged role helper files must use public/read-only mode'
require_source_text simulation/vm/lib/ssh.sh 'find $(shell_quote "$remote_tmp") -type f -exec chmod $LF_MODE_PUBLIC_FILE' \
  'VM staged role helper files must use public/read-only mode'
require_source_text simulation/vm/lib/artifacts.sh 'chmod "$LF_MODE_PUBLIC_FILE" "$export_archive" "$export_checksum"' \
  'VM exported artifact review copies must use public/read-only mode'

if rg -n -i 'harness[- ]secrets|harness secret' "$repo_root/docs" "$repo_root/simulation" \
  -g '*.md' -g '*.sh' | grep -v 'A harness does not inherently own secrets'; then
  printf 'Blanket harness-secret wording must not appear in docs or simulation code\n' >&2
  exit 1
fi
