#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
fake_bin="$tmp_dir/bin"
calls="$tmp_dir/docker-calls.log"
container_fs="$tmp_dir/container-fs"
run_id="artifact-export-$$"
run_dir="$repo_root/generated/simulation/docker/$run_id"
trap 'rm -rf "$tmp_dir" "$run_dir"' EXIT

mkdir -p "$fake_bin"
mkdir -p "$container_fs"
cat >"$fake_bin/docker" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$DOCKER_CALLS_LOG"
case "$*" in
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
          "test -x "*)
            exit 0
            ;;
          "env")
            case "$service" in
              bundle-factory) printf 'HARNESS_ENVIRONMENT=bundle-factory\n' ;;
              *) printf 'HARNESS_ENVIRONMENT=%s\n' "$service" ;;
            esac
            ;;
          *"/workspace/scripts/gerrit-setup.sh "*" prepare-artifacts")
            dir="$FAKE_CONTAINER_FS/var/lib/loopforge/artifact-bundle-work/gerrit"
            mkdir -p "$dir/plugins"
            cat >"$dir/manifest.txt" <<'EOF'
harness_manifest_version=1
role=gerrit
ubuntu_release=24.04
ubuntu_codename=noble
java_version=21
artifact_source=curated-bundle-factory
os_dependency_source=approved-internal-os-repos
public_internet_fallback=simulation-only
bundle_contains_keys=no
gerrit_version=3.13.6
jenkins_version=not-applicable
jenkins_plugin_manager_version=not-applicable
EOF
            printf 'payload\n' >"$dir/plugins/payload.txt"
            (cd "$dir" && sha256sum manifest.txt plugins/payload.txt >checksums.sha256)
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

cat >"$tmp_dir/harness.env" <<EOF
HARNESS_MODE=docker-simulation
HARNESS_RUN_ID=$run_id
HARNESS_PROJECT_NAME=$run_id
HARNESS_GERRIT_ENV_FILE=examples/gerrit.env.example
HARNESS_JENKINS_CONTROLLER_ENV_FILE=examples/jenkins-controller.env.example
HARNESS_JENKINS_AGENT_ENV_FILE=examples/jenkins-agent.env.example
HARNESS_INTEGRATION_ENV_FILE=examples/integration.env.example
EOF

PATH="$fake_bin:$PATH" \
DOCKER_CALLS_LOG="$calls" \
FAKE_CONTAINER_FS="$container_fs" \
  "$repo_root/simulation/docker/simulate.sh" --env "$tmp_dir/harness.env" init-run >/dev/null

PATH="$fake_bin:$PATH" \
DOCKER_CALLS_LOG="$calls" \
FAKE_CONTAINER_FS="$container_fs" \
  "$repo_root/simulation/docker/simulate.sh" --env "$tmp_dir/harness.env" prepare-artifacts --role gerrit >"$tmp_dir/prepare.out"

export_archive="$run_dir/target/artifacts/exported/gerrit-artifacts-bundle.tar.gz"
prepare_evidence="$(find "$run_dir/target/evidence" -maxdepth 1 -type f -name 'prepare-artifacts-gerrit-*.json' -print | sort | tail -1)"
grep -Fq "artifact-export=gerrit-artifacts-bundle.tar.gz" "$tmp_dir/prepare.out"
[ -f "$export_archive" ] || {
  printf 'Expected exported Gerrit archive\n' >&2
  exit 1
}
[ -n "$prepare_evidence" ] || {
  printf 'Expected prepare-artifacts evidence\n' >&2
  exit 1
}
grep -Fq '"artifact_manifest_references": "/var/lib/loopforge/artifact-bundle-work/gerrit/manifest.txt"' "$prepare_evidence"
grep -Fq '"checksum_references": "/var/lib/loopforge/artifact-bundle-work/gerrit/checksums.sha256"' "$prepare_evidence"
grep -Fq -- '/var/lib/loopforge' "$calls"
grep -Fq -- '/var/log/loopforge' "$calls"
grep -Fq -- '/var/lib/loopforge/rendered' "$calls"
grep -Fq -- '/var/lib/loopforge/artifact-bundle-work' "$calls"
grep -Fq -- 'cp container-id:/var/lib/loopforge/artifact-bundle-work/gerrit' "$calls"
[ -d "$run_dir/target/helper-state/bundle-factory/artifact-bundle-work" ] || {
  printf 'bundle-factory artifact workspace debug backing must be created in host state\n' >&2
  exit 1
}
[ -d "$run_dir/host/bundle-factory/rendered" ] || {
  printf 'bundle-factory rendered input debug backing must be created in host state\n' >&2
  exit 1
}
[ -d "$run_dir/target/helper-state/bundle-factory/evidence" ] || {
  printf 'bundle-factory evidence debug backing must be created in host state\n' >&2
  exit 1
}
[ ! -e "$run_dir/target/product-homes/bundle-factory" ] || {
  printf 'bundle-factory runtime state must not be created under target/product-homes\n' >&2
  exit 1
}
tar -tzf "$export_archive" | grep -Fq 'gerrit-artifacts-bundle/gerrit/manifest.txt'
tar -xOf "$export_archive" gerrit-artifacts-bundle/checksums/SHA256SUMS >/dev/null

PATH="$fake_bin:$PATH" \
DOCKER_CALLS_LOG="$calls" \
FAKE_CONTAINER_FS="$container_fs" \
  "$repo_root/simulation/docker/simulate.sh" --env "$tmp_dir/harness.env" stage-artifacts --role gerrit >"$tmp_dir/stage.out"

stage_evidence="$(find "$run_dir/target/evidence" -maxdepth 1 -type f -name 'stage-artifacts-gerrit-*.json' -print | sort | tail -1)"
[ -n "$stage_evidence" ] || {
  printf 'Expected stage-artifacts evidence\n' >&2
  exit 1
}
grep -Fq '"artifact_manifest_references": "/opt/gerrit-artifacts-bundle/gerrit/manifest.txt"' "$stage_evidence"
grep -Fq "$run_dir/target/artifacts/exported/gerrit-artifacts-bundle.tar.gz.sha256" "$stage_evidence"
grep -Fq '/opt/gerrit-artifacts-bundle/checksums/SHA256SUMS' "$stage_evidence"
grep -Fq '/opt/gerrit-artifacts-bundle/gerrit/checksums.sha256' "$stage_evidence"
grep -Fq 'Docker cp simulation-only waiver' "$stage_evidence"
grep -Fq -- 'cp ' "$calls"
grep -Fq -- 'gerrit-artifacts-bundle.tar.gz container-id:/tmp/loopforge-docker-cp-' "$calls"
grep -Fq -- 'gerrit-artifacts-bundle.tar.gz.sha256 container-id:/tmp/loopforge-docker-cp-' "$calls"
grep -Fq -- 'install -d -m 0750 -o ci-operator -g ci-operator /var/lib/loopforge/staging/gerrit/incoming' "$calls"
grep -Fq -- 'chown ci-operator:ci-operator /var/lib/loopforge/staging/gerrit/incoming/gerrit-artifacts-bundle.tar.gz' "$calls"
grep -Fq -- 'chown ci-operator:ci-operator /var/lib/loopforge/staging/gerrit/incoming/gerrit-artifacts-bundle.tar.gz.sha256' "$calls"
grep -Fq -- 'tar -xzf "$archive_name" -C /opt' "$calls"

[ ! -d "$run_dir/target/artifacts/staging/gerrit/gerrit-artifacts-bundle" ] || {
  printf 'stage-artifacts must not extract target bundles on the host\n' >&2
  exit 1
}
