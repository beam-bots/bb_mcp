# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.MCP.Tools.CancelCommandTest do
  use ExUnit.Case, async: false

  alias Anubis.Server.Frame
  alias BB.MCP.CommandRobot
  alias BB.MCP.Tools.CancelCommand
  alias BB.MCP.Tools.GetState
  alias BB.Robot.Runtime

  setup do
    original = Application.get_env(:bb_mcp, :robots, [])
    Application.put_env(:bb_mcp, :robots, [CommandRobot])
    on_exit(fn -> Application.put_env(:bb_mcp, :robots, original) end)

    start_supervised!({CommandRobot, [simulation: :kinematic]})
    :ok = BB.Safety.arm(CommandRobot)

    {:ok, frame: Frame.new()}
  end

  test "get_state reports an execution id which cancel_command accepts", %{frame: frame} do
    {:ok, cmd} = Runtime.execute(CommandRobot, :linger, %{notify: self()})
    assert_receive {:executing, ^cmd}, 500

    %{"executing_commands" => [info]} = get_state(frame)

    assert info["name"] == "linger"
    assert info["category"] == "default"
    assert is_binary(info["execution_id"])
    assert {:ok, _, _} = DateTime.from_iso8601(info["started_at"])

    ref = Process.monitor(cmd)

    assert %{"status" => "cancelled", "execution_id" => id} =
             cancel(frame, info["execution_id"])

    assert id == info["execution_id"]
    assert_receive {:DOWN, ^ref, :process, ^cmd, {:shutdown, :cancelled}}, 500

    assert %{"executing_commands" => []} = get_state(frame)
  end

  test "cancelling a command this process did not start works", %{frame: frame} do
    test_pid = self()

    spawn(fn ->
      {:ok, cmd} = Runtime.execute(CommandRobot, :linger, %{notify: test_pid})
      send(test_pid, {:started, cmd})
    end)

    assert_receive {:started, cmd}, 500
    assert_receive {:executing, ^cmd}, 500

    %{"executing_commands" => [%{"execution_id" => execution_id}]} = get_state(frame)
    ref = Process.monitor(cmd)

    assert %{"status" => "cancelled"} = cancel(frame, execution_id)
    assert_receive {:DOWN, ^ref, :process, ^cmd, {:shutdown, :cancelled}}, 500
  end

  test "an execution id which is not running is an error", %{frame: frame} do
    assert {:error, error, ^frame} =
             CancelCommand.execute(
               %{"robot" => "command_robot", "execution_id" => "#Reference<0.0.0.0>"},
               frame
             )

    assert error.data.message =~ "no command running"
    assert error.data.message =~ "(none)"
  end

  defp get_state(frame) do
    assert {:reply, response, ^frame} = GetState.execute(%{"robot" => "command_robot"}, frame)
    decode(response)
  end

  defp cancel(frame, execution_id) do
    assert {:reply, response, ^frame} =
             CancelCommand.execute(
               %{"robot" => "command_robot", "execution_id" => execution_id},
               frame
             )

    decode(response)
  end

  defp decode(response) do
    assert [%{"text" => text}] = response.content
    Jason.decode!(text)
  end
end
