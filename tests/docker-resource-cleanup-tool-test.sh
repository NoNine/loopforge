#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
tool="$repo_root/simulation/docker/tools/cleanup-docker-resources.sh"
tmp_dir="$(mktemp -d)"
stub_bin="$tmp_dir/bin"
state="$tmp_dir/state"
mutation_log="$tmp_dir/mutations.log"
compose_file="$repo_root/simulation/docker/compose.yaml"
docker_dir="$repo_root/simulation/docker"
trap 'rm -rf "$tmp_dir"' EXIT
mkdir -p "$stub_bin"

cat >"$stub_bin/docker" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
state="${DOCKER_TOOL_TEST_STATE:?}"
log="${DOCKER_TOOL_TEST_LOG:?}"
fail="${DOCKER_TOOL_FAIL:-}"
fail_if_requested() {
  [ "$fail" != "$1" ] || exit 42
}
find_record() {
  file="$1"
  key="$2"
  awk -F '\t' -v key="$key" '$1 == key { print; found = 1; exit } END { exit !found }' "$file"
}
case "$*" in
  version)
    fail_if_requested version
    printf 'Docker version stub\n'
    ;;
  'ps -a -q --filter label=org.loopforge.resource=docker-simulation')
    fail_if_requested ps
    awk -F '\t' '$3 == "docker-simulation" { print $1 }' "$state/containers.tsv"
    ;;
  'ps -a -q --filter label=com.docker.compose.project')
    fail_if_requested ps
    awk -F '\t' '$7 != "" && $7 != "<no value>" { print $1 }' "$state/containers.tsv"
    ;;
  container\ inspect\ -f*)
    fail_if_requested container-inspect
    id="${@: -1}"
    record="$(find_record "$state/containers.tsv" "$id")"
    IFS=$'\t' read -r rid name lf_resource lf_project lf_run lf_service compose_project compose_service config work <<<"$record"
    printf '%s\t/%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$rid" "$name" "$lf_resource" "$lf_project" "$lf_run" "$lf_service" \
      "$compose_project" "$compose_service" "$config" "$work"
    ;;
  'network ls -q --filter label=org.loopforge.resource=docker-simulation')
    fail_if_requested network-ls
    awk -F '\t' '$3 == "docker-simulation" { print $1 }' "$state/networks.tsv"
    ;;
  'network ls -q --filter label=com.docker.compose.project')
    fail_if_requested network-ls
    awk -F '\t' '$7 != "" && $7 != "<no value>" { print $1 }' "$state/networks.tsv"
    ;;
  network\ inspect\ -f*)
    fail_if_requested network-inspect
    id="${@: -1}"
    record="$(find_record "$state/networks.tsv" "$id")"
    IFS=$'\t' read -r rid name lf_resource lf_project lf_run lf_network compose_project compose_network config work <<<"$record"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$rid" "$name" "$lf_resource" "$lf_project" "$lf_run" "$lf_network" \
      "$compose_project" "$compose_network" "$config" "$work"
    ;;
  'images -q --filter label=org.loopforge.resource=docker-simulation')
    fail_if_requested images
    awk -F '\t' '$2 == "docker-simulation" { print $1 }' "$state/images.tsv"
    ;;
  'images -q --filter label=com.docker.compose.project')
    fail_if_requested images
    awk -F '\t' '$6 != "" && $6 != "<no value>" { print $1 }' "$state/images.tsv"
    ;;
  image\ inspect\ -f*)
    fail_if_requested image-inspect
    id="${@: -1}"
    record="$(find_record "$state/images.tsv" "$id")"
    IFS=$'\t' read -r rid lf_resource lf_project lf_run lf_service compose_project compose_service config work <<<"$record"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$rid" "$lf_resource" "$lf_project" "$lf_run" "$lf_service" \
      "$compose_project" "$compose_service" "$config" "$work"
    ;;
  rm\ -f\ *)
    fail_if_requested container-rm
    id="${*:3}"
    printf 'container-rm %s\n' "$id" >>"$log"
    awk -F '\t' -v key="$id" '$1 != key' "$state/containers.tsv" >"$state/containers.tmp"
    mv "$state/containers.tmp" "$state/containers.tsv"
    ;;
  network\ rm\ *)
    fail_if_requested network-rm
    id="${*:3}"
    printf 'network-rm %s\n' "$id" >>"$log"
    awk -F '\t' -v key="$id" '$1 != key' "$state/networks.tsv" >"$state/networks.tmp"
    mv "$state/networks.tmp" "$state/networks.tsv"
    ;;
  image\ rm\ *)
    fail_if_requested image-rm
    id="${*:3}"
    printf 'image-rm %s\n' "$id" >>"$log"
    awk -F '\t' -v key="$id" '$1 != key' "$state/images.tsv" >"$state/images.tmp"
    mv "$state/images.tmp" "$state/images.tsv"
    ;;
  *)
    printf 'unexpected docker command: %s\n' "$*" >&2
    exit 2
    ;;
esac
STUB
chmod +x "$stub_bin/docker"

reset_state() {
  rm -rf "$state"
  mkdir -p "$state"
  : >"$mutation_log"
  cat >"$state/containers.tsv" <<EOF_CONTAINERS
c1	lf-bundle-factory	docker-simulation	projA	runA	bundle-factory	<no value>	<no value>	<no value>	<no value>
c2	custom-gerrit	docker-simulation	customProj	runB	gerrit-target	<no value>	<no value>	<no value>	<no value>
c3	unrelated	<no value>	<no value>	<no value>	<no value>	unrelated	other-service	<no value>	<no value>
c4	foreign-bundle	<no value>	<no value>	<no value>	<no value>	foreignProj	bundle-factory	/tmp/foreign/compose.yaml	/tmp/foreign
c5	repo-compose-bundle	<no value>	<no value>	<no value>	<no value>	repoCompose	bundle-factory	$compose_file	$docker_dir
c6	no-source-compose	<no value>	<no value>	<no value>	<no value>	noSource	bundle-factory	<no value>	<no value>
EOF_CONTAINERS
  cat >"$state/networks.tsv" <<EOF_NETWORKS
n1	projA_harness	docker-simulation	projA	runA	harness	<no value>	<no value>	<no value>	<no value>
n2	repoCompose_harness	<no value>	<no value>	<no value>	<no value>	repoCompose	harness	$compose_file	$docker_dir
n3	foreign_harness	<no value>	<no value>	<no value>	<no value>	foreign	harness	/tmp/foreign/compose.yaml	/tmp/foreign
n4	projA_default	docker-simulation	projA	runA	default	<no value>	<no value>	<no value>	<no value>
n5	noSource_harness	<no value>	<no value>	<no value>	<no value>	noSource	harness	<no value>	<no value>
EOF_NETWORKS
  cat >"$state/images.tsv" <<EOF_IMAGES
i1	docker-simulation	projA	runA	bundle-factory	<no value>	<no value>	<no value>	<no value>
i2	docker-simulation	customProj	runB	gerrit-target	<no value>	<no value>	<no value>	<no value>
i3	<no value>	<no value>	<no value>	<no value>	foreignProj	bundle-factory	/tmp/foreign/compose.yaml	/tmp/foreign
ubuntu:24.04	<no value>	<no value>	<no value>	<no value>	<no value>	<no value>	<no value>	<no value>
i4	<no value>	<no value>	<no value>	<no value>	repoCompose	jenkins-agent-target	$compose_file	$docker_dir
i5	<no value>	<no value>	<no value>	<no value>	noSource	ldap	<no value>	<no value>
EOF_IMAGES
}

run_tool() {
  env PATH="$stub_bin:$PATH" \
    DOCKER_TOOL_TEST_STATE="$state" \
    DOCKER_TOOL_TEST_LOG="$mutation_log" \
    DOCKER_TOOL_FAIL="${DOCKER_TOOL_FAIL:-}" \
    "$tool" "$@"
}

reset_state
dry_out="$tmp_dir/dry-run.out"
run_tool --dry-run >"$dry_out"
grep -Fq 'would-remove-container id=c1 name=lf-bundle-factory project=projA service=bundle-factory' "$dry_out"
grep -Fq 'would-remove-container id=c2 name=custom-gerrit project=customProj service=gerrit-target' "$dry_out"
grep -Fq 'would-remove-container id=c5 name=repo-compose-bundle project=repoCompose service=bundle-factory' "$dry_out"
grep -Fq 'would-remove-network id=n1 name=projA_harness project=projA' "$dry_out"
grep -Fq 'would-remove-network id=n2 name=repoCompose_harness project=repoCompose' "$dry_out"
grep -Fq 'would-remove-image target=i1 project=projA service=bundle-factory' "$dry_out"
grep -Fq 'would-remove-image target=i2 project=customProj service=gerrit-target' "$dry_out"
grep -Fq 'would-remove-image target=i4 project=repoCompose service=jenkins-agent-target' "$dry_out"
grep -Fq 'dry-run: ok containers=3 networks=2 images=3' "$dry_out"
if grep -Eq 'foreign|ubuntu:24.04|unrelated|projA_default|noSource|no-source' "$dry_out"; then
  printf 'dry-run must not include unrelated resources or base images\n' >&2
  exit 1
fi
[ ! -s "$mutation_log" ]

run_tool >"$tmp_dir/cleanup.out"
grep -Fq 'cleanup: ok containers=3 networks=2 images=3' "$tmp_dir/cleanup.out"
grep -Fxq 'container-rm c1' "$mutation_log"
grep -Fxq 'container-rm c2' "$mutation_log"
grep -Fxq 'container-rm c5' "$mutation_log"
grep -Fxq 'network-rm n1' "$mutation_log"
grep -Fxq 'network-rm n2' "$mutation_log"
grep -Fxq 'image-rm i1' "$mutation_log"
grep -Fxq 'image-rm i2' "$mutation_log"
grep -Fxq 'image-rm i4' "$mutation_log"

c_line="$(grep -n '^container-rm c1$' "$mutation_log" | cut -d: -f1)"
n_line="$(grep -n '^network-rm n1$' "$mutation_log" | cut -d: -f1)"
i_line="$(grep -n '^image-rm i1$' "$mutation_log" | cut -d: -f1)"
[ "$c_line" -lt "$n_line" ]
[ "$n_line" -lt "$i_line" ]

grep -Fq $'c3\tunrelated' "$state/containers.tsv"
grep -Fq $'c4\tforeign-bundle' "$state/containers.tsv"
grep -Fq $'c6\tno-source-compose' "$state/containers.tsv"
grep -Fq $'n3\tforeign_harness' "$state/networks.tsv"
grep -Fq $'n4\tprojA_default' "$state/networks.tsv"
grep -Fq $'n5\tnoSource_harness' "$state/networks.tsv"
grep -Fq $'ubuntu:24.04' "$state/images.tsv"
grep -Fq $'i3\t<no value>\t<no value>\t<no value>\t<no value>\tforeignProj' "$state/images.tsv"
grep -Fq $'i5\t<no value>\t<no value>\t<no value>\t<no value>\tnoSource' "$state/images.tsv"

run_tool >"$tmp_dir/repeat.out"
grep -Fq 'cleanup: ok containers=0 networks=0 images=0' "$tmp_dir/repeat.out"

for failure in version ps container-inspect network-ls network-inspect images image-inspect \
  container-rm network-rm image-rm; do
  reset_state
  if DOCKER_TOOL_FAIL="$failure" run_tool >"$tmp_dir/fail-$failure.out" 2>"$tmp_dir/fail-$failure.err"; then
    printf 'Docker cleanup tool must propagate failure: %s\n' "$failure" >&2
    exit 1
  fi
  if grep -Fq 'cleanup: ok' "$tmp_dir/fail-$failure.out"; then
    printf 'Docker cleanup tool must not report success after failure: %s\n' "$failure" >&2
    exit 1
  fi
done

if run_tool --unknown >"$tmp_dir/unknown.out" 2>"$tmp_dir/unknown.err"; then
  printf 'Docker cleanup tool must reject unknown options\n' >&2
  exit 1
fi
grep -Fq 'Unknown option: --unknown' "$tmp_dir/unknown.err"

grep -Fq -- '--dry-run' < <("$tool" --help)
if grep -Eq 'rm -rf|generated/simulation/docker' "$tool"; then
  printf 'Docker cleanup tool must not delete generated workspaces directly\n' >&2
  exit 1
fi
