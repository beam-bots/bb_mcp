# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.MCP.EventBufferTest do
  use ExUnit.Case, async: true

  alias BB.Command.Event, as: CommandEvent
  alias BB.MCP.EventBuffer
  alias BB.Message

  defp event_message(status, data \\ %{}) do
    %Message{
      monotonic_time: System.monotonic_time(:nanosecond),
      wall_time: System.system_time(:nanosecond),
      node: Node.self(),
      frame_id: :base_link,
      payload: %CommandEvent{status: status, data: data}
    }
  end

  describe "new/1 and configured_capacity/0" do
    test "creates an empty buffer at the requested capacity" do
      assert EventBuffer.new(7) == %{events: [], capacity: 7, subscriptions: []}
    end

    test "configured_capacity falls back to the default when missing" do
      Application.delete_env(:bb_mcp, :event_buffer_size)
      assert EventBuffer.configured_capacity() == 1000
    end

    test "configured_capacity reads from app env" do
      Application.put_env(:bb_mcp, :event_buffer_size, 42)
      on_exit(fn -> Application.delete_env(:bb_mcp, :event_buffer_size) end)
      assert EventBuffer.configured_capacity() == 42
    end

    test "configured_capacity rejects nonsense values" do
      Application.put_env(:bb_mcp, :event_buffer_size, :bogus)
      on_exit(fn -> Application.delete_env(:bb_mcp, :event_buffer_size) end)
      assert EventBuffer.configured_capacity() == 1000
    end
  end

  describe "push/4" do
    test "prepends the entry and tracks the payload module" do
      buffer =
        EventBuffer.new(10)
        |> EventBuffer.push("robot", [:command, :home], event_message(:started))

      assert [entry] = buffer.events
      assert entry.robot == "robot"
      assert entry.path == [:command, :home]
      assert entry.payload_module == CommandEvent
    end

    test "drops the oldest entry when capacity is exceeded" do
      buffer = EventBuffer.new(2)

      buffer =
        Enum.reduce(1..5, buffer, fn n, acc ->
          EventBuffer.push(acc, "robot", [:command, :"c#{n}"], event_message(:started))
        end)

      paths = Enum.map(buffer.events, & &1.path)
      assert paths == [[:command, :c5], [:command, :c4]]
    end
  end

  describe "query/2 filtering" do
    setup do
      buffer =
        EventBuffer.new(100)
        |> EventBuffer.push("r1", [:sensor, :base_link], event_message(:started))
        |> EventBuffer.push("r1", [:command, :home], event_message(:started))
        |> EventBuffer.push("r2", [:command, :move_to_pose], event_message(:succeeded))

      {:ok, buffer: buffer}
    end

    test "no filters returns everything, newest first", %{buffer: buf} do
      events = EventBuffer.query(buf, %{})
      assert length(events) == 3
      assert [first | _] = events
      assert first["path"] == "command.move_to_pose"
    end

    test "filters by robot", %{buffer: buf} do
      events = EventBuffer.query(buf, %{robot: "r1"})
      assert length(events) == 2
      assert Enum.all?(events, &(&1["robot"] == "r1"))
    end

    test "filters by path prefix", %{buffer: buf} do
      events = EventBuffer.query(buf, %{path_prefix: "command"})
      paths = Enum.map(events, & &1["path"])
      assert "command.home" in paths
      assert "command.move_to_pose" in paths
      refute "sensor.base_link" in paths
    end

    test "filters by message type substring", %{buffer: buf} do
      assert [_, _, _] = EventBuffer.query(buf, %{message_type: "Event"})
      assert [] = EventBuffer.query(buf, %{message_type: "Imu"})
    end

    test "applies the limit", %{buffer: buf} do
      assert [_] = EventBuffer.query(buf, %{limit: 1})
    end

    test "since_ms cuts events older than the window" do
      buffer = EventBuffer.new(10)

      buffer = EventBuffer.push(buffer, "r1", [:command, :home], event_message(:started))

      # Force the stored entry to look old
      [entry] = buffer.events

      stale_buffer = %{
        buffer
        | events: [%{entry | received_ns: entry.received_ns - 5_000_000_000}]
      }

      assert [] = EventBuffer.query(stale_buffer, %{since_ms: 1_000})
      assert [_] = EventBuffer.query(stale_buffer, %{since_ms: 10_000_000})
    end
  end

  describe "Serializer rendering" do
    test "non-encodable values fall back to inspect" do
      msg = %Message{
        monotonic_time: 100,
        wall_time: 1_700_000_000_000_000_000,
        node: Node.self(),
        frame_id: :base_link,
        payload: %CommandEvent{
          status: :failed,
          data: %{tensor: Nx.tensor([1.0, 2.0, 3.0]), binary: <<255, 254>>}
        }
      }

      buffer =
        EventBuffer.new(10)
        |> EventBuffer.push("robot", [:command, :home], msg)

      [entry] = EventBuffer.query(buffer, %{})
      assert entry["type"] =~ "BB.Command.Event"
      assert entry["payload"]["status"] == "failed"
      assert is_binary(entry["payload"]["data"]["tensor"])
      assert entry["payload"]["data"]["binary"] =~ "bytes"
    end

    test "renders wall_time as an ISO-8601 string" do
      msg = %Message{
        monotonic_time: 0,
        wall_time: 1_700_000_000_000_000_000,
        node: Node.self(),
        frame_id: :base_link,
        payload: %CommandEvent{status: :started, data: %{}}
      }

      buffer =
        EventBuffer.new(10)
        |> EventBuffer.push("robot", [:command, :home], msg)

      [entry] = EventBuffer.query(buffer, %{})
      assert entry["wall_time"] == "2023-11-14T22:13:20.000000Z"
    end
  end
end
