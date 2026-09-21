# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.MCP.LongRunningCommandTest do
  use ExUnit.Case, async: false

  alias Anubis.Server.Frame
  alias BB.MCP.EventBuffer
  alias BB.MCP.FixtureRobot
  alias BB.MCP.Server
  alias BB.MCP.Tools.CancelCommand

  setup do
    original_robots = Application.get_env(:bb_mcp, :robots, [])
    original_grace = Application.get_env(:bb_mcp, :command_grace_period)

    Application.put_env(:bb_mcp, :robots, [FixtureRobot])
    Application.put_env(:bb_mcp, :command_grace_period, 50)

    on_exit(fn ->
      Application.put_env(:bb_mcp, :robots, original_robots)
      Application.put_env(:bb_mcp, :command_grace_period, original_grace)
    end)

    start_supervised!({FixtureRobot, [simulation: :kinematic]})
    {:ok, frame} = Server.init(%{}, Frame.new())

    {:reply, _response, frame} = Server.handle_tool_call("fixture_robot.arm", %{}, frame)

    {:ok, frame: frame}
  end

  test "a command that finishes inside the grace period replies with its result",
       %{frame: frame} do
    assert {:reply, response, _frame} =
             Server.handle_tool_call("fixture_robot.go_home", %{}, frame)

    assert %{"status" => "ok"} = decode(response)
  end

  test "a command that outlives the grace period replies with its execution id",
       %{frame: frame} do
    assert {:reply, response, _frame} =
             Server.handle_tool_call("fixture_robot.slow", %{}, frame)

    assert %{"status" => "running", "execution_id" => execution_id} = decode(response)

    assert [%{name: :slow, execution_id: id}] = BB.Command.list(FixtureRobot)
    assert BB.Command.encode_execution_id(id) == execution_id
  end

  test "the command keeps running rather than being abandoned", %{frame: frame} do
    {:reply, response, _frame} = Server.handle_tool_call("fixture_robot.slow", %{}, frame)
    %{"execution_id" => execution_id} = decode(response)

    assert is_pid(BB.Command.whereis(FixtureRobot, execution_id))
  end

  test "the execution id matches the command's query_events path segment",
       %{frame: frame} do
    {:reply, response, _frame} = Server.handle_tool_call("fixture_robot.slow", %{}, frame)
    %{"execution_id" => execution_id} = decode(response)

    assert_receive {:bb, [:command, :slow, _id] = path, _message}, 500
    assert EventBuffer.path_to_string(path) == "command.slow.#{execution_id}"
  end

  test "the execution id is accepted by cancel_command", %{frame: frame} do
    {:reply, response, frame} = Server.handle_tool_call("fixture_robot.slow", %{}, frame)
    %{"execution_id" => execution_id} = decode(response)

    assert {:reply, response, _frame} =
             CancelCommand.execute(
               %{robot: "fixture_robot", execution_id: execution_id},
               frame
             )

    assert %{"status" => "cancelled"} = decode(response)
    assert BB.Command.whereis(FixtureRobot, execution_id) == :undefined
  end

  defp decode(response) do
    [%{"text" => text}] = response.content
    Jason.decode!(text)
  end
end
