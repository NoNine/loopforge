#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
packages="$repo_root/docs/baselines/package-requirements.md"
gerrit_native="$repo_root/docs/operations/native/gerrit.md"
jenkins_native="$repo_root/docs/operations/native/jenkins-controller.md"
jenkins_agent_native="$repo_root/docs/operations/native/jenkins-agent.md"
jenkins_setup="$repo_root/docs/operations/setup/jenkins-controller.md"
gerrit_helper="$repo_root/scripts/gerrit-setup.sh"
jenkins_helper="$repo_root/scripts/jenkins-controller-setup.sh"

require_text() {
  local file pattern message
  file="${1:?file required}"
  pattern="${2:?pattern required}"
  message="${3:?message required}"
  grep -Fq -- "$pattern" "$file" || {
    printf '%s\n' "$message" >&2
    exit 1
  }
}

reject_text() {
  local file pattern message
  file="${1:?file required}"
  pattern="${2:?pattern required}"
  message="${3:?message required}"
  if grep -Fq -- "$pattern" "$file"; then
    printf '%s\n' "$message" >&2
    exit 1
  fi
}

require_text "$packages" '### LDAP Environment' \
  'Package authority must define the LDAP logical environment'
require_text "$packages" \
  'The `common-operations` package set provides `ldap-utils`' \
  'Package authority must assign ldap-utils to common operations'
require_text "$packages" \
  'Do not treat `ldap-utils` as a Gerrit or Jenkins runtime dependency.' \
  'Package authority must keep ldap-utils out of the application runtime layer'
require_text "$packages" \
  'Helper-specific packages belong to the logical environment in which the helper' \
  'Package authority must assign helper dependencies to logical environments'
require_text "$packages" '## Requirement Consumers' \
  'Package authority must identify requirement consumers'
reject_text "$packages" '| Verification |' \
  'Package authority must not embed implementation-test verification columns'
reject_text "$packages" '## Evidence Map' \
  'Package authority must not overload runtime evidence terminology'

for manual in "$gerrit_native" "$jenkins_native"; do
  require_text "$manual" '  ldap-utils \' \
    'Native application hosts must install the LDAP proof utility'
  require_text "$manual" 'ldapsearch -x -H LDAP_URL -D LDAP_BIND_DN -W \' \
    'Native application hosts must perform LDAP bind/search proof'
done

require_text "$jenkins_agent_native" '  ldap-utils ' \
  'Native Jenkins agent host must install the common LDAP utility'

gerrit_baseline='ca-certificates,curl,ldap-utils,openssh-client,openjdk-21-jre-headless,rsync,tar'
jenkins_baseline='ca-certificates,curl,fontconfig,ldap-utils,openjdk-21-jre,openssh-client,rsync,tar,wget'
for spec in \
  "$gerrit_helper:$gerrit_baseline" \
  "$repo_root/examples/gerrit.env.example:$gerrit_baseline" \
  "$jenkins_helper:$jenkins_baseline" \
  "$repo_root/examples/jenkins-controller.env.example:$jenkins_baseline"; do
  file="${spec%%:*}"
  baseline="${spec#*:}"
  require_text "$file" "$baseline" \
    "LDAP host prerequisite baseline is stale: $file"
done

for helper in "$gerrit_helper" "$jenkins_helper"; do
  require_text "$helper" 'ldap-utils) command_name="ldapsearch" ;;' \
    'Role helper must validate the ldap-utils command mapping'
  require_text "$helper" 'ldapsearch -x -H "$LDAP_URL" -D "$LDAP_BIND_DN"' \
    'Role helper must perform LDAP bind/search proof'
  require_text "$helper" '-b "$LDAP_USER_BASE" -s base dn' \
    'Role helper must search the reviewed LDAP user base'
  require_text "$helper" '-b "$LDAP_GROUP_BASE" -s base dn' \
    'Role helper must search the reviewed LDAP group base'
  reject_text "$helper" \
    'OS_DEPENDENCIES must match the static' \
    'Role dependency validation must not override reviewed package input'
done

require_text "$jenkins_helper" 'check_ldap_bind_search' \
  'Jenkins validation must call the LDAP bind/search proof'
reject_text "$jenkins_helper" 'check_ldap_access()' \
  'Jenkins validation must not retain TCP-only LDAP readiness'
require_text "$jenkins_setup" 'TCP reachability' \
  'Jenkins setup manual must reject TCP-only LDAP readiness'

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
mkdir -p "$tmp_dir/bin"
cat >"$tmp_dir/bin/ldapsearch" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${FAKE_LDAP_LOG:?}"
case "$*" in
  *"${FAKE_LDAP_FAIL_BASE:-__no_failure__}"*) exit 1 ;;
esac
SH
chmod +x "$tmp_dir/bin/ldapsearch"

exercise_helper_ldap_proof() {
  local helper secret_function runner log output
  helper="${1:?helper required}"
  secret_function="${2:?secret function required}"
  runner="$tmp_dir/$(basename "$helper").runner"
  log="$tmp_dir/$(basename "$helper").calls"
  {
    printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail'
    printf '%s\n' \
      'die() { printf "%s\n" "$*" >&2; exit 1; }' \
      'is_placeholder() { return 1; }'
    sed -n "/^${secret_function}() {/,/^}/p" "$helper"
    sed -n '/^check_ldap_bind_search() {/,/^}/p' "$helper"
    cat <<'SH'
LDAP_URL=ldaps://ldap.example.internal:636
LDAP_BIND_DN=uid=bind,ou=services,dc=example,dc=internal
LDAP_BIND_PASSWORD=reviewed-password
LDAP_USER_BASE=ou=people,dc=example,dc=internal
LDAP_GROUP_BASE=ou=groups,dc=example,dc=internal
check_ldap_bind_search
SH
  } >"$runner"

  FAKE_LDAP_LOG="$log" PATH="$tmp_dir/bin:$PATH" bash "$runner"
  [ "$(wc -l <"$log")" -eq 2 ] || {
    printf 'LDAP proof must run exactly two searches: %s\n' "$helper" >&2
    exit 1
  }
  grep -Fq -- '-b ou=people,dc=example,dc=internal -s base dn' "$log"
  grep -Fq -- '-b ou=groups,dc=example,dc=internal -s base dn' "$log"
  if grep -Fq -- 'reviewed-password' "$log"; then
    printf 'LDAP proof exposed the bind password in command arguments: %s\n' \
      "$helper" >&2
    exit 1
  fi

  : >"$log"
  if output="$(FAKE_LDAP_LOG="$log" \
    FAKE_LDAP_FAIL_BASE='ou=groups,dc=example,dc=internal' \
    PATH="$tmp_dir/bin:$PATH" bash "$runner" 2>&1)"; then
    printf 'LDAP proof unexpectedly accepted a failed group-base search: %s\n' \
      "$helper" >&2
    exit 1
  fi
  grep -Fq -- 'LDAP bind/search proof failed for configured group base' \
    <<<"$output" || {
    printf 'LDAP proof did not classify the failed group-base search: %s\n' \
      "$helper" >&2
    exit 1
  }
}

exercise_helper_ldap_proof "$gerrit_helper" reviewed_ldap_bind_password
exercise_helper_ldap_proof "$jenkins_helper" ldap_bind_password_value

bash -n "$gerrit_helper" "$jenkins_helper"
printf 'LDAP host prerequisite contract passed\n'
