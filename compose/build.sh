cd "$(dirname "$0")"

IROC_DEV_IMAGE="${1:-${IROC_DEV_IMAGE:-ctumrs/mrs_uav_system:stable}}" docker compose \
 -f compose.build.yaml \
 run --rm builder
