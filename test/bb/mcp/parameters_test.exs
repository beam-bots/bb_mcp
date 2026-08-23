# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.MCP.ParametersTest do
  use ExUnit.Case, async: false

  alias Anubis.MCP.Error
  alias Anubis.Server.Frame
  alias BB.MCP.ParameterRobot
  alias BB.MCP.Resources.RobotParameters
  alias BB.MCP.Tools.GetParameter
  alias BB.MCP.Tools.ListParameters
  alias BB.MCP.Tools.SetParameter
  alias BB.Parameter

  setup do
    original = Application.get_env(:bb_mcp, :robots, [])
    Application.put_env(:bb_mcp, :robots, [ParameterRobot])
    on_exit(fn -> Application.put_env(:bb_mcp, :robots, original) end)

    start_supervised!({ParameterRobot, [simulation: :kinematic]})

    {:ok, frame: Frame.new()}
  end

  describe "reading" do
    test "list_parameters renders unit values and defaults as magnitude and unit", %{frame: frame} do
      by_path = list(frame)

      assert by_path["motion.trim"]["value"] == %{"value" => 0, "unit" => "degree"}
      assert by_path["motion.trim"]["default"] == %{"value" => 0, "unit" => "degree"}

      assert by_path["motion.slew_rate"]["value"] ==
               %{"value" => 45, "unit" => "degree-per-second"}
    end

    test "list_parameters still reports plain-typed parameters alongside", %{frame: frame} do
      assert list(frame)["motion.max_speed"]["value"] == 1.0
    end

    test "get_parameter renders a unit value as magnitude and unit", %{frame: frame} do
      assert get(frame, "motion.trim")["value"] == %{"value" => 0, "unit" => "degree"}
    end

    test "get_parameter leaves a plain-typed value alone", %{frame: frame} do
      assert get(frame, "motion.max_speed")["value"] == 1.0
    end

    test "the parameters resource renders unit values and defaults", %{frame: frame} do
      by_path = read_resource(frame)

      assert by_path["motion.trim"]["value"] == %{"value" => 0, "unit" => "degree"}
      assert by_path["motion.trim"]["default"] == %{"value" => 0, "unit" => "degree"}
      assert by_path["motion.max_speed"]["value"] == 1.0
    end
  end

  describe "writing" do
    test "set_parameter accepts what get_parameter reports", %{frame: frame} do
      value = get(frame, "motion.trim")["value"]

      assert %{"value" => %{"value" => 12.5, "unit" => "degree"}, "status" => "ok"} =
               set(frame, "motion.trim", %{value | "value" => 12.5})

      assert Parameter.get(ParameterRobot, [:motion, :trim]) ==
               {:ok, Localize.Unit.new!(12.5, "degree")}
    end

    test "set_parameter reads a bare number in the parameter's declared unit", %{frame: frame} do
      assert %{"value" => %{"value" => -7.5, "unit" => "degree"}, "status" => "ok"} =
               set(frame, "motion.trim", -7.5)

      assert Parameter.get(ParameterRobot, [:motion, :trim]) ==
               {:ok, Localize.Unit.new!(-7.5, "degree")}
    end

    test "set_parameter round-trips a compound unit name", %{frame: frame} do
      value = get(frame, "motion.slew_rate")["value"]

      assert %{"status" => "ok"} = set(frame, "motion.slew_rate", %{value | "value" => 90})

      assert Parameter.get(ParameterRobot, [:motion, :slew_rate]) ==
               {:ok, Localize.Unit.new!(90, "degree-per-second")}
    end

    test "set_parameter leaves a plain-typed value alone", %{frame: frame} do
      assert %{"value" => 2.5, "status" => "ok"} = set(frame, "motion.max_speed", 2.5)
      assert Parameter.get(ParameterRobot, [:motion, :max_speed]) == {:ok, 2.5}
    end

    test "set_parameter reports an unparseable unit name", %{frame: frame} do
      assert {:error, %Error{reason: :invalid_params}, ^frame} =
               SetParameter.execute(
                 %{
                   "robot" => "parameter_robot",
                   "path" => "motion.trim",
                   "value" => %{"value" => 1, "unit" => "bananas"}
                 },
                 frame
               )
    end

    test "set_parameter still enforces the declared bounds", %{frame: frame} do
      assert {:error, %Error{}, ^frame} =
               SetParameter.execute(
                 %{
                   "robot" => "parameter_robot",
                   "path" => "motion.trim",
                   "value" => %{"value" => 45, "unit" => "degree"}
                 },
                 frame
               )

      assert Parameter.get(ParameterRobot, [:motion, :trim]) ==
               {:ok, Localize.Unit.new!(0, "degree")}
    end
  end

  defp list(frame) do
    assert {:reply, response, ^frame} =
             ListParameters.execute(%{"robot" => "parameter_robot"}, frame)

    response
    |> decode_tool()
    |> Map.fetch!("parameters")
    |> Map.new(fn parameter -> {parameter["path"], parameter} end)
  end

  defp get(frame, path) do
    assert {:reply, response, ^frame} =
             GetParameter.execute(%{"robot" => "parameter_robot", "path" => path}, frame)

    decode_tool(response)
  end

  defp set(frame, path, value) do
    assert {:reply, response, ^frame} =
             SetParameter.execute(
               %{"robot" => "parameter_robot", "path" => path, "value" => value},
               frame
             )

    decode_tool(response)
  end

  defp read_resource(frame) do
    assert {:reply, response, ^frame} =
             RobotParameters.read(%{"params" => %{"robot" => "parameter_robot"}}, frame)

    assert %{"text" => text} = response.contents

    text
    |> JSON.decode!()
    |> Map.fetch!("parameters")
    |> Map.new(fn parameter -> {parameter["path"], parameter} end)
  end

  defp decode_tool(response) do
    assert [%{"text" => text, "type" => "text"}] = response.content

    JSON.decode!(text)
  end
end
