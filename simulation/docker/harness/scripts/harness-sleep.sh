#!/usr/bin/env sh
set -eu

mkdir -p /harness/state /harness/evidence /harness/logs
printf '%s\n' "simulation-only public internet fallback is not production support" \
  > /harness/state/source-boundary.txt
exec sleep infinity
