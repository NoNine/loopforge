#!/usr/bin/env bash

evidence_record_path() {
  local evidence_dir checkpoint role
  evidence_dir="${1:?evidence dir required}"
  checkpoint="${2:?checkpoint required}"
  role="${3:?role required}"
  printf '%s/%s-%s-%s.json\n' "$evidence_dir" "$checkpoint" "$role" "$(timestamp_utc)"
}
