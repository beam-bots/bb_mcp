# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.MCP.Resources.RobotTopologyTest do
  use ExUnit.Case, async: false

  alias Anubis.Server.Frame
  alias BB.MCP.PlanarRobot
  alias BB.MCP.Resources.RobotTopology

  setup do
    original = Application.get_env(:bb_mcp, :robots, [])
    Application.put_env(:bb_mcp, :robots, [PlanarRobot])
    on_exit(fn -> Application.put_env(:bb_mcp, :robots, original) end)

    start_supervised!({PlanarRobot, [simulation: :kinematic]})

    {:ok, frame: Frame.new()}
  end

  test "a joint reports the limits declared on it, in SI units", %{frame: frame} do
    assert %{"limit" => limit} = joint(frame, "shoulder")

    assert limit["lower"] == -:math.pi() / 2
    assert limit["upper"] == :math.pi() / 2
    assert limit["velocity"] == :math.pi() / 2
    assert limit["effort"] == 1.0
  end

  test "a joint with no limit block carries no limit key", %{frame: frame} do
    refute Map.has_key?(joint(frame, "ground"), "limit")
  end

  test "a joint reports its axis, which is what a planar joint's plane is normal to",
       %{frame: frame} do
    assert joint(frame, "ground")["axis"] == %{"x" => 0.0, "y" => 0.0, "z" => 1.0}
  end

  test "a joint reports how many numbers its configuration takes", %{frame: frame} do
    assert joint(frame, "ground")["degrees_of_freedom"] == 3
    assert joint(frame, "shoulder")["degrees_of_freedom"] == 1
  end

  test "the robot is named as its module, without the Elixir prefix", %{frame: frame} do
    assert read(frame)["name"] == "BB.MCP.PlanarRobot"
  end

  defp joint(frame, name) do
    frame
    |> read()
    |> Map.fetch!("joints")
    |> Enum.find(&(&1["name"] == name))
  end

  defp read(frame) do
    assert {:reply, response, ^frame} =
             RobotTopology.read(%{"params" => %{"robot" => "planar_robot"}}, frame)

    assert %{"text" => text} = response.contents

    JSON.decode!(text)
  end
end
