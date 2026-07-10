#!/usr/bin/env bash

set -euo pipefail

test_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
VM_TEST_INCLUDE_M5=1 exec "$test_dir/vm-harness-m3-lifecycle-test.sh"
