#!/usr/bin/env bash
# Tears down every project, whatever mode it was started in.

cd "$(dirname "$0")"

export ROOT_DIR="$(realpath ..)"

# UAV projects to remove: SIM_UAVS if given, the configured UAVs, and any existing
# per-UAV project (started from simulation/compose.uav.yaml, e.g. with up.sh SIM_UAVS=...).
CONFIGURED_UAVS="$(set -a; . ./modes/simulation.env; echo "$SIM_UAVS")"
RUNNING_UAVS="$(docker ps -a --filter label=com.docker.compose.project \
  --format '{{.Label "com.docker.compose.project"}} {{.Label "com.docker.compose.project.config_files"}}' \
  | awk '$2 ~ /simulation\/compose\.uav\.yaml$/ { print $1 }')"
SIM_UAVS="$(printf '%s\n' ${SIM_UAVS:-} $CONFIGURED_UAVS $RUNNING_UAVS | sort -u)"

dc() {
  docker compose --profile "*" --env-file ./stack.env --env-file ./modes/simulation.env "$@" down -v --remove-orphans --timeout 1
}

for uav in $SIM_UAVS; do
  UAV_NAME="$uav" dc -p "$uav" -f simulation/compose.uav.yaml
done
dc -p sim -f simulation/compose.yaml
MODE=simulation dc -p ground -f compose.yaml

docker network prune -f
