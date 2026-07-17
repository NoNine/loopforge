#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/scripts"
cp "$repo_root/scripts/common.sh" "$tmp_dir/scripts/common.sh"
cp "$repo_root/scripts/jenkins-controller-setup.sh" \
  "$tmp_dir/scripts/jenkins-controller-setup.sh"

rendered="$tmp_dir/jenkins.yaml"
bash -c '
  set -euo pipefail
  # shellcheck source=/dev/null
  . "$1"
  JENKINS_HOME="/var/lib/jenkins"
  CASC_JENKINS_CONFIG="/var/lib/jenkins/jcasc/jenkins.yaml"
  JENKINS_HTTP_PORT="8080"
  JENKINS_RUNTIME_ACCOUNT="jenkins"
  JENKINS_RUNTIME_GROUP="jenkins"
  JENKINS_URL="http://jenkins-controller-target:8080/"
  LDAP_URL="ldap://ldap:389"
  LDAP_BIND_DN="cn=readonly,dc=example,dc=test"
  LDAP_BIND_PASSWORD="reviewed-bind-secret"
  LDAP_USER_BASE="ou=people,dc=example,dc=test"
  LDAP_GROUP_BASE="ou=groups,dc=example,dc=test"
  JENKINS_ADMIN_ACCOUNT="site-jenkins-admin"
  JENKINS_VERIFICATION_MODE="docker-simulation"
  render_template "$2" "$3"
' test-driver "$tmp_dir/scripts/jenkins-controller-setup.sh" \
  "$repo_root/templates/jenkins-controller/jenkins-jcasc.yaml.template" \
  "$rendered"

grep -Fq 'globalMatrix:' "$rendered"
grep -Fq 'name: "site-jenkins-admin"' "$rendered"
grep -Fq 'name: "authenticated"' "$rendered"
for permission in Overall/Administer Overall/Read Job/Read Job/Build; do
  grep -Fq "\"$permission\"" "$rendered"
done
if grep -Fq 'loggedInUsersCanDoAnything:' "$rendered"; then
  printf 'Controller JCasC must not grant every logged-in user administrator access\n' >&2
  exit 1
fi
if rg -n 'JENKINS_ADMIN_GROUP' \
  "$repo_root/scripts/jenkins-controller-setup.sh" \
  "$repo_root/examples/jenkins-controller.env.example" \
  "$repo_root/docs/operations/setup/jenkins-controller.md"; then
  printf 'Controller role interface must not retain the obsolete admin-group input\n' >&2
  exit 1
fi
grep -Fq '__docker_roles_validate_jenkins_controller_authorization "$service" "$log"' \
  "$repo_root/simulation/docker/lib/roles.sh"
grep -Fq 'Jenkins.ADMINISTER' \
  "$repo_root/simulation/docker/scripts/verify-jenkins-authorization.groovy"
grep -Fq "Item.BUILD, 'authenticated'" \
  "$repo_root/simulation/docker/scripts/verify-jenkins-authorization.groovy"

printf 'Jenkins controller authorization contract passed\n'
