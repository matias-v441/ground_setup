#!/usr/bin/env bash
set -e

SESSION="${1:-}"

CONTAINER="${2:-core}"

if [ -z "$SESSION" ]; then
  echo "Usage: $0 <container_name_or_id>"
  echo
  echo "Running containers:"
  docker ps --format "table {{.Names}}\t{{.ID}}\t{{.Image}}\t{{.Status}}"
  exit 1
fi

docker exec -it "$SESSION-$CONTAINER-1" bash -lc '. /opt/ros/jazzy/setup.sh && . holoswarm_ros_packages/install/setup.sh && exec bash'
