#!/usr/bin/env bash

# Source from a fake docker executable. Return 125 when the caller should
# handle a command with test-specific behavior.
fake_docker_set_handle() {
  local command_text name format service index power
  local -a args services
  args=("$@")
  services=(bundle-factory ldap gerrit-target jenkins-controller-target jenkins-agent-target)
  : "${DOCKER_SET_FAKE_STATE_DIR:?DOCKER_SET_FAKE_STATE_DIR is required}"
  mkdir -p "$DOCKER_SET_FAKE_STATE_DIR"
  command_text="$*"

  fake_docker_set_container_field() {
    local selected field
    selected="$1"
    field="$2"
    awk -F '\t' -v selected="$selected" -v field="$field" '
      $1 == selected || $2 == selected {
        if (field == "id") print $2
        if (field == "running") print $3
        if (field == "image") print $4
        if (field == "driver") print $5
      }
    ' "$DOCKER_SET_FAKE_STATE_DIR/containers" 2>/dev/null
  }

  fake_docker_set_power() {
    local selected_power
    selected_power="$1"
    awk -F '\t' -v power="$selected_power" 'BEGIN { OFS="\t" } { $3=power; print }' \
      "$DOCKER_SET_FAKE_STATE_DIR/containers" >"$DOCKER_SET_FAKE_STATE_DIR/containers.tmp"
    mv "$DOCKER_SET_FAKE_STATE_DIR/containers.tmp" "$DOCKER_SET_FAKE_STATE_DIR/containers"
  }

  fake_docker_set_record_value() {
    local file key
    file="$1"
    key="$2"
    awk -F= -v key="$key" '$1 == key { print substr($0, length(key) + 2); exit }' "$file"
  }

  fake_docker_set_create_containers() {
    local selected_service selected_index generation container_id
    generation=0
    [ ! -f "$DOCKER_SET_FAKE_STATE_DIR/generation" ] ||
      generation="$(cat "$DOCKER_SET_FAKE_STATE_DIR/generation")"
    generation=$((generation + 1))
    printf '%s\n' "$generation" >"$DOCKER_SET_FAKE_STATE_DIR/generation"
    if [ -f "$DOCKER_SET_FAKE_STATE_DIR/containers" ]; then
      awk -F '\t' -v prefix="$HARNESS_PROJECT_NAME-" \
        'index($1, prefix) != 1' "$DOCKER_SET_FAKE_STATE_DIR/containers" \
        >"$DOCKER_SET_FAKE_STATE_DIR/containers.next"
      mv "$DOCKER_SET_FAKE_STATE_DIR/containers.next" \
        "$DOCKER_SET_FAKE_STATE_DIR/containers"
    else
      : >"$DOCKER_SET_FAKE_STATE_DIR/containers"
    fi
    selected_index=0
    for selected_service in "${services[@]}"; do
      selected_index=$((selected_index + 1))
      if [ "$generation" -eq 1 ]; then
        container_id="cid-$selected_index"
      else
        container_id="cid-$generation-$selected_index"
      fi
      printf '%s-%s\t%s\tfalse\timage-%s\toverlayfs\n' \
        "$HARNESS_PROJECT_NAME" "$selected_service" "$container_id" \
        "$selected_service" >>"$DOCKER_SET_FAKE_STATE_DIR/containers"
    done
    if [ -n "${DOCKER_SET_FAKE_BASELINE_SECRET:-}" ]; then
      printf '%s\n' "$HARNESS_LDAP_BIND_PASSWORD" >"$HARNESS_LDAP_DATA_DIR/secret"
    elif [ -n "${DOCKER_SET_FAKE_BASELINE_MARKER:-}" ]; then
      printf '%s\n' clean-ldap-baseline >"$HARNESS_LDAP_DATA_DIR/clean-marker"
    fi
  }

  case "$command_text" in
    *"compose version"*) printf 'Docker Compose version v2.0.0\n'; return 0 ;;
  esac

  if [ "${args[0]:-}" = compose ]; then
    index=1
    while [ "$index" -lt "${#args[@]}" ]; do
      case "${args[$index]}" in
        --project-name|--file) index=$((index + 2)) ;;
        config) printf 'project=%s compose=v1\n' "$HARNESS_PROJECT_NAME"; return 0 ;;
        build) return 0 ;;
        create)
          fake_docker_set_create_containers
          return 0
          ;;
        up)
          [ "${args[$((index + 1))]:-}" = --no-start ] || return 2
          [ "${args[$((index + 2))]:-}" = --no-build ] || return 2
          fake_docker_set_create_containers
          [ -f "$DOCKER_SET_FAKE_STATE_DIR/network" ] ||
            printf '%s_harness\tnetwork-id\n' "$HARNESS_PROJECT_NAME" \
              >"$DOCKER_SET_FAKE_STATE_DIR/network"
          return 0
          ;;
        start)
          [ -f "$DOCKER_SET_FAKE_STATE_DIR/network" ] || return 1
          fake_docker_set_power true
          return 0
          ;;
        stop) fake_docker_set_power false; return 0 ;;
        exec)
          index=$((index + 1))
          while [ "$index" -lt "${#args[@]}" ]; do
            case "${args[$index]}" in
              -T) index=$((index + 1)) ;;
              -u|-e) index=$((index + 2)) ;;
              *) service="${args[$index]}"; index=$((index + 1)); break ;;
            esac
          done
          command_text="${args[*]:$index}"
          case "$command_text" in
            *'printf "%s %s\n"'*)
              printf '24.04 noble\n'
              return 0
              ;;
            *'/etc/os-release'*)
              printf 'release=24.04 codename=noble pretty=Ubuntu 24.04\n'
              return 0
              ;;
            *"stat -c %u:%g"*|*"stat -c '%u:%g'"*)
              case "$service" in
                gerrit-target) printf '61010:61010\n' ;;
                jenkins-controller-target) printf '61020:61020\n' ;;
                jenkins-agent-target) printf '61030:61030\n' ;;
              esac
              return 0
              ;;
            *'stat -Lc %d:%i'*|*"stat -Lc '%d:%i'"*)
              name="${args[${#args[@]}-1]}"
              case "$service:$name" in
                ldap:/var/lib/ldap) name="$HARNESS_LDAP_DATA_DIR" ;;
                ldap:/etc/ldap/slapd.d) name="$HARNESS_LDAP_CONFIG_DIR" ;;
                bundle-factory:/workspace|gerrit-target:/workspace|jenkins-controller-target:/workspace|jenkins-agent-target:/workspace) name="$REPO_ROOT" ;;
                gerrit-target:/srv/gerrit) name="$HARNESS_PRODUCT_HOME_DIR/gerrit" ;;
                jenkins-controller-target:/var/lib/jenkins) name="$HARNESS_PRODUCT_HOME_DIR/jenkins-controller" ;;
                jenkins-agent-target:/var/lib/jenkins-agent) name="$HARNESS_PRODUCT_HOME_DIR/jenkins-agent" ;;
                jenkins-controller-target:/data/jenkins-shared|jenkins-agent-target:/data/jenkins-shared) name="$HARNESS_SHARED_JENKINS_STORAGE_DIR" ;;
                *) return 125 ;;
              esac
              stat -Lc '%d:%i' "$name"
              return 0
              ;;
          esac
          return 125
          ;;
        *) return 125 ;;
      esac
    done
  fi

  case "${args[0]:-}" in
    ps)
      if [ "${args[1]:-}" = -a ] && [ "${args[2]:-}" = --format ]; then
        [ ! -f "$DOCKER_SET_FAKE_STATE_DIR/containers" ] ||
          cut -f1 "$DOCKER_SET_FAKE_STATE_DIR/containers"
        return 0
      fi
      ;;
    inspect)
      [ "${args[1]:-}" = -f ] || return 125
      format="${args[2]}"
      name="${args[3]}"
      case "$format" in
        '{{.Id}}') fake_docker_set_container_field "$name" id; return 0 ;;
        '{{.Image}}') fake_docker_set_container_field "$name" image; return 0 ;;
        '{{json .GraphDriver.Data}}') return 97 ;;
        '{{.Driver}}')
          [ "${DOCKER_DRIVER_INSPECT_FAIL:-0}" != 1 ] || return 98
          fake_docker_set_container_field "$name" driver
          return 0
          ;;
        '{{.State.Running}}') fake_docker_set_container_field "$name" running; return 0 ;;
        *'.Mounts'*)
          [ "${DOCKER_SET_FAKE_DELEGATE_MOUNTS:-0}" != 1 ] || return 125
          service="${name#"$HARNESS_PROJECT_NAME"-}"
          case "$service" in
            bundle-factory) printf '%s\t/workspace\n' "$REPO_ROOT" ;;
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
          return 0
          ;;
        *'org.loopforge.resource'*) printf 'docker-simulation\n'; return 0 ;;
        *'org.loopforge.project'*) printf '%s\n' "$HARNESS_PROJECT_NAME"; return 0 ;;
        *'org.loopforge.set-id'*) printf '%s\n' "$HARNESS_SET_ID"; return 0 ;;
        *'org.loopforge.service'*) printf '%s\n' "${name#"$HARNESS_PROJECT_NAME"-}"; return 0 ;;
      esac
      ;;
    network)
      [ "${args[1]:-}" = inspect ] || return 125
      [ "${args[2]:-}" = -f ] || return 125
      format="${args[3]}"
      name="${args[4]}"
      grep -Fq "$name" "$DOCKER_SET_FAKE_STATE_DIR/network" 2>/dev/null || return 1
      case "$format" in
        '{{.Id}}') cut -f2 "$DOCKER_SET_FAKE_STATE_DIR/network"; return 0 ;;
        *'org.loopforge.resource'*) printf 'docker-simulation\n'; return 0 ;;
        *'org.loopforge.project'*) printf '%s\n' "$HARNESS_PROJECT_NAME"; return 0 ;;
        *'org.loopforge.set-id'*) printf '%s\n' "$HARNESS_SET_ID"; return 0 ;;
        *'org.loopforge.network'*) printf 'harness\n'; return 0 ;;
      esac
      ;;
    cp)
      local_source="${args[1]:-}"
      local_destination="${args[2]:-}"
      name="${local_source%%:*}"
      container_path="${local_source#*:}"
      service="${name#"$HARNESS_PROJECT_NAME-"}"
      case "$service:$container_path" in
        ldap:/var/lib/ldap/.) host_path="$HARNESS_LDAP_DATA_DIR" ;;
        ldap:/etc/ldap/slapd.d/.) host_path="$HARNESS_LDAP_CONFIG_DIR" ;;
        gerrit-target:/srv/gerrit/.) host_path="$HARNESS_PRODUCT_HOME_DIR/gerrit" ;;
        jenkins-controller-target:/var/lib/jenkins/.) host_path="$HARNESS_PRODUCT_HOME_DIR/jenkins-controller" ;;
        jenkins-agent-target:/var/lib/jenkins-agent/.) host_path="$HARNESS_PRODUCT_HOME_DIR/jenkins-agent" ;;
        jenkins-agent-target:"$HARNESS_JENKINS_SHARED_STORAGE_PATH"/.) host_path="$HARNESS_SHARED_JENKINS_STORAGE_DIR" ;;
        *:/etc/ssh/ssh_host_*_key.pub)
          if [ ! -f "$DOCKER_SET_FAKE_STATE_DIR/ssh-host-key.pub" ]; then
            ssh-keygen -q -t ed25519 -N '' -f "$DOCKER_SET_FAKE_STATE_DIR/ssh-host-key" >/dev/null
          fi
          cp "$DOCKER_SET_FAKE_STATE_DIR/ssh-host-key.pub" "$local_destination"
          return 0
          ;;
        *) return 125 ;;
      esac
      [ "$local_destination" = - ] || return 125
      tar -C "$host_path" -cpf - .
      return 0
      ;;
    rm)
      selected="${args[1]:-}"
      awk -F '\t' -v selected="$selected" 'BEGIN { OFS="\t" } $1 != selected && $2 != selected' \
        "$DOCKER_SET_FAKE_STATE_DIR/containers" >"$DOCKER_SET_FAKE_STATE_DIR/containers.tmp"
      mv "$DOCKER_SET_FAKE_STATE_DIR/containers.tmp" "$DOCKER_SET_FAKE_STATE_DIR/containers"
      return 0
      ;;
    run)
      restore_fake_archive() {
        local archive target metadata uid rest gid mode
        archive="$1"
        target="$2"
        metadata="$3"
        uid="${metadata%%:*}"
        rest="${metadata#*:}"
        gid="${rest%%:*}"
        mode="${metadata##*:}"
        find "$target" -mindepth 1 -delete
        tar --numeric-owner -xpf "$archive" -C "$target"
        chown "$uid:$gid" "$target"
        chmod "$mode" "$target"
        tar --numeric-owner --compare -f "$archive" -C "$target"
      }
      restore_fake_archive "$HARNESS_BASELINE_ARCHIVE_DIR/ldap_data.tar" \
        "$HARNESS_LDAP_DATA_DIR" "$(fake_docker_set_record_value "$HARNESS_BASELINE_MANIFEST" archive_ldap_data_root_metadata)"
      restore_fake_archive "$HARNESS_BASELINE_ARCHIVE_DIR/ldap_config.tar" \
        "$HARNESS_LDAP_CONFIG_DIR" "$(fake_docker_set_record_value "$HARNESS_BASELINE_MANIFEST" archive_ldap_config_root_metadata)"
      restore_fake_archive "$HARNESS_BASELINE_ARCHIVE_DIR/gerrit_home.tar" \
        "$HARNESS_PRODUCT_HOME_DIR/gerrit" "$(fake_docker_set_record_value "$HARNESS_BASELINE_MANIFEST" archive_gerrit_home_root_metadata)"
      restore_fake_archive "$HARNESS_BASELINE_ARCHIVE_DIR/jenkins_controller_home.tar" \
        "$HARNESS_PRODUCT_HOME_DIR/jenkins-controller" "$(fake_docker_set_record_value "$HARNESS_BASELINE_MANIFEST" archive_jenkins_controller_home_root_metadata)"
      restore_fake_archive "$HARNESS_BASELINE_ARCHIVE_DIR/jenkins_agent_home.tar" \
        "$HARNESS_PRODUCT_HOME_DIR/jenkins-agent" "$(fake_docker_set_record_value "$HARNESS_BASELINE_MANIFEST" archive_jenkins_agent_home_root_metadata)"
      restore_fake_archive "$HARNESS_BASELINE_ARCHIVE_DIR/shared_jenkins_storage.tar" \
        "$HARNESS_SHARED_JENKINS_STORAGE_DIR" "$(fake_docker_set_record_value "$HARNESS_BASELINE_MANIFEST" archive_shared_jenkins_storage_root_metadata)"
      return 0
      ;;
  esac
  return 125
}
