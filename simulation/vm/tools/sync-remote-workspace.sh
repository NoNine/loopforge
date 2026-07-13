#!/usr/bin/env bash

set -euo pipefail

ssh_command=
workspace=
repo_name=loopforge
dry_run=0
force=0
source_mode=worktree
sync_tmp=

usage() {
  cat <<'USAGE'
Usage:
  simulation/vm/tools/sync-remote-workspace.sh --ssh COMMAND --workspace PATH [options]

Options:
  --ssh COMMAND       SSH command and target, for example: 'ssh -p 2222 localhost'.
  --workspace PATH    Remote workspace root that contains the repo directory.
  --repo-name NAME    Remote repo directory name. Default: loopforge.
  --head             Sync committed HEAD instead of the tracked local worktree.
  --force            Overwrite remote tracked-file changes.
  --dry-run          Print the sync plan without changing the remote host.
  -h, --help         Show this help.
USAGE
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

shell_quote() {
  local value
  value="${1:?value required}"
  printf "'%s'" "$(printf '%s' "$value" | sed "s/'/'\\\\''/g")"
}

validate_repo_name() {
  case "$repo_name" in
    ''|.|..|*/*|*' '*|*[!A-Za-z0-9_.-]*)
      die "repo name may contain only letters, digits, dots, underscores, and dashes"
      ;;
  esac
}

validate_workspace() {
  case "$workspace" in
    /*) ;;
    *) die "--workspace must be an absolute path" ;;
  esac
  case "$workspace" in
    *$'\n'*|*$'\t'*) die "--workspace must not contain tabs or newlines" ;;
  esac
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --ssh)
        [ "$#" -ge 2 ] || die "--ssh requires a command"
        ssh_command="$2"
        shift 2
        ;;
      --ssh=*)
        ssh_command="${1#--ssh=}"
        [ -n "$ssh_command" ] || die "--ssh requires a command"
        shift
        ;;
      --workspace)
        [ "$#" -ge 2 ] || die "--workspace requires a path"
        workspace="$2"
        shift 2
        ;;
      --workspace=*)
        workspace="${1#--workspace=}"
        [ -n "$workspace" ] || die "--workspace requires a path"
        shift
        ;;
      --repo-name)
        [ "$#" -ge 2 ] || die "--repo-name requires a value"
        repo_name="$2"
        shift 2
        ;;
      --repo-name=*)
        repo_name="${1#--repo-name=}"
        [ -n "$repo_name" ] || die "--repo-name requires a value"
        shift
        ;;
      --head)
        source_mode=head
        shift
        ;;
      --force)
        force=1
        shift
        ;;
      --dry-run)
        dry_run=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        usage >&2
        die "Unknown option: $1"
        ;;
    esac
  done
  [ -n "$ssh_command" ] || die "--ssh is required"
  [ -n "$workspace" ] || die "--workspace is required"
  validate_repo_name
  validate_workspace
}

prepare_worktree_overlay() {
  local manifest overlay path
  overlay="${1:?overlay dir required}"
  manifest="${2:?manifest path required}"
  : >"$manifest"
  while IFS= read -r -d '' path; do
    case "$path" in
      *$'\n'*) die "Tracked path contains a newline and cannot be synced safely: $path" ;;
    esac
    if [ -e "$path" ] || [ -L "$path" ]; then
      mkdir -p "$overlay/$(dirname "$path")"
      cp -Pp "$path" "$overlay/$path"
      printf '%s\n' "$path" >>"$manifest"
    fi
  done < <(git ls-files -z)
  LC_ALL=C sort -o "$manifest" "$manifest"
}

remote_entry_script() {
  local force_q head_q mode_q repo_q workspace_q
  workspace_q="$(shell_quote "$workspace")"
  repo_q="$(shell_quote "$repo_name")"
  mode_q="$(shell_quote "$source_mode")"
  force_q="$(shell_quote "$force")"
  head_q="$(shell_quote "$(git rev-parse --short HEAD)")"
  cat <<SCRIPT
set -euo pipefail
workspace=$workspace_q
repo_name=$repo_q
source_mode=$mode_q
force=$force_q
local_head=$head_q
repo_root="\$workspace/\$repo_name"
tmp_dir="\$repo_root/.loopforge-sync-incoming-\$\$"
mkdir -p "\$workspace" "\$repo_root"
chmod 0755 "\$repo_root"
rm -rf -- "\$tmp_dir"
mkdir -p "\$tmp_dir"
trap 'rm -rf -- "\$tmp_dir"' EXIT
tar -xzf - -C "\$tmp_dir"
bash "\$tmp_dir/remote-sync.sh" "\$workspace" "\$repo_name" "\$source_mode" "\$force" "\$local_head" "\$tmp_dir"
SCRIPT
}

write_remote_sync_script() {
  local path
  path="${1:?remote script path required}"
  cat >"$path" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

workspace="${1:?workspace required}"
repo_name="${2:?repo name required}"
source_mode="${3:?source mode required}"
force="${4:?force flag required}"
local_head="${5:?local head required}"
tmp_dir="${6:?temporary directory required}"
repo_root="$workspace/$repo_name"
sync_ref=refs/loopforge/sync-head
removed=0
overlay_commit=0

safe_path() {
  case "${1:-}" in
    ''|/*|..|../*|*/../*) return 1 ;;
    *) return 0 ;;
  esac
}

if [ ! -d "$repo_root/.git" ]; then
  git -C "$repo_root" init -q
fi

if [ -n "$(git -C "$repo_root" status --porcelain --untracked-files=no)" ]; then
  if [ "$force" != 1 ]; then
    printf 'ERROR: Remote repo has tracked-file changes; rerun with --force to overwrite: %s\n' "$repo_root" >&2
    exit 1
  fi
  git -C "$repo_root" reset --hard -q
fi

git -C "$repo_root" fetch -q "$tmp_dir/head.bundle" +HEAD:"$sync_ref"
git -C "$repo_root" reset --hard -q "$sync_ref"

if [ "$source_mode" = worktree ]; then
  git -C "$repo_root" ls-files | LC_ALL=C sort >"$tmp_dir/remote-tracked"
  comm -23 "$tmp_dir/remote-tracked" "$tmp_dir/overlay.manifest" >"$tmp_dir/deleted"
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    safe_path "$path" || {
      printf 'ERROR: Unsafe overlay deletion path: %s\n' "$path" >&2
      exit 1
    }
    rm -f -- "$repo_root/$path"
    git -C "$repo_root" rm -q --ignore-unmatch -- "$path"
    removed=$((removed + 1))
  done <"$tmp_dir/deleted"

  tar -C "$tmp_dir/overlay" -cf - . | tar -C "$repo_root" -xf -
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    safe_path "$path" || {
      printf 'ERROR: Unsafe overlay path: %s\n' "$path" >&2
      exit 1
    }
    git -C "$repo_root" add -- "$path"
  done <"$tmp_dir/overlay.manifest"

  if ! git -C "$repo_root" diff --cached --quiet; then
    GIT_AUTHOR_NAME='LoopForge Sync' \
    GIT_AUTHOR_EMAIL='loopforge-sync@example.invalid' \
    GIT_COMMITTER_NAME='LoopForge Sync' \
    GIT_COMMITTER_EMAIL='loopforge-sync@example.invalid' \
      git -C "$repo_root" commit -q -m "Apply LoopForge worktree sync overlay"
    overlay_commit=1
  fi
fi

chmod 0755 "$repo_root"
rm -rf -- "$tmp_dir"
printf 'sync-remote: ok mode=%s head=%s repo=%s removed=%s overlay-commit=%s\n' \
  "$source_mode" "$local_head" "$repo_root" "$removed" "$overlay_commit"
SCRIPT
  chmod 0700 "$path"
}

main() {
  local file_count head remote_command
  local -a ssh_parts
  parse_args "$@"
  require_command git
  require_command tar
  require_command cp
  require_command sed
  require_command sort
  git rev-parse --show-toplevel >/dev/null ||
    die "sync must run inside a Git worktree"
  head="$(git rev-parse --short HEAD)"
  read -r -a ssh_parts <<<"$ssh_command"
  [ "${#ssh_parts[@]}" -gt 0 ] || die "--ssh is empty"

  sync_tmp="$(mktemp -d)"
  trap 'rm -rf "$sync_tmp"' EXIT
  mkdir -p "$sync_tmp/package/overlay"
  git bundle create "$sync_tmp/package/head.bundle" HEAD >/dev/null
  case "$source_mode" in
    worktree) prepare_worktree_overlay "$sync_tmp/package/overlay" "$sync_tmp/package/overlay.manifest" ;;
    head) : >"$sync_tmp/package/overlay.manifest" ;;
    *) die "Unknown source mode: $source_mode" ;;
  esac
  file_count="$(wc -l <"$sync_tmp/package/overlay.manifest" | tr -d ' ')"

  if [ "$dry_run" -eq 1 ]; then
    printf 'sync-remote: dry-run mode=%s head=%s ssh=%s workspace=%s repo=%s overlay-files=%s force=%s\n' \
      "$source_mode" "$head" "$ssh_command" "$workspace" "$repo_name" "$file_count" "$force"
    printf 'sync-remote: would-fetch temporary Git bundle and preserve remote untracked runtime state\n'
    return 0
  fi

  write_remote_sync_script "$sync_tmp/package/remote-sync.sh"
  remote_command="bash -c $(shell_quote "$(remote_entry_script)")"
  tar -C "$sync_tmp/package" -czf - . | "${ssh_parts[@]}" "$remote_command"
}

main "$@"
