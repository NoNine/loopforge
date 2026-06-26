#!/usr/bin/env sh
set -eu

mkdir -p /var/lib/loopforge/evidence /var/log/loopforge
printf '%s\n' "simulation-only public internet fallback is not production support" \
  > /var/lib/loopforge/source-boundary.txt

if [ -s /var/lib/loopforge/target-ssh/ci-operator.pub ]; then
  install -d -m 700 -o ci-operator -g ci-operator /home/ci-operator/.ssh
  install -m 600 -o ci-operator -g ci-operator \
    /var/lib/loopforge/target-ssh/ci-operator.pub \
    /home/ci-operator/.ssh/authorized_keys
fi

mkdir -p /run/sshd
/usr/sbin/sshd

exec sleep infinity
