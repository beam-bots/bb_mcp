# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.MCP.Tools.QueryEvents do
  @moduledoc """
  Query pubsub events captured by the current MCP session.

  Each session subscribes to all configured robots' pubsub trees on connect
  and records messages in a ring buffer (capacity configurable via
  `:bb_mcp, :event_buffer_size`, default 1000). This tool returns the most
  recent events, optionally filtered.

  Events arrive in real time so the agent can use this tool after invoking
  a command to inspect motion lifecycle, joint-state changes, or other
  pubsub traffic without polling the robot state.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias BB.MCP.EventBuffer
  alias BB.MCP.Tools

  schema do
    field(:robot, :string, description: "Filter to events from one robot")

    field(:message_type, :string,
      description:
        "Substring match against the payload module name (e.g. \"JointState\", " <>
          "\"BB.Command.Event\")"
    )

    field(:path_prefix, :string,
      description: "Dotted path prefix, e.g. \"sensor\" or \"command.move_to_pose\""
    )

    field(:since_ms, :integer,
      description: "Only return events received within the last N milliseconds"
    )

    field(:limit, :integer, description: "Maximum events to return (default 50)")
  end

  @impl true
  def execute(params, frame) do
    filters = build_filters(params)
    buffer = Map.get(frame.assigns, :event_buffer, EventBuffer.new())
    events = EventBuffer.query(buffer, filters)

    payload = %{
      "count" => length(events),
      "capacity" => buffer.capacity,
      "buffered" => length(buffer.events),
      "events" => events
    }

    {:reply, Response.json(Response.tool(), payload), frame}
  end

  defp build_filters(params) do
    %{
      robot: Tools.get_arg(params, :robot),
      message_type: Tools.get_arg(params, :message_type),
      path_prefix: Tools.get_arg(params, :path_prefix),
      since_ms: Tools.get_arg(params, :since_ms),
      limit: Tools.get_arg(params, :limit) || 50
    }
  end
end
