#!/usr/bin/env bash
# Usage: ./up.sh experiment|simulation|remote-sim|ground-only
#
# Optional, for tests (environment variables):
#   simulation:   SIM_UAVS="uav1"    run only these of the configured UAVs (default: all of modes/simulation.env)
#                 SIM_TAKEOFF=0      do not arm / switch to offboard, so the UAVs stay on the ground
#   any mode:     BRIDGE_CUSTOM_CONFIG=./compose/testing/bridge_test.yaml  extra bridge config (path relative to ROOT)
#   ground-only:  FAKE_ROBOTS="uav1" also start fake mission handlers for these robots (compose/testing/fake_robots.py)
#                 FAKE_FAIL_UPLOAD="uav2"  fake robots that refuse uploads

set -euo pipefail

cd "$(dirname "$0")"

MODE="${1:-}"
case "$MODE" in
  experiment|simulation|remote-sim|ground-only) ;;
  *) echo "Usage: $0 experiment|simulation|remote-sim|ground-only"; exit 1 ;;
esac

export MODE
export ROOT_DIR="$(realpath ..)"

mkdir -p _logs
mkdir -p "$ROOT_DIR/.assets"   # persistent data (test databases), bind-mounted at /var/lib/holoswarm/assets

dc() {
  docker compose --env-file ./stack.env --env-file "./modes/$MODE.env" "$@"
}

if [ "$MODE" = simulation ]; then
  CONFIGURED_UAVS="$(set -a; . ./modes/simulation.env; echo "$SIM_UAVS")"
  SIM_UAVS="${SIM_UAVS:-$CONFIGURED_UAVS}"
  export SIM_TAKEOFF="${SIM_TAKEOFF:-1}"

  if [ "$SIM_UAVS" != "$CONFIGURED_UAVS" ]; then
    # Simulator and network configs listing only the selected UAVs (paths relative to ROOT_DIR).
    python3 simulation/scripts/select_uavs.py simulation/config simulation/_generated $SIM_UAVS
    export SIM_CONFIG_DIR=./compose/simulation/_generated
    export NETWORK_CONFIG=./compose/simulation/_generated/network_config.yaml
  fi
fi

dc -p ground -f compose.yaml up -d

if [ "$MODE" = ground-only ] && [ -n "${FAKE_ROBOTS:-}" ]; then
  export FAKE_ROBOTS FAKE_FAIL_UPLOAD="${FAKE_FAIL_UPLOAD:-}"
  dc -p ground -f compose.yaml --profile fake-robots up -d fake_robots
fi

if [ "$MODE" = simulation ]; then
  dc -p sim -f simulation/compose.yaml up -d

  for uav in $SIM_UAVS; do
    UAV_NAME="$uav" dc -p "$uav" -f simulation/compose.uav.yaml up -d
  done
fi
