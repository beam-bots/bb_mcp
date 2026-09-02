# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.MCP.ToolsTest do
  use ExUnit.Case, async: false

  alias Anubis.MCP.Error
  alias Anubis.Server.Frame
  alias Anubis.Server.Response
  alias BB.Error.State.CommandCrashed
  alias BB.Error.State.NotAllowed
  alias BB.MCP.FixtureRobot
  alias BB.MCP.Tools
  alias BB.MCP.Tools.GetParameter
  alias BB.MCP.Tools.ListCommands
  alias BB.MCP.Tools.SendJointPositions
  alias BB.MCP.Tools.SetParameter
  alias BB.Message
  alias BB.Message.Sensor.JointState
  alias BB.PubSub
  alias BB.Robot.Runtime
  alias BB.Robot.State, as: RobotState
  alias BB.Safety

  setup do
    original = Application.get_env(:bb_mcp, :robots, [])

    on_exit(fn ->
      Application.put_env(:bb_mcp, :robots, original)
    end)

    :ok
  end

  describe "parse_path/1" do
    test "splits a dotted string into atoms" do
      assert Tools.parse_path("motion.max_speed") == [:motion, :max_speed]
    end

    test "handles a single segment" do
      assert Tools.parse_path("velocity") == [:velocity]
    end

    test "skips empty segments" do
      assert Tools.parse_path("a..b") == [:a, :b]
    end
  end

  describe "robots/0" do
    test "returns an empty map when no robots configured" do
      Application.put_env(:bb_mcp, :robots, [])
      assert Tools.robots() == %{}
    end

    test "builds a name → module map from configured modules" do
      Application.put_env(:bb_mcp, :robots, [MyApp.WX200, MyApp.SO101])

      assert Tools.robots() == %{
               "wx200" => MyApp.WX200,
               "so101" => MyApp.SO101
             }
    end
  end

  describe "fetch_robot/1" do
    test "resolves a known robot by name" do
      Application.put_env(:bb_mcp, :robots, [MyApp.WX200])
      assert Tools.fetch_robot(%{"robot" => "wx200"}) == {:ok, MyApp.WX200}
    end

    test "resolves a known robot from atom-keyed params" do
      Application.put_env(:bb_mcp, :robots, [MyApp.WX200])
      assert Tools.fetch_robot(%{robot: "wx200"}) == {:ok, MyApp.WX200}
    end

    test "returns an MCP error for unknown robot names" do
      Application.put_env(:bb_mcp, :robots, [MyApp.WX200])

      assert {:error, error} = Tools.fetch_robot(%{"robot" => "nope"})
      assert error.__struct__ == Anubis.MCP.Error
    end

    test "returns an MCP error when the robot argument is missing" do
      Application.put_env(:bb_mcp, :robots, [MyApp.WX200])

      assert {:error, error} = Tools.fetch_robot(%{})
      assert error.__struct__ == Anubis.MCP.Error
    end
  end

  describe "tool params after schema validation" do
    test "list_commands accepts atom-keyed params" do
      Application.put_env(:bb_mcp, :robots, [FixtureRobot])
      frame = Frame.new()

      assert {:reply, %Response{} = response, ^frame} =
               ListCommands.execute(%{robot: "fixture_robot"}, frame)

      assert [%{"text" => text, "type" => "text"}] = response.content
      assert text =~ "go_home"
    end

    test "get_parameter accepts atom-keyed params" do
      frame = Frame.new()

      assert {:error, %Error{reason: :invalid_request}, ^frame} =
               GetParameter.execute(%{robot: "nope", path: "config.foo"}, frame)
    end

    test "set_parameter accepts atom-keyed params" do
      frame = Frame.new()

      assert {:error, %Error{reason: :invalid_request}, ^frame} =
               SetParameter.execute(%{robot: "nope", path: "config.foo", value: "bar"}, frame)
    end

    test "send_joint_positions validates and sends atom-keyed params" do
      Application.put_env(:bb_mcp, :robots, [FixtureRobot])
      start_supervised!({FixtureRobot, [simulation: :kinematic]})
      :ok = Safety.arm(FixtureRobot)
      {:ok, :idle} = Runtime.transition(FixtureRobot, :idle)
      PubSub.subscribe(FixtureRobot, [:sensor, :base, :shoulder, :motor_position])

      frame = Frame.new()

      assert {:reply, %Response{} = response, ^frame} =
               SendJointPositions.execute(
                 %{robot: "fixture_robot", joint: "shoulder", position: 0.25},
                 frame
               )

      assert [%{"text" => text, "type" => "text"}] = response.content
      assert %{"positions" => %{"shoulder" => 0.25}, "status" => "ok"} = Jason.decode!(text)

      await_joint_position(:shoulder, 0.25)
    end

    test "send_joint_positions rejects invalid positions before sending" do
      Application.put_env(:bb_mcp, :robots, [FixtureRobot])
      start_supervised!({FixtureRobot, [simulation: :kinematic]})
      :ok = Safety.arm(FixtureRobot)
      {:ok, :idle} = Runtime.transition(FixtureRobot, :idle)

      frame = Frame.new()

      assert {:error, %Error{reason: :invalid_request}, ^frame} =
               SendJointPositions.execute(
                 %{robot: "fixture_robot", joint: "shoulder", position: 2.0},
                 frame
               )

      positions = FixtureRobot |> Runtime.get_robot_state() |> RobotState.get_all_configurations()
      assert positions.shoulder == 0.0
    end
  end

  describe "to_anubis_error/1" do
    test "passes Anubis errors through unchanged" do
      error = Error.protocol(:invalid_request, %{message: "nope"})
      assert Tools.to_anubis_error(error) == error
    end

    test "renders BB.Error structs with their formatted message and structured data" do
      bb_error =
        NotAllowed.exception(current_state: :armed, allowed_states: [:disarmed])

      assert %Error{reason: :execution_error, message: message, data: data} =
               Tools.to_anubis_error(bb_error)

      assert message =~ "state :armed"
      assert message =~ ":disarmed"
      assert data.current_state == "armed"
      assert data.allowed_states == ["disarmed"]
      assert data.error_type =~ "BB.Error.State.NotAllowed"
      refute Map.has_key?(data, :splode)
      refute Map.has_key?(data, :bread_crumbs)
    end

    test "renders an error field holding an exception as its message" do
      assert %Error{data: data} =
               Tools.to_anubis_error(%CommandCrashed{
                 command: MyRobot.Home,
                 exception: %RuntimeError{message: "kaboom"}
               })

      assert data.exception == "kaboom"
      assert JSON.encode!(data)
    end

    test "wraps unknown atoms and tuples via inspect" do
      assert %Error{reason: :execution_error, message: ":boom"} =
               Tools.to_anubis_error(:boom)

      assert %Error{reason: :execution_error, message: "{:weird, 1}"} =
               Tools.to_anubis_error({:weird, 1})
    end
  end

  describe "available_names/0" do
    test "lists configured names sorted, joined by commas" do
      Application.put_env(:bb_mcp, :robots, [MyApp.WX200, MyApp.SO101])
      assert Tools.available_names() == "so101, wx200"
    end

    test "reports (none configured) when empty" do
      Application.put_env(:bb_mcp, :robots, [])
      assert Tools.available_names() == "(none configured)"
    end
  end

  # `BB.Robot.State` is written from `JointState` messages and nothing else, so
  # the open-loop estimator has to interpolate the whole move before the joint
  # reads back at its target.
  defp await_joint_position(joint, expected) do
    assert_receive {:bb, _path, %Message{payload: %JointState{names: [^joint], positions: [p]}}},
                   1_000

    if p == expected do
      assert %{^joint => ^expected} =
               FixtureRobot |> Runtime.get_robot_state() |> RobotState.get_all_configurations()
    else
      await_joint_position(joint, expected)
    end
  end
end
