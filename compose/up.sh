cd "$(dirname "$0")"
mkdir -p _logs

docker compose \
 -f compose.yaml \
 --env-file ./stack.env \
 up -d
