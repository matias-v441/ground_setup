cd "$(dirname "$0")"

MRS_SYSTEM_IMAGE="${1:-${MRS_SYSTEM_IMAGE:-ctumrs/mrs_uav_system:stable}}" docker compose \
 -f compose.build.yaml \
 run --rm builder
