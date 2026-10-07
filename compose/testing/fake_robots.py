"""Fake iroc_mission_handler for tests without simulated robots (compose ground-only mode).

Usage: fake_robots.py uav1 [uav2 ...]

Per robot: publishes GeneralRobotInfo (so the planners see it in the fleet), serves upload/unload,
activation and pausing, and the Mission action under the names the fleet manager is remapped to.
A goal waits for activation, then "flies" for RUN_SECONDS with feedback and succeeds; it can be
cancelled. FAIL_UPLOAD=uav2 makes that robot refuse uploads, and every robot refuses tasks with
"refuse-upload" in their id (lets a test pick the failure per mission). Every call is printed.
"""
import sys
import os
import threading
import time

import rclpy
from rclpy.action import ActionServer, CancelResponse, GoalResponse
from rclpy.callback_groups import ReentrantCallbackGroup
from rclpy.executors import MultiThreadedExecutor
from rclpy.node import Node

from iroc_mission_handler.action import Mission
from iroc_mission_handler.srv import UploadMissionSrv, UnloadMissionSrv
from mrs_msgs.msg import GeneralRobotInfo
from std_srvs.srv import Trigger

RUN_SECONDS = float(os.environ.get("RUN_SECONDS", "2.0"))
FAIL_UPLOAD = set(os.environ.get("FAIL_UPLOAD", "").replace(",", " ").split())


class FakeHandler:
    def __init__(self, node: Node, robot: str):
        self.node, self.robot = node, robot
        self.lock = threading.Lock()
        self.staged = None
        self.active = False
        self.activated = threading.Event()
        self.log = []
        group = ReentrantCallbackGroup()
        ns = f"/{robot}"
        self.pub = node.create_publisher(GeneralRobotInfo, f"{ns}/state_monitor/general_robot_info", 10)
        node.create_timer(0.5, self.publish_info)
        node.create_service(UploadMissionSrv, f"{ns}/iroc_mission_handler/upload_mission", self.upload, callback_group=group)
        node.create_service(UnloadMissionSrv, f"{ns}/iroc_mission_handler/unload_mission", self.unload, callback_group=group)
        node.create_service(Trigger, f"{ns}/iroc_mission_handler/mission_activation", self.activate, callback_group=group)
        node.create_service(Trigger, f"{ns}/iroc_mission_handler/mission_pausing", self.pause, callback_group=group)
        ActionServer(node, Mission, f"{ns}/mission_handler", execute_callback=self.execute, goal_callback=self.on_goal,
                     cancel_callback=lambda _: CancelResponse.ACCEPT, callback_group=group)

    def say(self, text):
        print(f"[{self.robot}] {text}", flush=True)

    def publish_info(self):
        msg = GeneralRobotInfo()
        msg.robot_name = self.robot
        self.pub.publish(msg)

    def upload(self, req, resp):
        with self.lock:
            if self.robot in FAIL_UPLOAD or "refuse-upload" in req.robot_goal.task_id:
                resp.success, resp.message = False, "Robot is not IDLE (test)"
            elif self.staged is not None or self.active:
                resp.success, resp.message = False, "Robot is not IDLE"
            else:
                self.staged = req.robot_goal.task_id
                resp.success, resp.message = True, "staged"
        self.say(f"upload {req.robot_goal.task_id}: {resp.message}")
        return resp

    def unload(self, req, resp):
        with self.lock:
            if self.staged is None or self.active:
                resp.success, resp.message = False, "No staged mission to unload"
            else:
                self.say(f"unload {self.staged}")
                self.staged = None
                resp.success, resp.message = True, "unloaded"
        return resp

    def on_goal(self, goal):
        with self.lock:
            if self.active:
                return GoalResponse.REJECT
            fast = self.staged is not None
            self.staged = None
            self.active = True
            self.activated.clear()
        self.say(f"goal {goal.robot_goal.task_id} accepted ({'staged' if fast else 'fresh'})")
        return GoalResponse.ACCEPT

    def activate(self, req, resp):
        if not self.active:
            resp.success, resp.message = False, "No active mission."
        else:
            self.activated.set()
            resp.success, resp.message = True, "activated"
        return resp

    def pause(self, req, resp):
        resp.success, resp.message = True, "paused"
        return resp

    def execute(self, handle):
        task = handle.request.robot_goal.task_id
        result = Mission.Result()
        result.robot_result.name, result.robot_result.task_id = self.robot, task
        try:
            while not self.activated.wait(0.1):
                if handle.is_cancel_requested:
                    handle.canceled()
                    result.robot_result.message = "cancelled before start"
                    return result
            self.say(f"running {task}")
            start = time.time()
            while time.time() - start < RUN_SECONDS:
                if handle.is_cancel_requested:
                    handle.canceled()
                    result.robot_result.message = "cancelled"
                    self.say(f"cancelled {task}")
                    return result
                fb = Mission.Feedback()
                fb.robot_feedback.name, fb.robot_feedback.task_id = self.robot, task
                fb.robot_feedback.message = "EXECUTING"
                fb.robot_feedback.mission_progress = 100.0 * (time.time() - start) / RUN_SECONDS
                handle.publish_feedback(fb)
                time.sleep(0.2)
            handle.succeed()
            result.robot_result.success, result.robot_result.message = True, "done"
            self.say(f"finished {task}")
            return result
        finally:
            with self.lock:
                self.active = False


def main():
    rclpy.init()
    node = Node("fake_mission_handlers")
    robots = sys.argv[1:] or ["uav1"]
    handlers = [FakeHandler(node, r) for r in robots]
    executor = MultiThreadedExecutor(num_threads=8)
    executor.add_node(node)
    print(f"fake robots up: {' '.join(robots)} (refusing uploads: {' '.join(sorted(FAIL_UPLOAD)) or 'none'})", flush=True)
    try:
        executor.spin()
    finally:
        rclpy.shutdown()


if __name__ == "__main__":
    main()
