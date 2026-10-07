#!/usr/bin/env bash
# Usage: ./run.sh [image] — interactive shell in the ground environment (MODE defaults to experiment)

set -euo pipefail

cd "$(dirname "$0")"

export MODE="${MODE:-experiment}"
export ROOT_DIR="$(realpath ..)"
export MRS_SYSTEM_IMAGE="${1:-${MRS_SYSTEM_IMAGE:-ctumrs/mrs_uav_system:stable}}"

exec docker compose \
  -f compose.yaml \
  --env-file ./stack.env \
  --env-file "./modes/$MODE.env" \
  run --rm --interactive --tty test
