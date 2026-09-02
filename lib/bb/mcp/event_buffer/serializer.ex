# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.MCP.EventBuffer.Serializer do
  @moduledoc """
  Convert `BB.MCP.EventBuffer` entries into JSON-safe maps for tool replies.

  Message payloads are rendered by `BB.MCP.Json.encodable/1`, which handles the
  tensors, binaries and other non-JSON values BB messages carry.
  """

  alias BB.MCP.EventBuffer
  alias BB.MCP.Json

  @doc """
  Serialise a buffer entry. `now_ns` is the reference monotonic time used to
  compute `age_ms`, so the agent can reason about how recent each event is.
  """
  @spec serialise(EventBuffer.entry(), integer()) :: map()
  def serialise(entry, now_ns) do
    %{
      "robot" => entry.robot,
      "path" => EventBuffer.path_to_string(entry.path),
      "type" => format_module(entry.payload_module),
      "frame_id" => format_atom(entry.message.frame_id),
      "wall_time" => format_wall_time(entry.wall_ns),
      "age_ms" => div(now_ns - entry.received_ns, 1_000_000),
      "payload" => Json.encodable(entry.message.payload)
    }
  end

  defp format_wall_time(ns) when is_integer(ns) do
    ns
    |> DateTime.from_unix!(:nanosecond)
    |> DateTime.to_iso8601()
  end

  defp format_module(nil), do: nil
  defp format_module(module) when is_atom(module), do: inspect(module)

  defp format_atom(nil), do: nil
  defp format_atom(atom) when is_atom(atom), do: Atom.to_string(atom)
end
