#!/usr/bin/env bash

__docker_set_record_is_strict() {
  strict_record_keys "${1:?Docker set record required}" schema_version backend \
    set_id resource_namespace compose_fingerprint resource_fingerprint
}

__docker_set_presence() {
  local service name count network_present
  count=0
  for service in "${services[@]}"; do
    name="$(container_name_for_service "$service")"
    docker_container_name_exists "$name" && count=$((count + 1))
  done
  network_present=0
  docker_network_exists "$(docker_network_name)" && network_present=1
  if [ "$count" -eq 0 ] && [ "$network_present" -eq 0 ]; then
    printf 'absent\n'
  elif [ "$count" -eq "${#services[@]}" ] && [ "$network_present" -eq 1 ]; then
    printf 'present\n'
  else
    printf 'partial\n'
  fi
}

__docker_set_owned_resource_snapshot() {
  local service name network value label expected compose_fingerprint
  local network_id container_id image_id storage_driver
  compose_fingerprint="$(compose_definition_fingerprint)" || return $?
  sha256_fingerprint_is_valid "$compose_fingerprint" ||
    die "Could not fingerprint the selected Docker Compose definition"
  printf 'compose=%s\n' "$compose_fingerprint"
  network="$(docker_network_name)"
  network_id="$(docker_network_inspect_value "$network" '{{.Id}}')" || return $?
  [ -n "$network_id" ] || die "Could not resolve selected Docker network identity"
  printf 'network_id=%s\n' "$network_id"
  for value in \
    "resource:org.loopforge.resource:docker-simulation" \
    "project:org.loopforge.project:$HARNESS_PROJECT_NAME" \
    "set_id:org.loopforge.set-id:$HARNESS_SET_ID" \
    "network:org.loopforge.network:harness"; do
    IFS=: read -r _ label expected <<<"$value"
    [ "$(docker_network_label "$network" "$label")" = "$expected" ] ||
      die "Docker network ownership label does not match selected set: $network ($label)"
  done
  for service in "${services[@]}"; do
    name="$(container_name_for_service "$service")"
    container_id="$(docker_container_id_by_name "$name")" || return $?
    image_id="$(docker_container_image_id_by_name "$name")" || return $?
    storage_driver="$(docker_container_storage_driver_by_name "$name")" || return $?
    [ -n "$container_id" ] && [ -n "$image_id" ] ||
      die "Could not resolve Docker identity for selected container: $name"
    # Docker binds the writable layer to the immutable container ID.
    printf 'container=%s id=%s image=%s writable_owner=%s storage_driver=%s\n' \
      "$service" "$container_id" "$image_id" "$container_id" "$storage_driver"
    for value in \
      "org.loopforge.resource:docker-simulation" \
      "org.loopforge.project:$HARNESS_PROJECT_NAME" \
      "org.loopforge.set-id:$HARNESS_SET_ID" \
      "org.loopforge.service:$service"; do
      label="${value%%:*}"
      expected="${value#*:}"
      [ "$(docker_container_label_by_name "$name" "$label")" = "$expected" ] ||
        die "Docker container ownership label does not match selected set: $name ($label)"
    done
  done
}

__docker_set_resource_fingerprint() {
  __docker_set_owned_resource_snapshot | sha256sum | awk '{print $1}'
}

__docker_set_write_record() {
  local compose_fingerprint resource_fingerprint
  compose_fingerprint="$(compose_definition_fingerprint)" || return $?
  resource_fingerprint="$(__docker_set_resource_fingerprint)" || return $?
  atomic_write_record "$HARNESS_DOCKER_SET_RECORD" "$LF_MODE_PUBLIC_FILE" \
    "schema_version=1" \
    "backend=docker" \
    "set_id=$HARNESS_SET_ID" \
    "resource_namespace=$HARNESS_PROJECT_NAME" \
    "compose_fingerprint=$compose_fingerprint" \
    "resource_fingerprint=$resource_fingerprint"
}

__docker_set_verify_record() {
  local expected actual
  __docker_set_record_is_strict "$HARNESS_DOCKER_SET_RECORD" ||
    die "Docker simulation-set metadata is missing, malformed, or has unexpected fields"
  [ "$(strict_record_value "$HARNESS_DOCKER_SET_RECORD" schema_version)" = 1 ] ||
    die "Docker simulation-set metadata schema is unsupported"
  [ "$(strict_record_value "$HARNESS_DOCKER_SET_RECORD" backend)" = docker ] ||
    die "Docker simulation-set metadata backend does not match"
  [ "$(strict_record_value "$HARNESS_DOCKER_SET_RECORD" set_id)" = "$HARNESS_SET_ID" ] ||
    die "Docker simulation-set metadata set ID does not match"
  [ "$(strict_record_value "$HARNESS_DOCKER_SET_RECORD" resource_namespace)" = "$HARNESS_PROJECT_NAME" ] ||
    die "Docker simulation-set metadata namespace does not match"
  expected="$(strict_record_value "$HARNESS_DOCKER_SET_RECORD" compose_fingerprint)"
  actual="$(compose_definition_fingerprint)" || return $?
  [ "$actual" = "$expected" ] || die "Docker Compose definition drifted from selected set metadata"
  expected="$(strict_record_value "$HARNESS_DOCKER_SET_RECORD" resource_fingerprint)"
  actual="$(__docker_set_resource_fingerprint)" || return $?
  [ "$actual" = "$expected" ] ||
    die "Docker selected container, image, network, or storage identity drifted"
}

__docker_set_require_runtime_dirs() {
  local path
  for path in \
    "$HARNESS_STATE_DIR" \
    "$HARNESS_PRODUCT_HOME_DIR/gerrit" \
    "$HARNESS_PRODUCT_HOME_DIR/jenkins-controller" \
    "$HARNESS_PRODUCT_HOME_DIR/jenkins-agent" \
    "$HARNESS_STAGING_DIR/gerrit" \
    "$HARNESS_STAGING_DIR/jenkins-controller" \
    "$HARNESS_STAGING_DIR/jenkins-agent" \
    "$HARNESS_LDAP_DATA_DIR" \
    "$HARNESS_LDAP_CONFIG_DIR" \
    "$HARNESS_SHARED_JENKINS_STORAGE_DIR"; do
    [ -d "$path" ] || die "Docker simulation-set runtime path is missing: $path"
  done
}

__docker_set_initialize_runtime_dirs() {
  [ ! -e "$HARNESS_SET_RUNTIME_DIR" ] ||
    die "Docker simulation-set runtime state exists without exact owned resources"
  mkdir -p \
    "$HARNESS_STATE_DIR" \
    "$HARNESS_PRODUCT_HOME_DIR/gerrit" \
    "$HARNESS_PRODUCT_HOME_DIR/jenkins-controller" \
    "$HARNESS_PRODUCT_HOME_DIR/jenkins-agent" \
    "$HARNESS_STAGING_DIR/gerrit" \
    "$HARNESS_STAGING_DIR/jenkins-controller" \
    "$HARNESS_STAGING_DIR/jenkins-agent" \
    "$HARNESS_LDAP_DATA_DIR" \
    "$HARNESS_LDAP_CONFIG_DIR" \
    "$HARNESS_SHARED_JENKINS_STORAGE_DIR"
  : >"$HARNESS_PRODUCT_HOME_DIR/.runtime-identity-pending"
  chmod "$LF_MODE_PUBLIC_FILE" "$HARNESS_PRODUCT_HOME_DIR/.runtime-identity-pending"
}

__docker_set_classification() {
  simulation_classify_claimed_state \
    "$HARNESS_ACTIVE_RUN_FILE" "$HARNESS_RUN_MARKER" \
    "$HARNESS_WORKFLOW_STATE_FILE" docker "$HARNESS_SET_ID" "$HARNESS_RUN_ID" \
    "$HARNESS_PROJECT_NAME" exact "$HARNESS_CHECKPOINT_RECORD_DIR"
}

__docker_set_reset_gate() {
  case "$(strict_record_value "$HARNESS_ACTIVE_RUN_FILE" state)" in
    active) printf 'normal\n' ;;
    restored-pending-clean) printf 'restored-pending-clean\n' ;;
    *) printf 'conflicting\n' ;;
  esac
}

__docker_set_require_normal_reset_gate() {
  local gate
  gate="$(__docker_set_reset_gate)"
  [ "$gate" = normal ] ||
    die "Docker lifecycle command blocks reset gate: $gate"
}

docker_set_create() {
  local log rc evidence presence power classification
  bootstrap_harness_env
  docker_set_require_runtime || return $?
  require_command docker
  detect_compose
  require_baseline_label
  [ -f "$compose_file" ] || die "Missing Compose file: $compose_file"
  [ -f "$docker_dir/ldap/50-harness-seed.ldif" ] || die "Missing LDAP seed LDIF"
  [ -f "$docker_dir/target/Dockerfile" ] || die "Missing harness target Dockerfile"
  [ -f "$docker_dir/scripts/harness-sleep.sh" ] || die "Missing harness container entrypoint"
  __docker_set_require_normal_reset_gate
  presence="$(__docker_set_presence)"
  if [ "$presence" = present ] && [ -f "$HARNESS_DOCKER_SET_RECORD" ]; then
    __docker_set_require_runtime_dirs
    __docker_set_verify_record
    power="$(selected_container_power_state)"
    [ "$power" = stopped ] ||
      die "Docker create requires the exact selected set to be stopped; current power state is $power"
    classification="$(__docker_set_classification)"
    [ "$classification" = baseline ] ||
      die "Docker create cannot adopt durable state classified as $classification"
    print_command_summary create "" "ok state=existing resources=stopped"
    return 0
  fi
  [ "$presence" = absent ] && [ ! -e "$HARNESS_DOCKER_SET_RECORD" ] ||
    die "Docker selected set is partial, unowned, or missing exact set metadata"
  __docker_set_initialize_runtime_dirs
  log="$(bounded_log_path create)"
  if compose build >"$log" 2>&1; then
    rc=0
  else
    rc=$?
  fi
  if [ "$rc" -ne 0 ]; then
    evidence="$(write_evidence create harness fail "simulate.sh create" "$log" "Compose image build failed")"
    print_command_failure create "" failed "$log" "$evidence"
    return "$rc"
  fi
  if ! compose up --no-start --no-build >>"$log" 2>&1; then
    evidence="$(write_evidence create harness fail "simulate.sh create" "$log" "Compose resource creation failed")"
    print_command_failure create "" failed "$log" "$evidence"
    return 1
  fi
  if ! compose start >>"$log" 2>&1; then
    evidence="$(write_evidence create harness fail "simulate.sh create" "$log" "Temporary prerequisite startup during create failed")"
    print_command_failure create "" failed "$log" "$evidence"
    return 1
  fi
  if ! __docker_set_initialize_or_validate_product_homes "$log"; then
    compose stop >>"$log" 2>&1 || true
    evidence="$(write_evidence create harness fail "simulate.sh create" "$log" "Clean product-home identity initialization failed")"
    print_command_failure create "" failed "$log" "$evidence"
    return 1
  fi
  if ! compose stop >>"$log" 2>&1; then
    evidence="$(write_evidence create harness fail "simulate.sh create" "$log" "Compose stop after clean prerequisite initialization failed")"
    print_command_failure create "" failed "$log" "$evidence"
    return 1
  fi
  [ "$(selected_container_power_state)" = stopped ] ||
    die "Docker create did not leave every selected container stopped"
  __docker_set_write_record || {
    evidence="$(write_evidence create harness fail "simulate.sh create" "$log" "Docker simulation-set identity publication failed")"
    print_command_failure create "" failed "$log" "$evidence"
    return 1
  }
  validate_selected_container_mounts
  evidence="$(write_evidence create harness pass "simulate.sh create" "$log" "Built and created the exact retained Docker simulation set and left it stopped")"
  print_command_summary create "" "ok state=created resources=stopped"
}

__docker_set_initialize_or_validate_product_homes() {
  local log marker pending spec service account group path
  local expected expected_uid expected_gid actual
  log="${1:?log required}"
  marker="$HARNESS_PRODUCT_HOME_DIR/.runtime-identity-pending"
  pending=0
  [ ! -f "$marker" ] || pending=1

  for spec in \
    'gerrit-target:gerrit:gerrit:/srv/gerrit:61010:61010' \
    'jenkins-controller-target:jenkins:jenkins:/var/lib/jenkins:61020:61020' \
    'jenkins-agent-target:jenkins-agent:jenkins-agent:/var/lib/jenkins-agent:61030:61030'; do
    IFS=: read -r service account group path expected_uid expected_gid <<<"$spec"
    expected="$expected_uid:$expected_gid"
    if [ "$pending" -eq 1 ]; then
      compose exec -T "$service" sh -c \
        'test -d "$1" && test -z "$(find "$1" -mindepth 1 -maxdepth 1 -print -quit)" && install -d -m 0755 -o "$2" -g "$3" "$1"' \
        sh "$path" "$account" "$group" >>"$log" 2>&1 || {
          printf 'ERROR: Fresh Docker product home initialization failed for %s:%s\n' "$service" "$path" >>"$log"
          return 1
        }
    else
      actual="$(compose exec -T "$service" stat -c '%u:%g' "$path" 2>>"$log" | tr -d '\r')" || {
        printf 'ERROR: Could not inspect Docker product home ownership for %s:%s\n' "$service" "$path" >>"$log"
        return 1
      }
      if [ "$actual" != "$expected" ]; then
        printf 'ERROR: Docker product home ownership mismatch for %s:%s expected=%s actual=%s; run explicit cleanup and use a fresh run\n' \
          "$service" "$path" "$expected" "$actual" >>"$log"
        return 1
      fi
    fi
  done

  if [ "$pending" -eq 1 ]; then
    rm -f -- "$marker"
    printf 'product-home-runtime-identities=initialized\n' >>"$log"
  else
    printf 'product-home-runtime-identities=validated\n' >>"$log"
  fi
}

__docker_set_runtime_start_gerrit() {
  local log
  log="${1:?log required}"
  compose exec -T -u root gerrit-target sh -c '
    set -eu
    site=/srv/gerrit
    pidfile=$site/logs/gerrit.pid
    test -x "$site/bin/gerrit.sh"
    test -f "$site/etc/gerrit.config"
    if test -s "$pidfile"; then
      pid=$(cat "$pidfile")
      kill -0 "$pid" 2>/dev/null && exit 0
      echo "stale Gerrit PID file blocks runtime-only start" >&2
      exit 41
    fi
    runuser -u gerrit -- sh -c "setsid -f $site/bin/gerrit.sh run </dev/null >>$site/logs/gerrit.log 2>&1"
    deadline=180
    while test "$deadline" -gt 0; do
      pid=$(ps -eo pid=,comm=,args= | awk -v site="$site" '\''$2 == "java" && index($0, site) { print $1; exit }'\'')
      if test -n "$pid" && curl -fsS http://127.0.0.1:8080/ >/dev/null 2>&1; then
        printf "%s\n" "$pid" >"$pidfile"
        chown gerrit:gerrit "$pidfile"
        exit 0
      fi
      sleep 3
      deadline=$((deadline - 3))
    done
    echo "Gerrit runtime-only start did not reach readiness" >&2
    exit 42
  ' >>"$log" 2>&1
}

__docker_set_runtime_start_jenkins() {
  local log
  log="${1:?log required}"
  compose exec -T -u root jenkins-controller-target sh -c '
    set -eu
    home=/var/lib/jenkins
    pidfile=$home/run/jenkins.pid
    test -f "$home/war/jenkins.war"
    test -f "$home/jcasc/jenkins.yaml"
    test -d "$home/run"
    test -d "$home/logs"
    test -d "$home/war-cache"
    runuser -u jenkins -- test -w "$home/run"
    runuser -u jenkins -- test -w "$home/logs"
    runuser -u jenkins -- test -w "$home/war-cache"
    if test -s "$pidfile"; then
      pid=$(cat "$pidfile")
      kill -0 "$pid" 2>/dev/null && exit 0
      echo "stale Jenkins PID file blocks runtime-only start" >&2
      exit 43
    fi
    runuser -u jenkins -- sh -c "JENKINS_HOME=$home CASC_JENKINS_CONFIG=$home/jcasc/jenkins.yaml nohup java -Djava.awt.headless=true -Djenkins.install.runSetupWizard=false -jar $home/war/jenkins.war --httpPort=8080 --webroot=$home/war-cache >$home/logs/jenkins-controller.log 2>&1 & echo \$! >$pidfile"
    chown jenkins:jenkins "$pidfile"
    pid=$(cat "$pidfile")
    deadline=240
    while test "$deadline" -gt 0; do
      kill -0 "$pid" 2>/dev/null || exit 44
      curl -fsSI http://127.0.0.1:8080/login 2>/dev/null | grep -Fq "X-Jenkins: 2.555.3" && exit 0
      sleep 3
      deadline=$((deadline - 3))
    done
    echo "Jenkins runtime-only start did not reach readiness" >&2
    exit 45
  ' >>"$log" 2>&1
}

__docker_set_runtime_stop_gerrit() {
  local log
  log="${1:?log required}"
  compose exec -T -u root gerrit-target sh -c '
    set -eu
    site=/srv/gerrit
    pidfile=$site/logs/gerrit.pid
    test -s "$pidfile" || exit 0
    pid=$(cat "$pidfile")
    if ! kill -0 "$pid" 2>/dev/null; then
      echo "stale Gerrit PID file blocks graceful stop" >&2
      exit 46
    fi
    runuser -u gerrit -- "$site/bin/gerrit.sh" stop
    deadline=60
    while test "$deadline" -gt 0; do
      kill -0 "$pid" 2>/dev/null || { rm -f "$pidfile"; exit 0; }
      sleep 2
      deadline=$((deadline - 2))
    done
    echo "Gerrit did not stop gracefully" >&2
    exit 47
  ' >>"$log" 2>&1
}

__docker_set_runtime_stop_jenkins() {
  local log
  log="${1:?log required}"
  compose exec -T -u root jenkins-controller-target sh -c '
    set -eu
    pidfile=/var/lib/jenkins/run/jenkins.pid
    test -s "$pidfile" || exit 0
    pid=$(cat "$pidfile")
    if ! kill -0 "$pid" 2>/dev/null; then
      echo "stale Jenkins PID file blocks graceful stop" >&2
      exit 48
    fi
    kill -TERM "$pid"
    deadline=120
    while test "$deadline" -gt 0; do
      kill -0 "$pid" 2>/dev/null || { rm -f "$pidfile"; exit 0; }
      sleep 2
      deadline=$((deadline - 2))
    done
    echo "Jenkins did not stop gracefully" >&2
    exit 49
  ' >>"$log" 2>&1
}

__docker_set_require_configured_runtimes() {
  local log
  log="${1:?log required}"
  compose exec -T -u root gerrit-target sh -c '
    test -s /srv/gerrit/logs/gerrit.pid
    pid=$(cat /srv/gerrit/logs/gerrit.pid)
    kill -0 "$pid" 2>/dev/null
  ' >>"$log" 2>&1 || return 1
  compose exec -T -u root jenkins-controller-target sh -c '
    test -s /var/lib/jenkins/run/jenkins.pid
    pid=$(cat /var/lib/jenkins/run/jenkins.pid)
    kill -0 "$pid" 2>/dev/null
  ' >>"$log" 2>&1
}

__docker_set_require_baseline_runtimes_absent() {
  local log
  log="${1:?log required}"
  compose exec -T -u root gerrit-target sh -c '
    test ! -e /srv/gerrit/logs/gerrit.pid
  ' >>"$log" 2>&1 || return 1
  compose exec -T -u root jenkins-controller-target sh -c '
    test ! -e /var/lib/jenkins/run/jenkins.pid
  ' >>"$log" 2>&1
}

__docker_set_start_access_and_inputs() {
  local log
  log="${1:?log required}"
  if ! __docker_set_initialize_or_validate_product_homes "$log"; then
    return 1
  fi
  check_ubuntu_service_baseline bundle-factory bundle-factory
  check_ubuntu_service_baseline gerrit-target gerrit
  check_ubuntu_service_baseline jenkins-controller-target jenkins-controller
  check_ubuntu_service_baseline jenkins-agent-target jenkins-agent
  stage_role_helpers_for_all_services "$log" || return 1
  stage_target_ssh_authorized_keys "$log" || return 1
  refresh_target_ssh_known_hosts "$log" || return 1
  docker_publish_or_verify_effective_inputs >>"$log" 2>&1 || return 1
  require_running_service ldap
}

docker_set_start() {
  local log rc evidence presence power classification summary_state
  bootstrap_harness_env
  docker_set_require_runtime || return $?
  require_command docker
  require_command python3
  require_command sha256sum
  require_command tar
  require_command awk
  require_command ssh-keyscan
  detect_compose
  require_baseline_label
  [ -f "$compose_file" ] || die "Missing Compose file: $compose_file"
  [ -f "$docker_dir/ldap/50-harness-seed.ldif" ] || die "Missing LDAP seed LDIF"
  [ -f "$docker_dir/target/Dockerfile" ] || die "Missing harness target Dockerfile"
  [ -f "$docker_dir/scripts/harness-sleep.sh" ] || die "Missing harness container entrypoint"
  __docker_set_require_normal_reset_gate
  presence="$(__docker_set_presence)"
  [ "$presence" = present ] ||
    die "Docker start requires the complete selected retained set; resource state is $presence"
  __docker_set_require_runtime_dirs
  __docker_set_verify_record
  validate_selected_container_mounts
  classification="$(__docker_set_classification)"
  case "$classification" in
    baseline|exact-bound) ;;
    *) die "Docker start blocks durable state classified as $classification" ;;
  esac
  power="$(selected_container_power_state)"
  case "$power" in
    stopped) summary_state=started ;;
    running) summary_state=already-running ;;
    *) die "Docker start requires uniformly stopped or running selected containers; current power state is $power" ;;
  esac
  log="$(bounded_log_path start)"
  : >"$log"
  if [ "$power" = stopped ] && compose start >>"$log" 2>&1; then
    rc=0
  elif [ "$power" = running ]; then
    rc=0
  else
    rc=$?
  fi
  if [ "$rc" -ne 0 ]; then
    evidence="$(write_evidence start harness fail "simulate.sh start" "$log" "Compose startup failed")"
    print_command_failure start "" failed "$log" "$evidence"
    return "$rc"
  fi
  __docker_set_verify_record
  validate_selected_container_mounts
  if [ "$classification" = exact-bound ] && [ "$power" = stopped ]; then
    if ! __docker_set_runtime_start_gerrit "$log" ||
      ! __docker_set_runtime_start_jenkins "$log"; then
      evidence="$(write_evidence start harness fail "simulate.sh start" "$log" "Configured Docker product runtime-only startup failed")"
      print_command_failure start "" failed "$log" "$evidence"
      return 1
    fi
  elif [ "$classification" = exact-bound ]; then
    if ! __docker_set_require_configured_runtimes "$log"; then
      evidence="$(write_evidence start harness fail "simulate.sh start" "$log" "Configured Docker runtimes are not ready in an already-running set")"
      print_command_failure start "" failed "$log" "$evidence"
      return 1
    fi
  elif ! __docker_set_require_baseline_runtimes_absent "$log"; then
    evidence="$(write_evidence start harness fail "simulate.sh start" "$log" "Unexpected configured product runtime exists in baseline state")"
    print_command_failure start "" failed "$log" "$evidence"
    return 1
  fi
  if ! __docker_set_start_access_and_inputs "$log"; then
    evidence="$(write_evidence start harness fail "simulate.sh start" "$log" "Docker target access or stable effective input readiness failed")"
    print_command_failure start "" failed "$log" "$evidence"
    return 1
  fi
  evidence="$(write_evidence start harness pass "simulate.sh start" "$log" "Started or verified the exact retained Docker set without setup replay")"
  print_command_summary start "" "ok state=$summary_state durable=$classification resources=running target-access=ready inputs=ready"
}

__docker_set_destroy_container_targets() {
  local service
  for service in "${services[@]}"; do
    docker ps -a -q \
      --filter "label=org.loopforge.resource=docker-simulation" \
      --filter "label=org.loopforge.project=$HARNESS_PROJECT_NAME" \
      --filter "label=org.loopforge.set-id=$HARNESS_SET_ID" \
      --filter "label=org.loopforge.service=$service" 2>/dev/null || true
  done | awk 'NF && !seen[$0]++'
}

__docker_set_destroy_network_targets() {
  (docker network ls -q \
    --filter "label=org.loopforge.resource=docker-simulation" \
    --filter "label=org.loopforge.project=$HARNESS_PROJECT_NAME" \
    --filter "label=org.loopforge.set-id=$HARNESS_SET_ID" \
    --filter "label=org.loopforge.network=harness" 2>/dev/null || true) |
    awk 'NF && !seen[$0]++'
}

__docker_set_destroy_image_targets() {
  local service
  for service in "${services[@]}"; do
    docker images -q \
      --filter "label=org.loopforge.resource=docker-simulation" \
      --filter "label=org.loopforge.project=$HARNESS_PROJECT_NAME" \
      --filter "label=org.loopforge.set-id=$HARNESS_SET_ID" \
      --filter "label=org.loopforge.service=$service" 2>/dev/null || true
  done | awk 'NF && !seen[$0]++'
}

docker_set_destroy() {
  local log rc evidence target container_count network_count image_count
  bootstrap_harness_env
  require_command docker
  log="$(bounded_log_path destroy)"
  rc=0
  container_count=0
  network_count=0
  image_count=0
  : >"$log"
  while IFS= read -r target; do
    [ -n "$target" ] || continue
    if docker rm -f "$target" >>"$log" 2>&1; then
      container_count=$((container_count + 1))
    else
      rc=$?
      printf 'container_remove_failed target=%s\n' "$target" >>"$log"
      break
    fi
  done <<EOF
$(__docker_set_destroy_container_targets)
EOF
  if [ "$rc" -eq 0 ]; then
    while IFS= read -r target; do
      [ -n "$target" ] || continue
      if docker network rm "$target" >>"$log" 2>&1; then
        network_count=$((network_count + 1))
      else
        rc=$?
        printf 'network_remove_failed target=%s\n' "$target" >>"$log"
        break
      fi
    done <<EOF
$(__docker_set_destroy_network_targets)
EOF
  fi
  if [ "$rc" -eq 0 ]; then
    while IFS= read -r target; do
      [ -n "$target" ] || continue
      if docker image rm "$target" >>"$log" 2>&1; then
        image_count=$((image_count + 1))
      else
        rc=$?
        printf 'image_remove_failed target=%s\n' "$target" >>"$log"
        break
      fi
    done <<EOF
$(__docker_set_destroy_image_targets)
EOF
  fi
  if [ "$rc" -ne 0 ]; then
    evidence="$(write_evidence destroy harness fail "simulate.sh destroy" "$log" "Docker selected resource destruction failed")"
    print_command_failure destroy "" failed "$log" "$evidence"
    return "$rc"
  fi
  evidence="$(write_evidence destroy harness pass "simulate.sh destroy" "$log" "Removed selected Docker simulation containers, harness network, and project-built images; base images and generated state were not removed")"
  print_command_summary destroy "" "ok containers-removed=$container_count networks-removed=$network_count images-removed=$image_count"
}

docker_set_status() {
  local gerrit_port jenkins_port presence power classification reset_gate
  bootstrap_harness_env
  docker_set_require_runtime || return $?
  require_command docker
  detect_compose
  presence="$(__docker_set_presence)"
  [ "$presence" = present ] ||
    die "Docker status found selected resource state: $presence"
  __docker_set_require_runtime_dirs
  __docker_set_verify_record
  power="$(selected_container_power_state)"
  case "$power" in running|stopped) ;; *) die "Docker status found conflicting power state: $power" ;; esac
  classification="$(__docker_set_classification)"
  [ "$classification" != conflicting ] || die "Docker status found conflicting durable state"
  reset_gate="$(__docker_set_reset_gate)"

  printf 'status: %s\n\n' "$power"
  printf 'Run\n'
  printf '  %-13s %s\n' 'Run ID' "$HARNESS_RUN_ID"
  printf '  %-13s %s\n' 'Set ID' "$HARNESS_SET_ID"
  printf '  %-13s %s\n' 'Project' "$HARNESS_PROJECT_NAME"
  printf '  %-13s %s\n' 'Durable' "$classification"
  printf '  %-13s %s\n' 'Reset gate' "$reset_gate"
  [ "$power" = running ] || return 0
  gerrit_port="$(running_loopback_port_for_service_port gerrit-target 8080/tcp)"
  jenkins_port="$(running_loopback_port_for_service_port jenkins-controller-target 8080/tcp)"
  printf '  %-13s http://127.0.0.1:%s/\n' 'Gerrit URL' "$gerrit_port"
  printf '  %-13s http://127.0.0.1:%s/login\n' 'Jenkins URL' "$jenkins_port"
  printf '\n'
  printf 'Login accounts\n'
  printf '  %-18s  %-14s  %-20s  %-40s\n' 'System' 'Username' 'Password' 'Purpose'
  printf '  %-18s  %-14s  %-20s  %-40s\n' '------------------' '--------------' '--------------------' '----------------------------------------'
  printf '  %-18s  %-14s  %-20s  %-40s\n' 'Gerrit' 'gerrit-admin' 'admin-password' 'Gerrit admin user'
  printf '  %-18s  %-14s  %-20s  %-40s\n' 'Jenkins' 'jenkins-admin' 'admin-password' 'Jenkins admin user'
  printf '  %-18s  %-14s  %-20s  %-40s\n' 'Gerrit' 'test-user' 'test-password' 'Test/change workflow user'
  printf '  %-18s  %-14s  %-20s  %-40s\n' '------------------' '--------------' '--------------------' '----------------------------------------'
}

docker_set_audit() {
  bootstrap_harness_env
  docker_set_require_runtime || return $?
  require_command docker
  detect_compose
  docker_set_verify_selected_mounts
  print_command_summary audit-state "" "ok"
}

docker_set_stop() {
  local log rc evidence presence power classification reset_gate
  bootstrap_harness_env
  docker_set_require_runtime || return $?
  require_command docker
  detect_compose
  presence="$(__docker_set_presence)"
  [ "$presence" = present ] ||
    die "Docker stop requires the complete selected retained set; resource state is $presence"
  __docker_set_require_runtime_dirs
  __docker_set_verify_record
  classification="$(__docker_set_classification)"
  [ "$classification" != conflicting ] ||
    die "Docker stop blocks conflicting selected durable state"
  reset_gate="$(__docker_set_reset_gate)"
  power="$(selected_container_power_state)"
  log="$(bounded_log_path stop)"
  : >"$log"
  if [ "$power" = stopped ]; then
    print_command_summary stop "" "ok state=already-stopped durable=$classification reset-gate=$reset_gate"
    return 0
  fi
  [ "$power" = running ] ||
    die "Docker stop requires uniformly running or stopped selected containers; current power state is $power"
  if [ "$classification" = exact-bound ]; then
    printf 'runtime-stop=jenkins-controller\n' >>"$log"
    __docker_set_runtime_stop_jenkins "$log" || rc=$?
    rc="${rc:-0}"
    if [ "$rc" -eq 0 ]; then
      printf 'runtime-stop=gerrit\n' >>"$log"
      __docker_set_runtime_stop_gerrit "$log" || rc=$?
      rc="${rc:-0}"
    fi
    if [ "$rc" -ne 0 ]; then
      evidence="$(write_evidence stop harness fail "simulate.sh stop" "$log" "Configured product runtime graceful stop failed")"
      print_command_failure stop "" failed "$log" "$evidence"
      return "$rc"
    fi
  elif ! __docker_set_require_baseline_runtimes_absent "$log"; then
    evidence="$(write_evidence stop harness fail "simulate.sh stop" "$log" "Unexpected configured product runtime exists in baseline state")"
    print_command_failure stop "" failed "$log" "$evidence"
    return 1
  fi
  printf 'compose-stop=begin\n' >>"$log"
  if compose stop >>"$log" 2>&1; then
    rc=0
  else
    rc=$?
  fi
  if [ "$rc" -ne 0 ]; then
    evidence="$(write_evidence stop harness fail "simulate.sh stop" "$log" "Compose stop failed")"
    print_command_failure stop "" failed "$log" "$evidence"
    return "$rc"
  fi
  [ "$(selected_container_power_state)" = stopped ] ||
    die "Docker stop did not leave every selected container stopped"
  __docker_set_verify_record
  evidence="$(write_evidence stop harness pass "simulate.sh stop" "$log" "Gracefully stopped configured runtimes and retained exact containers and writable layers")"
  print_command_summary stop "" "ok state=stopped durable=$classification reset-gate=$reset_gate"
}

__docker_set_cleanup_mutable_paths_host() {
  local path
  for path in \
    "$HARNESS_HOST_DIR/rendered" \
    "$HARNESS_RUNTIME_INPUT_DIR" \
    "$HARNESS_TARGET_SSH_DIR" \
    "$HARNESS_GERRIT_VALIDATION_SECRET_DIR" \
    "$HARNESS_BUNDLE_FACTORY_RENDERED_DIR" \
    "$HARNESS_BUNDLE_FACTORY_VALIDATION_PUBLIC_DIR"; do
    [ -e "$path" ] || continue
    rm -rf -- "$path" || return 1
  done
}

__docker_set_cleanup_mutable_paths_container() {
  local log
  log="${1:?log required}"
  docker run --rm \
    --mount "type=bind,source=$HARNESS_GENERATED_RUN_DIR,target=/cleanup-root" \
    "$HARNESS_UBUNTU_IMAGE" \
    sh -c 'rm -rf -- /cleanup-root/host/rendered /cleanup-root/host/runtime-inputs /cleanup-root/host/target-ssh /cleanup-root/host/validation-secrets /cleanup-root/host/bundle-factory' \
    >>"$log" 2>&1
}

__docker_set_backup_and_clear_retained_outputs() {
  local log backup_name backup_path uid gid
  log="${1:?log required}"
  backup_name="${2:?backup name required}"
  backup_path="$HARNESS_RETAINED_OUTPUT_BACKUP_DIR/$backup_name"
  uid="$(id -u)"
  gid="$(id -g)"
  docker run --rm \
    --mount "type=bind,source=$HARNESS_GENERATED_RUN_DIR,target=/cleanup-root" \
    "$HARNESS_UBUNTU_IMAGE" \
    sh -c '
      set -e
      backup_name="$1"
      uid="$2"
      gid="$3"
      backup_root="/cleanup-root/host/retained-output-backups/$backup_name"
      mkdir -p "$backup_root/target/artifacts" "$backup_root/host" "$backup_root/target"
      copy_if_present() {
        src="$1"
        dest="$2"
        [ -e "$src" ] || return 0
        mkdir -p "$(dirname "$dest")"
        cp -a "$src" "$dest"
      }
      copy_if_present /cleanup-root/target/artifacts/exported "$backup_root/target/artifacts/exported"
      copy_if_present /cleanup-root/host/evidence "$backup_root/host/evidence"
      copy_if_present /cleanup-root/host/logs "$backup_root/host/logs"
      copy_if_present /cleanup-root/target/evidence "$backup_root/target/evidence"
      copy_if_present /cleanup-root/target/logs "$backup_root/target/logs"
      rm -rf -- /cleanup-root/target/artifacts/exported /cleanup-root/host/evidence /cleanup-root/host/logs /cleanup-root/target/evidence /cleanup-root/target/logs
      chown -R "$uid:$gid" "$backup_root"
    ' sh "$backup_name" "$uid" "$gid" \
    >>"$log" 2>&1
  printf '%s\n' "$backup_path"
}

__docker_set_run_root_exists_for_recovery() {
  local expected actual_real expected_real
  expected="$(canonical_generated_run_dir)"
  [ "$HARNESS_GENERATED_RUN_DIR" = "$expected" ] || return 1
  [ -d "$HARNESS_GENERATED_RUN_DIR" ] || return 1
  [ ! -L "$HARNESS_GENERATED_RUN_DIR" ] || return 1
  actual_real="$(realpath "$HARNESS_GENERATED_RUN_DIR")"
  expected_real="$(realpath "$expected")"
  [ "$actual_real" = "$expected_real" ]
}

__docker_set_verify_clean_output_dirs() {
  [ -d "$HARNESS_EXPORTED_ARTIFACT_DIR" ] || mkdir -p "$HARNESS_EXPORTED_ARTIFACT_DIR"
  [ -d "$HARNESS_EVIDENCE_DIR" ] || mkdir -p "$HARNESS_EVIDENCE_DIR"
  [ -d "$HARNESS_LOG_DIR" ] || mkdir -p "$HARNESS_LOG_DIR"
  [ -d "$HARNESS_HOST_DIR/evidence/integration" ] || mkdir -p "$HARNESS_HOST_DIR/evidence/integration"
  [ -d "$HARNESS_HOST_DIR/logs/integration" ] || mkdir -p "$HARNESS_HOST_DIR/logs/integration"
  [ -d "$HARNESS_GERRIT_EVIDENCE_DIR" ] || mkdir -p "$HARNESS_GERRIT_EVIDENCE_DIR"
  [ -d "$HARNESS_GERRIT_LOG_DIR" ] || mkdir -p "$HARNESS_GERRIT_LOG_DIR"
  [ -d "$HARNESS_JENKINS_CONTROLLER_EVIDENCE_DIR" ] || mkdir -p "$HARNESS_JENKINS_CONTROLLER_EVIDENCE_DIR"
  [ -d "$HARNESS_JENKINS_CONTROLLER_LOG_DIR" ] || mkdir -p "$HARNESS_JENKINS_CONTROLLER_LOG_DIR"
  [ -d "$HARNESS_JENKINS_AGENT_EVIDENCE_DIR" ] || mkdir -p "$HARNESS_JENKINS_AGENT_EVIDENCE_DIR"
  [ -d "$HARNESS_JENKINS_AGENT_LOG_DIR" ] || mkdir -p "$HARNESS_JENKINS_AGENT_LOG_DIR"
}

docker_set_clean() {
  local log rc evidence cleanup_fallback container backup_name backup_path recovery_run_root_exists
  bootstrap_harness_env
  require_command docker
  recovery_run_root_exists=0
  if docker_set_runtime_config_valid; then
    detect_compose
    validate_canonical_run_root
    log="$(bounded_log_path clean)"
    cleanup_fallback=host
    if compose down --remove-orphans >"$log" 2>&1; then
      rc=0
    else
      rc=$?
    fi
  else
    if __docker_set_run_root_exists_for_recovery; then
      recovery_run_root_exists=1
    fi
    ensure_preflight_dirs
    log="$(bounded_log_path clean)"
    cleanup_fallback=skipped-invalid-runtime-config
    rc=0
    while IFS= read -r container; do
      [ -n "$container" ] || continue
      if docker rm -f "$container" >>"$log" 2>&1; then
        printf 'recovery_container_removed name=%s\n' "$container" >>"$log"
      else
        rc=$?
      fi
    done <<EOF
$(existing_selected_container_names)
EOF
    docker network rm "${HARNESS_PROJECT_NAME}_harness" >>"$log" 2>&1 || true
    printf 'recovery_mode=bootstrap-only reason=invalid-or-missing-runtime-config\n' >>"$log"
    printf 'host_generated_cleanup=skipped reason=invalid-or-missing-runtime-config\n' >>"$log"
  fi
  if [ "$rc" -ne 0 ]; then
    evidence="$(write_evidence clean harness fail "simulate.sh clean" "$log" "Compose shutdown before cleanup failed")"
    print_command_failure clean "" failed "$log" "$evidence"
    return "$rc"
  fi

  if [ "$cleanup_fallback" = "skipped-invalid-runtime-config" ]; then
    if [ "$recovery_run_root_exists" -eq 1 ]; then
      cleanup_fallback=container-recovery
      backup_name="clean-$(timestamp_utc)"
      if ! __docker_set_cleanup_mutable_paths_container "$log"; then
        evidence="$(write_evidence clean harness fail "simulate.sh clean" "$log" "Generated runtime cleanup failed during recovery")"
        print_command_failure clean "" failed "$log" "$evidence"
        return 1
      fi
      backup_path="$(__docker_set_backup_and_clear_retained_outputs "$log" "$backup_name")" || rc=$?
      rc="${rc:-0}"
      if [ "$rc" -ne 0 ]; then
        evidence="$(write_evidence clean harness fail "simulate.sh clean" "$log" "Retained output backup failed during recovery")"
        print_command_failure clean "" failed "$log" "$evidence"
        return "$rc"
      fi
      __docker_set_verify_clean_output_dirs
      evidence="$(write_evidence clean harness pass "simulate.sh clean" "$log" "Removed selected containers, cleaned mutable generated runtime data, and backed up retained outputs during recovery to $backup_path")"
      print_command_summary clean "" "removed containers runtime data backup=$backup_name cleanup=$cleanup_fallback"
      return 0
    else
      evidence="$(write_evidence clean harness pass "simulate.sh clean" "$log" "Removed selected containers with bootstrap recovery; host generated cleanup skipped because runtime config is invalid or missing")"
      print_command_summary clean "" "removed containers cleanup=skipped reason=invalid-or-missing-runtime-config"
      return 0
    fi
  fi

  if ! __docker_set_cleanup_mutable_paths_host >>"$log" 2>&1; then
    cleanup_fallback=container
    __docker_set_cleanup_mutable_paths_container "$log" || rc=$?
    rc="${rc:-0}"
    if [ "$rc" -ne 0 ]; then
      evidence="$(write_evidence clean harness fail "simulate.sh clean" "$log" "Generated runtime cleanup failed")"
      print_command_failure clean "" failed "$log" "$evidence"
      return "$rc"
    fi
  fi
  backup_name="clean-$(timestamp_utc)"
  backup_path="$(__docker_set_backup_and_clear_retained_outputs "$log" "$backup_name")" || rc=$?
  rc="${rc:-0}"
  if [ "$rc" -ne 0 ]; then
    evidence="$(write_evidence clean harness fail "simulate.sh clean" "$log" "Retained output backup failed")"
    print_command_failure clean "" failed "$log" "$evidence"
    return "$rc"
  fi
  ensure_preflight_dirs
  __docker_set_verify_clean_output_dirs
  evidence="$(write_evidence clean harness pass "simulate.sh clean" "$log" "Removed mutable generated runtime data and backed up retained outputs to $backup_path")"
  print_command_summary clean "" "removed runtime data backup=$backup_name cleanup=$cleanup_fallback"
}

docker_set_require_runtime() {
  if [ -n "$HARNESS_RENDERED_ENV_OPERATOR_SET" ] && docker_config_load_runtime_if_present; then
    verify_run_marker
    validate_core_generated_state
    return 0
  fi
  if docker_config_load_runtime_if_present; then
    verify_run_marker
    validate_core_generated_state
    return 0
  fi
  if selected_containers_exist; then
    die "Docker generated state is missing while selected containers exist; use stop and explicit recovery before resuming"
  fi
  die "Missing Docker harness runtime config: run init-run first"
}

docker_set_runtime_config_valid() {
  (
    docker_config_load_runtime_if_present &&
    verify_run_marker >/dev/null 2>&1 &&
    validate_core_generated_state >/dev/null 2>&1
  ) >/dev/null 2>&1
}

docker_set_verify_selected_mounts() {
  validate_selected_container_mounts
}
