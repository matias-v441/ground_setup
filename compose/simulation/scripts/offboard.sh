#!/usr/bin/env bash

cd "$(dirname "$0")"

UAV="${1:-uav1}"
TAKEOFF="${2:-1}"

if [ "$TAKEOFF" = 0 ]; then
  echo "SIM_TAKEOFF=0: not arming $UAV, it stays on the ground"
  exit 0
fi

# Arm only once the core is up: automatic_start disarms if control output is not
# enabled within control_output_timeout (1.5 s) after arming, and does not retry.
echo "waiting for core"
for topic_type in \
  "control_manager/diagnostics mrs_msgs/msg/ControlManagerDiagnostics" \
  "uav_manager/diagnostics mrs_msgs/msg/UavManagerDiagnostics" \
  "estimation_manager/diagnostics mrs_msgs/msg/EstimationDiagnostics" \
  "safety_area_manager/diagnostics mrs_msgs/msg/SafetyAreaManagerDiagnostics"; do
  set -- $topic_type
  ros2 topic echo --once /$UAV/$1 $2 > /dev/null
done
sleep 2

echo "arming"

ros2 service call /$UAV/hw_api/arming std_srvs/srv/SetBool '{"data": true}'

./waitForControlOutput

echo "toggling offboard"

ros2 service call /$UAV/hw_api/offboard std_srvs/srv/Trigger '{}' | tee /dev/stderr | grep -q "success=True"
