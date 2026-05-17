# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.MCP.EventBuffer do
  @moduledoc """
  Per-session ring buffer for BB pubsub events.

  Each MCP session subscribes to all configured robots' pubsub trees and
  records arriving messages in a bounded buffer that the agent can query
  via the `query_events` tool.

  The buffer is stored directly in `Anubis.Server.Frame.assigns[:event_buffer]`
  and updated on every `handle_info({:bb, path, %BB.Message{}}, frame)` call —
  no extra processes per session.
  """

  alias BB.MCP.EventBuffer.Serializer
  alias BB.Message

  @type entry :: %{
          monotonic_ns: integer(),
          wall_ns: integer(),
          received_ns: integer(),
          robot: String.t(),
          path: [atom()],
          payload_module: module(),
          message: Message.t()
        }

  @type t :: %{
          events: [entry()],
          capacity: pos_integer(),
          subscriptions: [{String.t(), module()}]
        }

  @type filters :: %{
          optional(:robot) => String.t(),
          optional(:message_type) => String.t(),
          optional(:path_prefix) => String.t(),
          optional(:since_ms) => non_neg_integer(),
          optional(:limit) => pos_integer()
        }

  @default_capacity 1000
  @default_query_limit 50

  @doc """
  Build an empty buffer with the given capacity.
  """
  @spec new(pos_integer()) :: t()
  def new(capacity \\ @default_capacity) when is_integer(capacity) and capacity > 0 do
    %{events: [], capacity: capacity, subscriptions: []}
  end

  @doc """
  Capacity sourced from `:bb_mcp` app config, falling back to the default.
  """
  @spec configured_capacity() :: pos_integer()
  def configured_capacity do
    case Application.get_env(:bb_mcp, :event_buffer_size, @default_capacity) do
      n when is_integer(n) and n > 0 -> n
      _ -> @default_capacity
    end
  end

  @doc """
  Record a subscription pair so the session can unsubscribe later.
  """
  @spec record_subscription(t(), String.t(), module()) :: t()
  def record_subscription(buffer, robot_name, robot_module) do
    %{buffer | subscriptions: [{robot_name, robot_module} | buffer.subscriptions]}
  end

  @doc """
  Append a pubsub event to the buffer, dropping the oldest entry if at capacity.
  """
  @spec push(t(), String.t(), [atom()], Message.t()) :: t()
  def push(buffer, robot_name, path, %Message{} = message)
      when is_binary(robot_name) and is_list(path) do
    entry = %{
      monotonic_ns: message.monotonic_time,
      wall_ns: message.wall_time,
      received_ns: System.monotonic_time(:nanosecond),
      robot: robot_name,
      path: path,
      payload_module: payload_module(message.payload),
      message: message
    }

    %{buffer | events: trim([entry | buffer.events], buffer.capacity)}
  end

  @doc """
  Return matching events, newest first, serialised to JSON-safe maps.
  """
  @spec query(t(), filters()) :: [map()]
  def query(buffer, filters \\ %{}) do
    now_ns = System.monotonic_time(:nanosecond)
    limit = Map.get(filters, :limit, @default_query_limit)
    cutoff_ns = since_cutoff_ns(now_ns, Map.get(filters, :since_ms))

    buffer.events
    |> Enum.filter(&matches?(&1, filters, cutoff_ns))
    |> Enum.take(limit)
    |> Enum.map(&Serializer.serialise(&1, now_ns))
  end

  defp trim(events, capacity) do
    if length(events) > capacity, do: Enum.take(events, capacity), else: events
  end

  defp payload_module(%module{}), do: module
  defp payload_module(_), do: nil

  defp since_cutoff_ns(_now, nil), do: nil
  defp since_cutoff_ns(now, ms) when is_integer(ms) and ms >= 0, do: now - ms * 1_000_000

  defp matches?(entry, filters, cutoff_ns) do
    matches_robot?(entry, filters) and
      matches_path_prefix?(entry, filters) and
      matches_message_type?(entry, filters) and
      matches_since?(entry, cutoff_ns)
  end

  defp matches_robot?(_entry, %{robot: nil}), do: true

  defp matches_robot?(entry, %{robot: robot}) when is_binary(robot),
    do: entry.robot == robot

  defp matches_robot?(_entry, _filters), do: true

  defp matches_path_prefix?(_entry, %{path_prefix: nil}), do: true

  defp matches_path_prefix?(entry, %{path_prefix: prefix}) when is_binary(prefix) do
    String.starts_with?(path_to_string(entry.path), prefix)
  end

  defp matches_path_prefix?(_entry, _filters), do: true

  defp matches_message_type?(_entry, %{message_type: nil}), do: true

  defp matches_message_type?(entry, %{message_type: needle}) when is_binary(needle) do
    case entry.payload_module do
      nil -> false
      module -> module |> inspect() |> String.contains?(needle)
    end
  end

  defp matches_message_type?(_entry, _filters), do: true

  defp matches_since?(_entry, nil), do: true
  defp matches_since?(entry, cutoff_ns), do: entry.received_ns >= cutoff_ns

  @doc false
  def path_to_string(path) when is_list(path), do: Enum.map_join(path, ".", &segment_to_string/1)

  defp segment_to_string(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp segment_to_string(binary) when is_binary(binary), do: binary
  defp segment_to_string(other), do: inspect(other)
end
