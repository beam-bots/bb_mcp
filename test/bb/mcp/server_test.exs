# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.MCP.ServerTest do
  use ExUnit.Case, async: false

  alias Anubis.MCP.Error
  alias Anubis.Server.Frame
  alias BB.Command.Event, as: CommandEvent
  alias BB.MCP.FixtureRobot
  alias BB.MCP.Server
  alias BB.MCP.Tools.QueryEvents
  alias BB.Message

  setup do
    original = Application.get_env(:bb_mcp, :robots, [])
    Application.put_env(:bb_mcp, :robots, [FixtureRobot])

    on_exit(fn -> Application.put_env(:bb_mcp, :robots, original) end)

    {:ok, frame: Frame.new()}
  end

  describe "init/2" do
    test "registers one tool per declared command on each configured robot",
         %{frame: frame} do
      {:ok, frame} = Server.init(%{}, frame)

      registered = Map.keys(frame.tools) |> Enum.sort()

      assert "fixture_robot.arm" in registered
      assert "fixture_robot.disarm" in registered
      assert "fixture_robot.go_home" in registered
      assert "fixture_robot.wave" in registered
    end

    test "each per-command tool carries the command's argument schema as JSON",
         %{frame: frame} do
      {:ok, frame} = Server.init(%{}, frame)
      tool = Map.fetch!(frame.tools, "fixture_robot.wave")

      props = tool.input_schema["properties"]
      assert props["cycles"]["type"] == "integer"
      assert props["cycles"]["description"] == "Number of cycles"
      assert props["speed"]["type"] == "number"
      assert "cycles" in tool.input_schema["required"]
      refute Enum.member?(tool.input_schema["required"] || [], "speed")
    end

    test "describes the tool so agents see allowed states", %{frame: frame} do
      {:ok, frame} = Server.init(%{}, frame)
      tool = Map.fetch!(frame.tools, "fixture_robot.go_home")

      assert tool.description =~ "go_home"
      assert tool.description =~ "fixture_robot"
      assert tool.description =~ "idle"
    end

    test "leaves the frame's other registries (resources, prompts) alone",
         %{frame: frame} do
      {:ok, new_frame} = Server.init(%{}, frame)

      assert new_frame.resources == %{}
      assert new_frame.prompts == %{}
    end
  end

  describe "handle_tool_call/3" do
    test "returns method_not_found for an unparseable tool name", %{frame: frame} do
      assert {:error, %Error{} = error, ^frame} =
               Server.handle_tool_call("not_a_command_tool", %{}, frame)

      assert error.reason == :method_not_found
    end

    test "returns invalid_request for a known shape with an unknown robot",
         %{frame: frame} do
      assert {:error, %Error{} = error, ^frame} =
               Server.handle_tool_call("nope.arm", %{}, frame)

      assert error.reason == :invalid_request
    end
  end

  describe "event buffer lifecycle" do
    test "init/2 subscribes to each configured robot and seeds an empty buffer",
         %{frame: frame} do
      start_supervised!({FixtureRobot, [simulation: :kinematic]})

      {:ok, frame} = Server.init(%{}, frame)

      buffer = Map.fetch!(frame.assigns, :event_buffer)
      assert buffer.events == []
      assert [{"fixture_robot", FixtureRobot}] = buffer.subscriptions
    end

    test "handle_info/2 appends an incoming BB pubsub event to the buffer",
         %{frame: frame} do
      start_supervised!({FixtureRobot, [simulation: :kinematic]})
      {:ok, frame} = Server.init(%{}, frame)

      message = %Message{
        monotonic_time: 123,
        wall_time: 1_700_000_000_000_000_000,
        node: Node.self(),
        frame_id: :base_link,
        payload: %CommandEvent{status: :started, data: %{}}
      }

      assert {:noreply, frame} =
               Server.handle_info({:bb, [:command, :go_home, "exec-1"], message}, frame)

      buffer = frame.assigns.event_buffer
      assert [entry] = buffer.events
      assert entry.path == [:command, :go_home, "exec-1"]
      assert entry.payload_module == CommandEvent
    end

    test "query_events tool returns the buffered events", %{frame: frame} do
      start_supervised!({FixtureRobot, [simulation: :kinematic]})
      {:ok, frame} = Server.init(%{}, frame)

      message = %Message{
        monotonic_time: 1,
        wall_time: 1_700_000_000_000_000_000,
        node: Node.self(),
        frame_id: :base_link,
        payload: %CommandEvent{status: :succeeded, data: %{}}
      }

      {:noreply, frame} =
        Server.handle_info({:bb, [:command, :go_home, "x"], message}, frame)

      assert {:reply, response, _frame} =
               QueryEvents.execute(%{message_type: "Event"}, frame)

      assert [%{"text" => text}] = response.content
      assert %{"count" => 1, "events" => [event]} = Jason.decode!(text)
      assert event["type"] =~ "BB.Command.Event"
      assert event["payload"]["status"] == "succeeded"
    end

    test "handle_info ignores unrelated messages", %{frame: frame} do
      assert {:noreply, ^frame} = Server.handle_info(:something_else, frame)
    end
  end
end
