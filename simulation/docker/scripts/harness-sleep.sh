#!/usr/bin/env sh
set -eu

mkdir -p /run/sshd
/usr/sbin/sshd

exec sleep infinity
