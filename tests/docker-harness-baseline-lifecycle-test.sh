#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
fake_bin="$tmp_dir/bin"
run_id="baseline-life-$$"
set_id="baseline-life-$$"
secret_run_id="baseline-secret-$$"
secret_set_id="baseline-secret-$$"
docker_root="$repo_root/generated/simulation/docker"
run_dir="$docker_root/$run_id"
set_dir="$docker_root/sets/$set_id"
calls="$tmp_dir/docker-calls.log"

cleanup() {
  rc=$?
  if [ "$rc" -ne 0 ] && [ -f "$calls" ]; then
    tail -80 "$calls" >&2
  fi
  rm -rf "$tmp_dir" "$run_dir" "$docker_root/$secret_run_id" \
    "$set_dir" "$docker_root/sets/$secret_set_id"
  rm -f "$docker_root/locks/$set_id.lock" \
    "$docker_root/locks/$secret_set_id.lock"
  exit "$rc"
}
trap cleanup EXIT

mkdir -p "$fake_bin"
cat >"$fake_bin/docker" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$DOCKER_CALLS_LOG"
. "$DOCKER_SET_FAKE_LIB"
if fake_docker_set_handle "$@"; then
  exit 0
else
  rc=$?
  [ "$rc" -eq 125 ] || exit "$rc"
fi
exit 0
SH
chmod +x "$fake_bin/docker"

cat >"$fake_bin/ssh-keyscan" <<'SH'
#!/usr/bin/env bash
printf '[127.0.0.1]:%s ssh-ed25519 test-key\n' "${4:-22}"
SH
chmod +x "$fake_bin/ssh-keyscan"

cat >"$tmp_dir/harness.env" <<EOF
HARNESS_MODE=docker-simulation
HARNESS_RUN_ID=$run_id
HARNESS_SET_ID=$set_id
HARNESS_GERRIT_ENV_FILE=examples/gerrit.env.example
HARNESS_JENKINS_CONTROLLER_ENV_FILE=examples/jenkins-controller.env.example
HARNESS_JENKINS_AGENT_ENV_FILE=examples/jenkins-agent.env.example
HARNESS_INTEGRATION_ENV_FILE=examples/integration.env.example
EOF

cat >"$tmp_dir/secret.env" <<EOF
HARNESS_MODE=docker-simulation
HARNESS_RUN_ID=$secret_run_id
HARNESS_SET_ID=$secret_set_id
HARNESS_GERRIT_ENV_FILE=examples/gerrit.env.example
HARNESS_JENKINS_CONTROLLER_ENV_FILE=examples/jenkins-controller.env.example
HARNESS_JENKINS_AGENT_ENV_FILE=examples/jenkins-agent.env.example
HARNESS_INTEGRATION_ENV_FILE=examples/integration.env.example
EOF

export PATH="$fake_bin:$PATH"
export DOCKER_CALLS_LOG="$calls"
export DOCKER_SET_FAKE_LIB="$repo_root/tests/fixtures/docker-set-state.sh"
export DOCKER_SET_FAKE_STATE_DIR="$tmp_dir/docker-state"
export DOCKER_SET_FAKE_BASELINE_MARKER=1
export REPO_ROOT="$repo_root"

simulate=("$repo_root/simulation/docker/simulate.sh" --env "$tmp_dir/harness.env")
"${simulate[@]}" init-run >/dev/null
"${simulate[@]}" create >"$tmp_dir/create.out"
grep -Fxq 'create: ok state=created resources=stopped' "$tmp_dir/create.out"

manifest="$set_dir/baseline/manifest.env"
[ -f "$manifest" ]
for archive in ldap_data ldap_config gerrit_home jenkins_controller_home \
  jenkins_agent_home shared_jenkins_storage; do
  [ -s "$set_dir/baseline/archives/$archive.tar" ]
  grep -Eq "^archive_${archive}_sha256=[a-f0-9]{64}$" "$manifest"
done
grep -Eq '^implementation_revision=[a-f0-9]{64}$' "$manifest"
grep -Eq '^ssh_identities_sha256=[a-f0-9]{64}$' "$manifest"
baseline_fingerprint="$(sha256sum "$manifest" | awk '{print $1}')"
grep -Fxq "baseline_fingerprint=$baseline_fingerprint" \
  "$set_dir/active-run.env"
grep -Fxq "baseline_fingerprint=$baseline_fingerprint" \
  "$run_dir/host/state/workflow-state.env"
archive="$set_dir/baseline/archives/ldap_data.tar"
cp "$archive" "$tmp_dir/ldap-data.tar"
printf 'drift\n' >>"$archive"
if "${simulate[@]}" start >"$tmp_dir/start-archive-drift.out" 2>&1; then
  printf 'start unexpectedly accepted a drifted baseline archive\n' >&2
  exit 1
fi
grep -Fq 'Docker baseline archive checksum drifted: ldap_data' \
  "$tmp_dir/start-archive-drift.out"
mv "$tmp_dir/ldap-data.tar" "$archive"

"${simulate[@]}" start >/dev/null
if "${simulate[@]}" restore-baseline >"$tmp_dir/restore-running.out" 2>&1; then
  printf 'restore-baseline unexpectedly accepted a running set\n' >&2
  exit 1
fi
grep -Fq 'requires the selected set to be stopped' "$tmp_dir/restore-running.out"
"${simulate[@]}" stop >/dev/null

runtime="$set_dir/runtime"
printf 'mutated\n' >"$runtime/ldap/data/mutated"
printf 'mutated\n' >"$runtime/ldap/config/mutated"
printf 'mutated\n' >"$runtime/product-homes/gerrit/gerrit.config"
printf 'mutated\n' >"$runtime/product-homes/jenkins-controller/config.xml"
printf 'mutated\n' >"$runtime/product-homes/jenkins-agent/workspace"
printf 'mutated\n' >"$runtime/shared-jenkins-storage/proof"

containers="$DOCKER_SET_FAKE_STATE_DIR/containers"
selected_before="$(awk -F '\t' -v prefix="loopforge-docker-$set_id-" \
  'index($1, prefix) == 1 { print $2 }' "$containers")"
printf 'unrelated-container\tunrelated-id\tfalse\tunrelated-image\toverlayfs\n' \
  >>"$containers"
cp "$containers" "$tmp_dir/containers.before-image-drift"
awk -F '\t' -v prefix="loopforge-docker-$set_id-gerrit-target" \
  'BEGIN { OFS="\t" } $1 == prefix { $4="drifted-image" } { print }' \
  "$containers" >"$containers.tmp"
mv "$containers.tmp" "$containers"
if "${simulate[@]}" restore-baseline >"$tmp_dir/restore-image-drift.out" 2>&1; then
  printf 'restore-baseline unexpectedly accepted selected image drift\n' >&2
  exit 1
fi
grep -Fq 'container, image, network, or storage identity drifted' \
  "$tmp_dir/restore-image-drift.out"
mv "$tmp_dir/containers.before-image-drift" "$containers"

restore_line=$(( $(wc -l <"$calls") + 1 ))
"${simulate[@]}" restore-baseline >"$tmp_dir/restore.out"
grep -Fxq 'restore-baseline: ok state=restored-pending-clean durable=baseline resources=stopped' \
  "$tmp_dir/restore.out"
[ "$baseline_fingerprint" = "$(sha256sum "$manifest" | awk '{print $1}')" ]

selected_after="$(awk -F '\t' -v prefix="loopforge-docker-$set_id-" \
  'index($1, prefix) == 1 { print $2 }' "$containers")"
[ "$selected_before" != "$selected_after" ]
grep -Fxq $'unrelated-container\tunrelated-id\tfalse\tunrelated-image\toverlayfs' \
  "$containers"
[ "$(cat "$runtime/ldap/data/clean-marker")" = clean-ldap-baseline ]
for path in \
  "$runtime/ldap/data/mutated" \
  "$runtime/ldap/config/mutated" \
  "$runtime/product-homes/gerrit/gerrit.config" \
  "$runtime/product-homes/jenkins-controller/config.xml" \
  "$runtime/product-homes/jenkins-agent/workspace" \
  "$runtime/shared-jenkins-storage/proof"; do
  [ ! -e "$path" ]
done

tail -n +"$restore_line" "$calls" >"$tmp_dir/restore-calls"
grep -Fq 'run --rm --network none --read-only --user 0:0' \
  "$tmp_dir/restore-calls"
grep -Eq 'compose .* up --no-start --no-build$' "$tmp_dir/restore-calls"
if grep -Fq 'rm unrelated-id' "$tmp_dir/restore-calls"; then
  printf 'restore-baseline removed an unrelated container\n' >&2
  exit 1
fi

active="$set_dir/active-run.env"
grep -Fxq 'state=restored-pending-clean' "$active"
restore_sha="$(sed -n 's/^restore_evidence_sha256=//p' "$active")"
evidence="$(find "$run_dir/host/evidence" -type f -name '*restore-baseline*' -print -quit)"
[ -n "$evidence" ]
[ "$restore_sha" = "$(sha256sum "$evidence" | awk '{print $1}')" ]
if "${simulate[@]}" restore-baseline >"$tmp_dir/restore-repeat.out" 2>&1; then
  printf 'restore-baseline unexpectedly repeated after the reset gate\n' >&2
  exit 1
fi
grep -Fq 'blocks reset gate: restored-pending-clean' "$tmp_dir/restore-repeat.out"

scanner_archive="$tmp_dir/application.tar"
mkdir -p "$tmp_dir/application"
printf 'application-secret\n' >"$tmp_dir/application/config"
tar -C "$tmp_dir/application" -cf "$scanner_archive" .
if HARNESS_LDAP_ADMIN_PASSWORD=application-secret \
  HARNESS_LDAP_CONFIG_PASSWORD=unused-config-secret \
  HARNESS_LDAP_BIND_PASSWORD=unused-bind-secret \
  bash -c '. "$1/simulation/docker/lib/baseline.sh"; __docker_baseline_archive_excludes_secrets "$2" gerrit_home' \
  bash "$repo_root" "$scanner_archive"; then
  printf 'Docker baseline scanner accepted a credential in application state\n' >&2
  exit 1
fi

export DOCKER_SET_FAKE_STATE_DIR="$tmp_dir/secret-state"
export DOCKER_SET_FAKE_BASELINE_SECRET=1
secret_simulate=("$repo_root/simulation/docker/simulate.sh" --env "$tmp_dir/secret.env")
"${secret_simulate[@]}" init-run >/dev/null
"${secret_simulate[@]}" create >"$tmp_dir/create-secret.out"
grep -Fxq 'create: ok state=created resources=stopped' "$tmp_dir/create-secret.out"
[ -f "$docker_root/sets/$secret_set_id/baseline/manifest.env" ]
tar -xOf "$docker_root/sets/$secret_set_id/baseline/archives/ldap_data.tar" >"$tmp_dir/secret-ldap-content"
grep -aFq 'readonly-password' "$tmp_dir/secret-ldap-content"

printf 'Docker baseline lifecycle test passed\n'
