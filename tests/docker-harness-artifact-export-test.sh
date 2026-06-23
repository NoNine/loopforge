#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
fake_bin="$tmp_dir/bin"
run_id="artifact-export-$$"
run_dir="$repo_root/generated/simulation/docker/$run_id"
trap 'rm -rf "$tmp_dir" "$run_dir"' EXIT

mkdir -p "$fake_bin"
cat >"$fake_bin/docker" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
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
            dir="$HARNESS_STATE_DIR/bundle-factory/artifact-bundle-work/gerrit"
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
  "$repo_root/simulation/docker/simulate.sh" --env "$tmp_dir/harness.env" render-config >/dev/null

PATH="$fake_bin:$PATH" \
  "$repo_root/simulation/docker/simulate.sh" --env "$tmp_dir/harness.env" prepare-artifacts --role gerrit >"$tmp_dir/prepare.out"

export_archive="$run_dir/exported-artifacts/gerrit-artifacts-bundle.tar.gz"
grep -Fq "artifact-export=gerrit-artifacts-bundle.tar.gz" "$tmp_dir/prepare.out"
[ -f "$export_archive" ] || {
  printf 'Expected exported Gerrit archive\n' >&2
  exit 1
}
tar -tzf "$export_archive" | grep -Fq 'gerrit-artifacts-bundle/gerrit/manifest.txt'
tar -xOf "$export_archive" gerrit-artifacts-bundle/checksums/SHA256SUMS >/dev/null
