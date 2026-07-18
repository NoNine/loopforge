#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
fake_bin="$tmp_dir/bin"
run_id="set-lifecycle-$$"
set_id="set-life-$$"
project_name="loopforge-docker-$set_id"
run_dir="$repo_root/generated/simulation/docker/$run_id"
set_dir="$repo_root/generated/simulation/docker/sets/$set_id"
calls="$tmp_dir/docker-calls.log"
containers="$tmp_dir/containers"
network="$tmp_dir/network"

cleanup() {
  rc=$?
  if [ "$rc" -ne 0 ] && [ -f "$calls" ]; then
    tail -80 "$calls" >&2
  fi
  rm -rf "$tmp_dir" "$run_dir" "$set_dir"
  rm -f "$repo_root/generated/simulation/docker/locks/$set_id.lock"
  exit "$rc"
}
trap cleanup EXIT

mkdir -p "$fake_bin"
cat >"$fake_bin/docker" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >>"$DOCKER_CALLS_LOG"
services=(bundle-factory ldap gerrit-target jenkins-controller-target jenkins-agent-target)

container_field() {
  local name field
  name="$1"
  field="$2"
  awk -F '\t' -v name="$name" -v field="$field" '
    $1 == name || $2 == name {
      if (field == "id") print $2
      if (field == "running") print $3
      if (field == "image") print $4
      if (field == "driver") print $5
    }
  ' "$DOCKER_CONTAINERS_FILE"
}

set_all_power() {
  local power
  power="$1"
  awk -F '\t' -v power="$power" 'BEGIN { OFS="\t" } { $3=power; print }' \
    "$DOCKER_CONTAINERS_FILE" >"$DOCKER_CONTAINERS_FILE.tmp"
  mv "$DOCKER_CONTAINERS_FILE.tmp" "$DOCKER_CONTAINERS_FILE"
}

create_containers() {
  local service index
  : >"$DOCKER_CONTAINERS_FILE"
  index=0
  for service in "${services[@]}"; do
    index=$((index + 1))
    printf '%s-%s\tcid-%s\tfalse\timage-%s\toverlayfs\n' \
      "$HARNESS_PROJECT_NAME" "$service" "$index" "$service" \
      >>"$DOCKER_CONTAINERS_FILE"
  done
}

compose_command=""
if [ "${1:-}" = compose ]; then
  shift
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --project-name|--file) shift 2 ;;
      *) compose_command="$1"; shift; break ;;
    esac
  done
fi

case "$compose_command" in
  version)
    printf 'Docker Compose version v2.0.0\n'
    exit 0
    ;;
  config)
    printf 'project=%s compose=v1\n' "$HARNESS_PROJECT_NAME"
    exit 0
    ;;
  build)
    exit 0
    ;;
  create)
    create_containers
    exit 0
    ;;
  up)
    [ "${1:-}" = --no-start ] && [ "${2:-}" = --no-build ] || exit 2
    create_containers
    printf '%s_harness\tnetwork-id\n' "$HARNESS_PROJECT_NAME" >"$DOCKER_NETWORK_FILE"
    exit 0
    ;;
  start)
    [ -f "$DOCKER_NETWORK_FILE" ] || exit 1
    set_all_power true
    exit 0
    ;;
  stop)
    set_all_power false
    exit 0
    ;;
  exec)
    service=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        -T|-u) [ "$1" = -u ] && shift; shift ;;
        *) service="$1"; shift; break ;;
      esac
    done
    command_text="$*"
    case "$command_text" in
      *'/etc/os-release'*)
        printf 'release=24.04 codename=noble pretty=Ubuntu 24.04\n'
        ;;
      *"stat -c %u:%g"*|*"stat -c '%u:%g'"*)
        case "$service" in
          gerrit-target) printf '61010:61010\n' ;;
          jenkins-controller-target) printf '61020:61020\n' ;;
          jenkins-agent-target) printf '61030:61030\n' ;;
        esac
        ;;
      *'stat -Lc %d:%i'*|*"stat -Lc '%d:%i'"*)
        destination="${*: -1}"
        case "$service:$destination" in
          ldap:/var/lib/ldap) path="$HARNESS_LDAP_DATA_DIR" ;;
          ldap:/etc/ldap/slapd.d) path="$HARNESS_LDAP_CONFIG_DIR" ;;
          gerrit-target:/workspace|jenkins-controller-target:/workspace|jenkins-agent-target:/workspace|bundle-factory:/workspace) path="$REPO_ROOT" ;;
          gerrit-target:/srv/gerrit) path="$HARNESS_PRODUCT_HOME_DIR/gerrit" ;;
          jenkins-controller-target:/var/lib/jenkins) path="$HARNESS_PRODUCT_HOME_DIR/jenkins-controller" ;;
          jenkins-agent-target:/var/lib/jenkins-agent) path="$HARNESS_PRODUCT_HOME_DIR/jenkins-agent" ;;
          jenkins-controller-target:/data/jenkins-shared|jenkins-agent-target:/data/jenkins-shared) path="$HARNESS_SHARED_JENKINS_STORAGE_DIR" ;;
          *) exit 1 ;;
        esac
        stat -Lc '%d:%i' "$path"
        ;;
    esac
    exit 0
    ;;
esac

case "${1:-}" in
  ps)
    shift
    if [ "${1:-}" = -a ] && [ "${2:-}" = --format ]; then
      [ ! -f "$DOCKER_CONTAINERS_FILE" ] || cut -f1 "$DOCKER_CONTAINERS_FILE"
      exit 0
    fi
    ;;
  inspect)
    shift
    [ "${1:-}" = -f ] || exit 1
    format="$2"
    name="$3"
    case "$format" in
      '{{.Id}}') container_field "$name" id ;;
      '{{.Image}}') container_field "$name" image ;;
      '{{json .GraphDriver.Data}}') exit 97 ;;
      '{{.Driver}}')
        [ "${DOCKER_DRIVER_INSPECT_FAIL:-0}" != 1 ] || exit 98
        container_field "$name" driver
        ;;
      '{{.State.Running}}') container_field "$name" running ;;
      *'.Mounts'*)
        service="${name#"$HARNESS_PROJECT_NAME"-}"
        case "$service" in
          bundle-factory)
            printf '%s\t/workspace\n' "$REPO_ROOT"
            ;;
          ldap)
            printf '%s\t/var/lib/ldap\n' "$HARNESS_LDAP_DATA_DIR"
            printf '%s\t/etc/ldap/slapd.d\n' "$HARNESS_LDAP_CONFIG_DIR"
            ;;
          gerrit-target)
            printf '%s\t/workspace\n' "$REPO_ROOT"
            printf '%s\t/srv/gerrit\n' "$HARNESS_PRODUCT_HOME_DIR/gerrit"
            ;;
          jenkins-controller-target)
            printf '%s\t/workspace\n' "$REPO_ROOT"
            printf '%s\t/var/lib/jenkins\n' "$HARNESS_PRODUCT_HOME_DIR/jenkins-controller"
            printf '%s\t/data/jenkins-shared\n' "$HARNESS_SHARED_JENKINS_STORAGE_DIR"
            ;;
          jenkins-agent-target)
            printf '%s\t/workspace\n' "$REPO_ROOT"
            printf '%s\t/var/lib/jenkins-agent\n' "$HARNESS_PRODUCT_HOME_DIR/jenkins-agent"
            printf '%s\t/data/jenkins-shared\n' "$HARNESS_SHARED_JENKINS_STORAGE_DIR"
            ;;
        esac
        ;;
      *'org.loopforge.resource'*) printf 'docker-simulation\n' ;;
      *'org.loopforge.project'*) printf '%s\n' "$HARNESS_PROJECT_NAME" ;;
      *'org.loopforge.set-id'*) printf '%s\n' "$HARNESS_SET_ID" ;;
      *'org.loopforge.service'*) printf '%s\n' "${name#"$HARNESS_PROJECT_NAME"-}" ;;
      *'NetworkSettings.Ports'*) printf '18080\n' ;;
      *) exit 1 ;;
    esac
    exit 0
    ;;
  network)
    shift
    [ "${1:-}" = inspect ] || exit 0
    shift
    [ "${1:-}" = -f ] || exit 1
    format="$2"
    name="$3"
    grep -Fq "$name" "$DOCKER_NETWORK_FILE" 2>/dev/null || exit 1
    case "$format" in
      '{{.Id}}') cut -f2 "$DOCKER_NETWORK_FILE" ;;
      *'org.loopforge.resource'*) printf 'docker-simulation\n' ;;
      *'org.loopforge.project'*) printf '%s\n' "$HARNESS_PROJECT_NAME" ;;
      *'org.loopforge.set-id'*) printf '%s\n' "$HARNESS_SET_ID" ;;
      *'org.loopforge.network'*) printf 'harness\n' ;;
      *) exit 1 ;;
    esac
    exit 0
    ;;
  cp)
    exit 0
    ;;
esac

exit 0
SH
chmod +x "$fake_bin/docker"

cat >"$fake_bin/docker-compose" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
exec "$FAKE_DOCKER_BIN/docker" compose "$@"
SH
chmod +x "$fake_bin/docker-compose"

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

common_env=(
  PATH="$fake_bin:$PATH"
  DOCKER_CALLS_LOG="$calls"
  DOCKER_CONTAINERS_FILE="$containers"
  DOCKER_NETWORK_FILE="$network"
  FAKE_DOCKER_BIN="$fake_bin"
  HARNESS_FORCE_COMPOSE_V1_FOR_TESTS=1
  REPO_ROOT="$repo_root"
)
simulate=("$repo_root/simulation/docker/simulate.sh" --env "$tmp_dir/harness.env")

env "${common_env[@]}" "${simulate[@]}" init-run >/dev/null
[ ! -e "$set_dir/runtime" ] || {
  printf 'init-run must not create durable Docker runtime state\n' >&2
  exit 1
}

env "${common_env[@]}" "${simulate[@]}" create >"$tmp_dir/create.out"
grep -Fq 'create: ok state=created resources=stopped' "$tmp_dir/create.out"
[ -f "$set_dir/docker-set.env" ]
[ -d "$set_dir/runtime/product-homes/gerrit" ]
[ -f "$network" ]
grep -Eq 'compose .* up --no-start --no-build$' "$calls"
grep -Fq 'inspect -f {{.Driver}}' "$calls"
if grep -Fq 'GraphDriver' "$calls"; then
  printf 'Docker identity publication must not query removed GraphDriver fields\n' >&2
  exit 1
fi
set +e
env "${common_env[@]}" DOCKER_DRIVER_INSPECT_FAIL=1 bash -c \
  '. "$1/simulation/lib/common.sh"; . "$1/simulation/docker/lib/compose.sh"; docker_container_storage_driver_by_name "$2"' \
  bash "$repo_root" "$project_name-gerrit-target" \
  >"$tmp_dir/driver-unavailable.out" 2>&1
rc=$?
set -e
[ "$rc" -ne 0 ]
grep -Fq 'Could not inspect Docker storage driver for selected container' \
  "$tmp_dir/driver-unavailable.out"
awk -F '\t' '$3 != "false" { exit 1 }' "$containers"
record_before="$(sha256sum "$set_dir/docker-set.env")"
containers_before="$(cut -f1,2,4,5 "$containers")"

env "${common_env[@]}" "${simulate[@]}" create >"$tmp_dir/create-existing.out"
grep -Fq 'create: ok state=existing resources=stopped' "$tmp_dir/create-existing.out"
[ "$record_before" = "$(sha256sum "$set_dir/docker-set.env")" ]

ordinary_lifecycle_line=$(( $(wc -l <"$calls") + 1 ))
env "${common_env[@]}" "${simulate[@]}" start >"$tmp_dir/start.out"
grep -Fq 'start: ok state=started durable=baseline resources=running' "$tmp_dir/start.out"
env "${common_env[@]}" "${simulate[@]}" start >"$tmp_dir/start-repeat.out"
grep -Fq 'start: ok state=already-running durable=baseline resources=running' "$tmp_dir/start-repeat.out"

set +e
env "${common_env[@]}" "${simulate[@]}" create >"$tmp_dir/create-running.out" 2>&1
rc=$?
set -e
[ "$rc" -ne 0 ]
grep -Fq 'requires the exact selected set to be stopped' "$tmp_dir/create-running.out"

env "${common_env[@]}" "${simulate[@]}" stop >"$tmp_dir/stop.out"
grep -Fq 'stop: ok state=stopped durable=baseline reset-gate=normal' "$tmp_dir/stop.out"
env "${common_env[@]}" "${simulate[@]}" stop >"$tmp_dir/stop-repeat.out"
grep -Fq 'stop: ok state=already-stopped durable=baseline reset-gate=normal' "$tmp_dir/stop-repeat.out"
[ "$containers_before" = "$(cut -f1,2,4,5 "$containers")" ]
tail -n +"$ordinary_lifecycle_line" "$calls" >"$tmp_dir/ordinary-lifecycle-calls"
if grep -Eq 'compose .* (down|up)' "$tmp_dir/ordinary-lifecycle-calls"; then
  printf 'ordinary Docker set lifecycle must not call Compose up or down\n' >&2
  exit 1
fi

cp "$set_dir/active-run.env" "$tmp_dir/active-run.env"
sed -e 's/^state=active$/state=restored-pending-clean/' \
  -e 's/^restore_evidence_sha256=none$/restore_evidence_sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/' \
  "$tmp_dir/active-run.env" >"$set_dir/active-run.env"
for command in create start; do
  set +e
  env "${common_env[@]}" "${simulate[@]}" "$command" >"$tmp_dir/$command-restored.out" 2>&1
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || {
    printf '%s must reject restored-pending-clean state\n' "$command" >&2
    exit 1
  }
  grep -Fq 'blocks reset gate: restored-pending-clean' "$tmp_dir/$command-restored.out"
done
mv "$tmp_dir/active-run.env" "$set_dir/active-run.env"

# Publish one exact completed checkpoint so restart must use runtime-only
# product service operations before target-access refresh.
. "$repo_root/simulation/lib/common.sh"
. "$repo_root/simulation/lib/state.sh"
workflow="$run_dir/host/state/workflow-state.env"
checkpoint_dir="$run_dir/host/state/checkpoints"
evidence="$tmp_dir/checkpoint-evidence"
record="$checkpoint_dir/prepare-artifacts-gerrit.env"
printf 'pass\n' >"$evidence"
workflow_state_publish_activity "$workflow" mutating prepare-artifacts-gerrit
write_immutable_checkpoint_record "$record" docker "$set_id" "$run_id" none \
  "$(strict_record_value "$workflow" source_inputs_fingerprint)" \
  "$(strict_record_value "$workflow" effective_inputs_fingerprint)" \
  prepare-artifacts-gerrit none mutating complete "$evidence" \
  2026-07-18T00:00:00Z 2026-07-18T00:00:01Z
workflow_state_publish_checkpoint "$workflow" "$record" complete

start_line=$(( $(wc -l <"$calls") + 1 ))
env "${common_env[@]}" "${simulate[@]}" start >"$tmp_dir/start-exact.out"
grep -Fq 'start: ok state=started durable=exact-bound resources=running' "$tmp_dir/start-exact.out"
tail -n +"$start_line" "$calls" >"$tmp_dir/exact-start-calls"
grep -Fq 'site=/srv/gerrit' "$tmp_dir/exact-start-calls"
grep -Fq 'home=/var/lib/jenkins' "$tmp_dir/exact-start-calls"
if grep -Eq '(gerrit|jenkins-controller)-setup\.sh (install|configure)|test -z .*install -d' "$tmp_dir/exact-start-calls"; then
  printf 'exact-bound start must not replay setup helpers\n' >&2
  exit 1
fi

stop_line=$(( $(wc -l <"$calls") + 1 ))
env "${common_env[@]}" "${simulate[@]}" stop >"$tmp_dir/stop-exact.out"
tail -n +"$stop_line" "$calls" >"$tmp_dir/exact-stop-calls"
jenkins_stop_line="$(grep -n 'pidfile=/var/lib/jenkins/run/jenkins.pid' "$tmp_dir/exact-stop-calls" | head -1 | cut -d: -f1)"
gerrit_stop_line="$(grep -n 'pidfile=$site/logs/gerrit.pid' "$tmp_dir/exact-stop-calls" | head -1 | cut -d: -f1)"
compose_stop_line="$(grep -n 'compose .* stop$' "$tmp_dir/exact-stop-calls" | head -1 | cut -d: -f1)"
[ -n "$jenkins_stop_line" ] && [ -n "$gerrit_stop_line" ] && [ -n "$compose_stop_line" ]
[ "$jenkins_stop_line" -lt "$compose_stop_line" ]
[ "$gerrit_stop_line" -lt "$compose_stop_line" ]
[ "$containers_before" = "$(cut -f1,2,4,5 "$containers")" ]

awk -F '\t' 'BEGIN { OFS="\t" } /gerrit-target/ { $2="recreated-container-id" } { print }' \
  "$containers" >"$containers.tmp"
mv "$containers.tmp" "$containers"
set +e
env "${common_env[@]}" "${simulate[@]}" start >"$tmp_dir/start-drift.out" 2>&1
rc=$?
set -e
[ "$rc" -ne 0 ]
grep -Fq 'container, image, network, or storage identity drifted' "$tmp_dir/start-drift.out"
