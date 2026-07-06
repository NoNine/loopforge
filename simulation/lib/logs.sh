#!/usr/bin/env bash

bounded_log_path_in_dir() {
  local dir name
  dir="${1:?log dir required}"
  name="${2:?log name required}"
  mkdir -p "$dir"
  printf '%s/%s-%s.log' "$dir" "$name" "$(timestamp_utc)"
}
