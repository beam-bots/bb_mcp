# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.MCP.Resources.RobotStateTest do
  use ExUnit.Case, async: false

  alias Anubis.Server.Frame
  alias BB.MCP.Resources.RobotState
  alias BB.MCP.SlowRobot
  alias BB.MCP.Tools.GetState
  alias BB.Robot.Runtime
  alias BB.Safety

  setup do
    original = Application.get_env(:bb_mcp, :robots, [])
    Application.put_env(:bb_mcp, :robots, [SlowRobot])
    on_exit(fn -> Application.put_env(:bb_mcp, :robots, original) end)

    start_supervised!({SlowRobot, [simulation: true]})

    {:ok, frame: Frame.new()}
  end

  test "reports the safety and operational state of an idle robot", %{frame: frame} do
    payload = read(frame)

    assert payload["safety_state"] == "disarmed"
    assert payload["operational_state"] == "idle"
    assert payload["executing"] == false
    assert payload["executing_commands"] == []
  end

  # `BB.Robot.Runtime.executing_commands/1` reports each execution id as a
  # `reference()`, which JSON has no encoding for.
  test "encodes an executing command, whose execution id is a reference",
       %{frame: frame} do
    :ok = Safety.arm(SlowRobot)
    {:ok, _pid} = Runtime.execute(SlowRobot, :slow, %{})

    payload = read(frame)

    assert payload["executing"] == true
    assert [command] = payload["executing_commands"]
    assert command["name"] == "slow"
    assert command["category"] == "default"
    assert is_binary(command["execution_id"])
    assert is_binary(command["pid"])
    assert {:ok, _, _} = DateTime.from_iso8601(command["started_at"])
  end

  test "the get_state tool answers with the same fields as the resource", %{frame: frame} do
    :ok = Safety.arm(SlowRobot)
    {:ok, _pid} = Runtime.execute(SlowRobot, :slow, %{})

    assert {:reply, response, ^frame} = GetState.execute(%{robot: "slow_robot"}, frame)
    assert %{"text" => text} = response.content |> hd()

    from_tool = text |> JSON.decode!() |> Map.delete("robot")

    assert Map.keys(from_tool) == Map.keys(read(frame))
  end

  defp read(frame) do
    assert {:reply, response, ^frame} =
             RobotState.read(%{"params" => %{"robot" => "slow_robot"}}, frame)

    assert %{"text" => text} = response.contents

    JSON.decode!(text)
  end
end
