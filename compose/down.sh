cd "$(dirname "$0")"

docker compose \
 -f compose.yaml \
 --env-file ./stack.env \
 down -v --remove-orphans --timeout 1
docker network prune -f
