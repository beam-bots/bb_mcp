# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.MCP.Resources.RobotCommandsTest do
  use ExUnit.Case, async: false

  alias Anubis.Server.Frame
  alias BB.MCP.FixtureRobot
  alias BB.MCP.Resources.RobotCommands
  alias BB.MCP.Tools

  setup do
    original = Application.get_env(:bb_mcp, :robots, [])
    Application.put_env(:bb_mcp, :robots, [FixtureRobot])
    on_exit(fn -> Application.put_env(:bb_mcp, :robots, original) end)

    {:ok, frame: Frame.new()}
  end

  # The DSL's `commands` section holds categories alongside commands, and
  # `BB.Dsl.Info.commands/1` hands back both.
  test "the robot's declared category is not mistaken for a command", %{frame: frame} do
    names = frame |> read() |> Enum.map(& &1["name"])

    assert "go_home" in names
    refute "motion" in names
  end

  test "reports the category a command runs in", %{frame: frame} do
    assert command(frame, "go_home")["category"] == "motion"
    assert command(frame, "wave")["category"] == "default"
  end

  test "reports whether a command is the robot's arming or disarming command",
       %{frame: frame} do
    assert command(frame, "arm")["arms"] == true
    assert command(frame, "disarm")["disarms"] == true
    assert command(frame, "wave")["arms"] == false
  end

  test "Tools.commands/1 returns only commands" do
    assert Enum.all?(Tools.commands(FixtureRobot), &is_struct(&1, BB.Dsl.Command))
  end

  defp command(frame, name) do
    frame |> read() |> Enum.find(&(&1["name"] == name))
  end

  defp read(frame) do
    assert {:reply, response, ^frame} =
             RobotCommands.read(%{"params" => %{"robot" => "fixture_robot"}}, frame)

    assert %{"text" => text} = response.contents

    text |> JSON.decode!() |> Map.fetch!("commands")
  end
end
