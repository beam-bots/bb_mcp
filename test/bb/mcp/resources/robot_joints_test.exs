# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.MCP.Resources.RobotJointsTest do
  use ExUnit.Case, async: false

  alias Anubis.Server.Frame
  alias BB.Math.Transform2D
  alias BB.MCP.PlanarRobot
  alias BB.MCP.Resources.RobotJoints
  alias BB.Message.Geometry.Twist2D
  alias BB.Robot.Runtime
  alias BB.Robot.State, as: RobotState

  setup do
    original = Application.get_env(:bb_mcp, :robots, [])
    Application.put_env(:bb_mcp, :robots, [PlanarRobot])
    on_exit(fn -> Application.put_env(:bb_mcp, :robots, original) end)

    start_supervised!({PlanarRobot, [simulation: :kinematic]})

    {:ok, frame: Frame.new()}
  end

  test "a planar joint's position and velocity carry their own fields", %{frame: frame} do
    state = Runtime.get_robot_state(PlanarRobot)
    :ok = RobotState.set_configuration(state, :ground, Transform2D.new(1.5, -0.5, 0.25))
    :ok = RobotState.set_velocity(state, :ground, %Twist2D{vx: 0.1, vy: 0.0, omega: -0.2})

    %{"positions" => positions, "velocities" => velocities} = read(frame)

    assert positions["ground"] == %{"x" => 1.5, "y" => -0.5, "theta" => 0.25}
    assert velocities["ground"] == %{"vx" => 0.1, "vy" => 0.0, "omega" => -0.2}
  end

  test "a single-degree-of-freedom joint stays a bare number", %{frame: frame} do
    state = Runtime.get_robot_state(PlanarRobot)
    :ok = RobotState.set_configuration(state, :shoulder, 0.25)

    %{"positions" => positions, "velocities" => velocities} = read(frame)

    assert positions["shoulder"] == 0.25
    assert velocities["shoulder"] == 0.0
  end

  defp read(frame) do
    assert {:reply, response, ^frame} =
             RobotJoints.read(%{"params" => %{"robot" => "planar_robot"}}, frame)

    assert %{"text" => text} = response.contents

    JSON.decode!(text)
  end
end
