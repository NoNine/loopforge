#!/usr/bin/env sh
set -eu

mkdir -p /var/lib/loopforge/evidence /var/log/loopforge
printf '%s\n' "simulation-only public internet fallback is not production support" \
  > /var/lib/loopforge/source-boundary.txt
exec sleep infinity
