# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.MCP.Tools.SendJointPositionsTest do
  use ExUnit.Case, async: false

  alias Anubis.MCP.Error
  alias Anubis.Server.Frame
  alias BB.MCP.PlanarRobot
  alias BB.MCP.Tools.SendJointPositions
  alias BB.Safety

  setup do
    original = Application.get_env(:bb_mcp, :robots, [])
    Application.put_env(:bb_mcp, :robots, [PlanarRobot])
    on_exit(fn -> Application.put_env(:bb_mcp, :robots, original) end)

    start_supervised!({PlanarRobot, [simulation: :kinematic]})
    :ok = Safety.arm(PlanarRobot)

    {:ok, frame: Frame.new()}
  end

  # A planar joint's configuration is a whole 2D pose, so a scalar leaves two
  # of its three numbers unsaid. Accepting one and reporting `ok` would tell an
  # agent the robot moved when nothing did.
  test "refuses a single position for a joint with more than one degree of freedom",
       %{frame: frame} do
    assert {:error, %Error{} = error, ^frame} =
             SendJointPositions.execute(
               %{robot: "planar_robot", joint: "ground", position: 0.5},
               frame
             )

    assert error.data.message =~ "ground"
    assert error.data.message =~ "3 degrees of freedom"
  end

  test "refuses a joint that has no actuators to drive it", %{frame: frame} do
    assert {:error, %Error{} = error, ^frame} =
             SendJointPositions.execute(
               %{robot: "planar_robot", joint: "shoulder", position: 0.5},
               frame
             )

    assert error.data.message =~ "no actuators"
  end
end
