#!/usr/bin/env bash

set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=common.sh
. "$script_dir/common.sh"

command_name="${1:-}"
unsupported_placeholder "$(basename "$0")" "$command_name"
