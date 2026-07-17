#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
fake_bin="$tmp_dir/bin"
calls="$tmp_dir/docker-calls.log"
container_fs="$tmp_dir/container-fs"
run_id="artifact-export-$$"
run_dir="$repo_root/generated/simulation/docker/$run_id"
trap 'rm -rf "$tmp_dir" "$run_dir" "$repo_root/generated/simulation/docker/sets/$run_id"; rm -f "$repo_root/generated/simulation/docker/locks/$run_id.lock"' EXIT

mkdir -p "$fake_bin"
mkdir -p "$container_fs"
cat >"$fake_bin/docker" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$DOCKER_CALLS_LOG"
case "$*" in
  "ps -a --format {{.Names}}")
    if [ "${FAKE_CONTAINERS_EXIST:-0}" = "1" ]; then
      printf '%s-bundle-factory\n%s-ldap\n%s-gerrit-target\n%s-jenkins-controller-target\n%s-jenkins-agent-target\n' \
        "$HARNESS_PROJECT_NAME" "$HARNESS_PROJECT_NAME" "$HARNESS_PROJECT_NAME" "$HARNESS_PROJECT_NAME" "$HARNESS_PROJECT_NAME"
    fi
    ;;
  cp\ *)
    src="${2:?source required}"
    dest="${3:?destination required}"
    case "$src" in
      container-id:*)
        rel="${src#container-id:}"
        cp -R "$FAKE_CONTAINER_FS$rel" "$dest"
        ;;
      *)
        :
        ;;
    esac
    ;;
  *"compose version"*) printf 'Docker Compose version v2.0.0\n' ;;
  compose*)
    if [ "${1:-}" = "compose" ]; then
      shift
    fi
    while [ "$#" -gt 0 ]; do
      case "$1" in
        -f|--file|--project-name|-p)
          shift 2
          ;;
        -*)
          shift
          ;;
        *)
          break
          ;;
      esac
    done
    case "${1:-}" in
      ps)
        printf 'container-id\n'
        ;;
      exec)
        shift
        [ "${1:-}" = "-T" ] && shift
        if [ "${1:-}" = "-u" ]; then
          shift 2
        fi
        service="${1:-}"
        shift
        case "$*" in
          *"/etc/os-release"*)
            printf 'release=24.04 codename=noble pretty=Ubuntu 24.04\n'
            ;;
          "test -x "*)
            exit 0
            ;;
          "env")
            case "$service" in
              bundle-factory) printf 'HARNESS_ENVIRONMENT=bundle-factory\n' ;;
              *) printf 'HARNESS_ENVIRONMENT=%s\n' "$service" ;;
            esac
            ;;
          *"/home/ci-operator/loopforge/scripts/gerrit-setup.sh "*" prepare-artifacts")
            bundle_dir="$FAKE_CONTAINER_FS/var/lib/loopforge/preparing/gerrit-artifacts-bundle"
            dir="$bundle_dir/gerrit"
            mkdir -p "$dir/plugins"
            cat >"$dir/manifest.txt" <<'EOF'
harness_manifest_version=1
role=gerrit
bundle_name=gerrit-artifacts-bundle
ubuntu_release=24.04
ubuntu_codename=noble
java_version=21
gerrit_version=3.13.6
jenkins_version=not-applicable
jenkins_plugin_manager_version=not-applicable
war=gerrit-3.13.6.war
template_count=2
EOF
            printf 'payload\n' >"$dir/plugins/payload.txt"
            (cd "$dir" && sha256sum manifest.txt plugins/payload.txt >checksums.sha256)
            (cd "$bundle_dir" && tar -czf "$FAKE_CONTAINER_FS/var/lib/loopforge/preparing/gerrit-artifacts-bundle.tar.gz" gerrit)
            (cd "$FAKE_CONTAINER_FS/var/lib/loopforge/preparing" && sha256sum gerrit-artifacts-bundle.tar.gz >gerrit-artifacts-bundle.tar.gz.sha256)
            ;;
          *)
            exit 0
            ;;
        esac
        ;;
      *)
        exit 0
        ;;
    esac
    ;;
  inspect*)
    printf 'true\n'
    ;;
esac
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
HARNESS_SET_ID=$run_id
HARNESS_GERRIT_ENV_FILE=examples/gerrit.env.example
HARNESS_JENKINS_CONTROLLER_ENV_FILE=examples/jenkins-controller.env.example
HARNESS_JENKINS_AGENT_ENV_FILE=examples/jenkins-agent.env.example
HARNESS_INTEGRATION_ENV_FILE=examples/integration.env.example
EOF

PATH="$fake_bin:$PATH" \
DOCKER_CALLS_LOG="$calls" \
FAKE_CONTAINER_FS="$container_fs" \
FAKE_CONTAINERS_EXIST=0 \
  "$repo_root/simulation/docker/simulate.sh" --env "$tmp_dir/harness.env" init-run >/dev/null

PATH="$fake_bin:$PATH" \
DOCKER_CALLS_LOG="$calls" \
FAKE_CONTAINER_FS="$container_fs" \
FAKE_CONTAINERS_EXIST=1 \
  "$repo_root/simulation/docker/simulate.sh" --env "$tmp_dir/harness.env" start >/dev/null

PATH="$fake_bin:$PATH" \
DOCKER_CALLS_LOG="$calls" \
FAKE_CONTAINER_FS="$container_fs" \
FAKE_CONTAINERS_EXIST=1 \
  "$repo_root/simulation/docker/simulate.sh" --env "$tmp_dir/harness.env" prepare-artifacts --role gerrit >"$tmp_dir/prepare.out"

export_archive="$run_dir/target/artifacts/exported/gerrit-artifacts-bundle.tar.gz"
prepare_evidence="$(find "$run_dir/host/evidence/harness" -maxdepth 1 -type f -name 'prepare-artifacts-gerrit-*.json' -print | sort | tail -1)"
grep -Fq "artifact-export=gerrit-artifacts-bundle.tar.gz" "$tmp_dir/prepare.out"
[ -f "$export_archive" ] || {
  printf 'Expected exported Gerrit archive\n' >&2
  exit 1
}
[ ! -e "$run_dir/target/artifacts/exported/gerrit-artifacts-bundle.txt" ] || {
  printf 'Did not expect exported Gerrit review sibling\n' >&2
  exit 1
}
[ -n "$prepare_evidence" ] || {
  printf 'Expected prepare-artifacts evidence\n' >&2
  exit 1
}
grep -Fq '"artifact_manifest_references": "/var/lib/loopforge/preparing/gerrit-artifacts-bundle/gerrit/manifest.txt"' "$prepare_evidence"
grep -Fq '"checksum_references": "/var/lib/loopforge/preparing/gerrit-artifacts-bundle.tar.gz.sha256;/var/lib/loopforge/preparing/gerrit-artifacts-bundle/gerrit/checksums.sha256"' "$prepare_evidence"
grep -Fq -- '/home/ci-operator/loopforge-inputs/gerrit.env' "$calls"
grep -Fq -- '/home/ci-operator/loopforge/scripts/gerrit-setup.sh' "$calls"
if grep -Fq -- '/home/ci-operator/loopforge-inputs/bundle-factory/' "$calls"; then
  printf 'Bundle-factory env staging must use the canonical flat operator input path\n' >&2
  exit 1
fi
if grep -Fq -- '/var/lib/loopforge/rendered' "$calls"; then
  printf 'prepare-artifacts must not stage helper env files under Loopforge rendered state\n' >&2
  exit 1
fi
grep -Fq -- '/var/lib/loopforge/preparing' "$calls"
if grep -Fq -- 'install -d -m 0755 -o ci-operator -g ci-operator /var/lib/loopforge' "$calls"; then
  printf 'bundle-factory prepare-artifacts must not set up the Loopforge helper state root in harness\n' >&2
  exit 1
fi
if grep -Fq -- 'install -d -m 0755 -o ci-operator -g ci-operator /var/log/loopforge' "$calls"; then
  printf 'bundle-factory prepare-artifacts must not set up the Loopforge helper log root in harness\n' >&2
  exit 1
fi
if grep -Fq -- 'install -d -m 0755 -o ci-operator -g ci-operator /var/lib/loopforge/preparing/gerrit-artifacts-bundle/gerrit' "$calls"; then
  printf 'bundle-factory prepare-artifacts must not create role payload dirs in harness\n' >&2
  exit 1
fi
if grep -Fq -- 'ldap-bind-password' "$calls"; then
  printf 'prepare-artifacts must not create or stage LDAP bind secrets\n' >&2
  exit 1
fi
grep -Fq -- 'cp container-id:/var/lib/loopforge/preparing/gerrit-artifacts-bundle.tar.gz' "$calls"
grep -Fq -- 'cp container-id:/var/lib/loopforge/preparing/gerrit-artifacts-bundle.tar.gz.sha256' "$calls"
if grep -Fq -- 'cp container-id:/var/lib/loopforge/preparing/gerrit-artifacts-bundle.txt' "$calls"; then
  printf 'prepare-artifacts must not export Gerrit review sibling\n' >&2
  exit 1
fi
[ -f "$run_dir/host/runtime-inputs/gerrit.env" ] || {
  printf 'effective Gerrit input must be retained under host runtime inputs\n' >&2
  exit 1
}
[ ! -e "$run_dir/host/runtime-inputs/helper-envs" ]
[ ! -e "$run_dir/target/product-homes/bundle-factory" ] || {
  printf 'bundle-factory runtime state must not be created under target/product-homes\n' >&2
  exit 1
}
tar -tzf "$export_archive" | grep -Fq 'gerrit/manifest.txt'
if tar -tzf "$export_archive" | grep -Eq '(^|/)checksums/SHA256SUMS$|source-boundary.log|package-intent.manifest|gerrit-artifacts-bundle.txt'; then
  printf 'exported archive contains removed audit files\n' >&2
  exit 1
fi

PATH="$fake_bin:$PATH" \
DOCKER_CALLS_LOG="$calls" \
FAKE_CONTAINER_FS="$container_fs" \
FAKE_CONTAINERS_EXIST=1 \
  "$repo_root/simulation/docker/simulate.sh" --env "$tmp_dir/harness.env" stage-artifacts --role gerrit >"$tmp_dir/stage.out"

stage_evidence="$(find "$run_dir/host/evidence/harness" -maxdepth 1 -type f -name 'stage-artifacts-gerrit-*.json' -print | sort | tail -1)"
[ -n "$stage_evidence" ] || {
  printf 'Expected stage-artifacts evidence\n' >&2
  exit 1
}
grep -Fq '"artifact_manifest_references": "/var/lib/loopforge/staging/gerrit/manifest.txt"' "$stage_evidence"
grep -Fq "$run_dir/target/artifacts/exported/gerrit-artifacts-bundle.tar.gz.sha256" "$stage_evidence"
grep -Fq '/var/lib/loopforge/staging/gerrit/checksums.sha256' "$stage_evidence"
if grep -Fq '/var/lib/loopforge/staging/gerrit-artifacts-bundle/checksums/SHA256SUMS' "$stage_evidence"; then
  printf 'stage evidence must not reference archive-level SHA256SUMS\n' >&2
  exit 1
fi
grep -Fq 'Docker cp simulation-only waiver' "$stage_evidence"
grep -Fq -- 'cp ' "$calls"
grep -Fq -- 'prepare-target-workspace' "$calls"
grep -Fq -- 'gerrit-artifacts-bundle.tar.gz container-id:/tmp/loopforge-docker-cp-' "$calls"
grep -Fq -- 'gerrit-artifacts-bundle.tar.gz.sha256 container-id:/tmp/loopforge-docker-cp-' "$calls"
grep -Fq -- 'test -d /var/lib/loopforge/staging' "$calls"
if grep -Fq -- 'install -d -m 0750 -o ci-operator -g ci-operator /var/lib/loopforge/staging' "$calls"; then
  printf 'stage-artifacts must not create helper-owned staging dirs from the harness\n' >&2
  exit 1
fi
grep -Fq -- 'chown ci-operator:ci-operator /var/lib/loopforge/staging/gerrit-artifacts-bundle.tar.gz' "$calls"
grep -Fq -- 'chown ci-operator:ci-operator /var/lib/loopforge/staging/gerrit-artifacts-bundle.tar.gz.sha256' "$calls"
grep -Fq -- 'tar --no-same-owner -xzf "$archive_name" -C "$staging_root"' "$calls"
if grep -Fq -- 'chown -R ci-operator:ci-operator "$target_bundle_dir"' "$calls" ||
  grep -Fq -- 'find "$target_bundle_dir" -type d -exec chmod 0755 {} +' "$calls" ||
  grep -Fq -- 'find "$target_bundle_dir" -type f -exec chmod 0644 {} +' "$calls"; then
  printf 'stage-artifacts must extract helper-owned bundles as ci-operator without recursive harness ownership repair\n' >&2
  exit 1
fi

[ ! -d "$run_dir/target/artifacts/staging/gerrit/gerrit-artifacts-bundle" ] || {
  printf 'stage-artifacts must not extract target bundles on the host\n' >&2
  exit 1
}
