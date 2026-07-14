#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
# shellcheck source=../scripts/common.sh
. "$repo_root/scripts/common.sh"

identity_state=absent
collision=none
expected_owner=service
mutation_command=""
action_file="$(mktemp)"
trap 'rm -f "$action_file"' EXIT

shell_quote() {
  printf '%q' "${1:?value required}"
}

groupadd() { :; }
useradd() { :; }
install() { :; }

getent() {
  local database key
  database="${1:?database required}"
  key="${2:?key required}"
  case "$database:$key:$collision" in
    passwd:62010:uid) printf 'other:x:62010:62011::/other:/bin/bash\n'; return 0 ;;
    group:62011:gid) printf 'other:x:62011:\n'; return 0 ;;
  esac
  case "$identity_state:$database:$key" in
    ready:passwd:service|partial:passwd:service)
      printf 'service:x:62010:62011::/srv/service:/bin/bash\n'
      ;;
    ready:group:service)
      printf 'service:x:62011:\n'
      ;;
    *) return 2 ;;
  esac
}

stat() {
  local format path
  [ "${1:-}" = "-c" ] || return 2
  format="${2:?format required}"
  path="${3:?path required}"
  [ "$identity_state" = "ready" ] && [ "$path" = "/srv/service" ] || return 2
  case "$format" in
    %F) printf 'directory\n' ;;
    %U) printf '%s\n' "$expected_owner" ;;
    %G) printf 'service\n' ;;
    *) return 2 ;;
  esac
}

run_with_privilege() {
  mutation_command="${1:?command required}"
  identity_state=ready
}

realize_runtime_identity service service 62010 62011 /srv/service Service >"$action_file"
action="$(<"$action_file")"
[ "$action" = "created" ] || {
  printf 'Expected absent runtime identity to be created, got %s\n' "$action" >&2
  exit 1
}
case "$mutation_command" in
  *'groupadd --gid 62011 service'*) ;;
  *) printf 'Creation command omitted reviewed group/GID: %s\n' "$mutation_command" >&2; exit 1 ;;
esac
case "$mutation_command" in
  *'useradd --uid 62010 --gid 62011 --home-dir /srv/service --no-create-home --shell /bin/bash service'*) ;;
  *) printf 'Creation command omitted reviewed account fields: %s\n' "$mutation_command" >&2; exit 1 ;;
esac
case "$mutation_command" in
  *'install -d -m 0755 -o service -g service /srv/service'*) ;;
  *) printf 'Creation command omitted owned product home: %s\n' "$mutation_command" >&2; exit 1 ;;
esac

identity_state=ready
mutation_command=""
realize_runtime_identity service service 62010 62011 /srv/service Service >"$action_file"
action="$(<"$action_file")"
[ "$action" = "reused" ] && [ -z "$mutation_command" ] || {
  printf 'Fully matching runtime identity was not reused without mutation\n' >&2
  exit 1
}

expect_failure() {
  local expected output rc
  expected="${1:?expected text required}"
  set +e
  output="$(classify_runtime_identity_state service service 62010 62011 /srv/service Service 2>&1)"
  rc=$?
  set -e
  [ "$rc" -ne 0 ] && grep -Fq "$expected" <<<"$output" || {
    printf 'Expected failure containing %s, got:\n%s\n' "$expected" "$output" >&2
    exit 1
  }
}

identity_state=absent
collision=uid
expect_failure 'runtime UID 62010 is already assigned'
collision=gid
expect_failure 'runtime GID 62011 is already assigned'
collision=none
identity_state=partial
expect_failure 'runtime identity state is partial'
identity_state=ready
expected_owner=root
expect_failure 'product home /srv/service owner/group must be service:service, got root:service'
