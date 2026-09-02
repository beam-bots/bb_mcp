# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.MCP.Resources.RobotParametersTest do
  use ExUnit.Case, async: false

  alias Anubis.Server.Frame
  alias BB.MCP.ParameterRobot
  alias BB.MCP.Resources.RobotParameters
  alias BB.MCP.Tools.ListParameters

  setup do
    original = Application.get_env(:bb_mcp, :robots, [])
    Application.put_env(:bb_mcp, :robots, [ParameterRobot])
    on_exit(fn -> Application.put_env(:bb_mcp, :robots, original) end)

    start_supervised!({ParameterRobot, [simulation: :kinematic]})

    {:ok, frame: Frame.new()}
  end

  test "reports the range a write has to fall inside", %{frame: frame} do
    max_speed = parameter(frame, "motion.max_speed")

    assert max_speed["min"] == 0.0
    assert max_speed["max"] == 10.0
  end

  test "a unit-typed parameter's range carries its unit", %{frame: frame} do
    trim = parameter(frame, "motion.trim")

    assert trim["min"] == %{"value" => -30, "unit" => "degree"}
    assert trim["max"] == %{"value" => 30, "unit" => "degree"}
  end

  test "a parameter with no declared range carries no min or max", %{frame: frame} do
    slew_rate = parameter(frame, "motion.slew_rate")

    refute Map.has_key?(slew_rate, "min")
    refute Map.has_key?(slew_rate, "max")
  end

  test "the list_parameters tool answers with the same shape as the resource",
       %{frame: frame} do
    assert {:reply, response, ^frame} =
             ListParameters.execute(%{robot: "parameter_robot"}, frame)

    from_tool = response.content |> hd() |> Map.fetch!("text") |> JSON.decode!()

    assert from_tool == %{"parameters" => read(frame)}
  end

  test "a prefix naming a segment that is not an atom matches nothing", %{frame: frame} do
    unknown = "motion.#{System.unique_integer([:positive])}"

    assert {:reply, response, ^frame} =
             ListParameters.execute(%{robot: "parameter_robot", prefix: unknown}, frame)

    assert response.content |> hd() |> Map.fetch!("text") |> JSON.decode!() ==
             %{"parameters" => []}
  end

  defp parameter(frame, path) do
    frame |> read() |> Enum.find(&(&1["path"] == path))
  end

  defp read(frame) do
    assert {:reply, response, ^frame} =
             RobotParameters.read(%{"params" => %{"robot" => "parameter_robot"}}, frame)

    assert %{"text" => text} = response.contents

    text |> JSON.decode!() |> Map.fetch!("parameters")
  end
end
