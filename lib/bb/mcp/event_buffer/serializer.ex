# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.MCP.EventBuffer.Serializer do
  @moduledoc """
  Convert `BB.MCP.EventBuffer` entries into JSON-safe maps for tool replies.

  BB message payloads may contain Nx tensors (Vec3, Quaternion, Transform),
  large binaries (camera images), or other non-JSON-encodable values. We
  render those via `inspect/1` rather than failing the Jason encode.
  """

  alias BB.MCP.EventBuffer

  @max_binary_bytes 64

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
      "monotonic_ns" => entry.monotonic_ns,
      "age_ms" => div(now_ns - entry.received_ns, 1_000_000),
      "payload" => jsonable(entry.message.payload)
    }
  end

  defp format_module(nil), do: nil
  defp format_module(module) when is_atom(module), do: inspect(module)

  defp format_atom(nil), do: nil
  defp format_atom(atom) when is_atom(atom), do: Atom.to_string(atom)

  defp jsonable(%Nx.Tensor{} = tensor), do: inspect(tensor)

  defp jsonable(%_{} = struct) do
    struct
    |> Map.from_struct()
    |> Map.new(fn {k, v} -> {Atom.to_string(k), jsonable(v)} end)
  end

  defp jsonable(value) when is_map(value) do
    Map.new(value, fn {k, v} -> {jsonable_key(k), jsonable(v)} end)
  end

  defp jsonable(value) when is_list(value), do: Enum.map(value, &jsonable/1)

  defp jsonable(value) when is_tuple(value),
    do: value |> Tuple.to_list() |> Enum.map(&jsonable/1)

  defp jsonable(nil), do: nil
  defp jsonable(value) when is_boolean(value), do: value
  defp jsonable(value) when is_atom(value), do: Atom.to_string(value)
  defp jsonable(value) when is_number(value), do: value
  defp jsonable(value) when is_binary(value), do: render_binary(value)
  defp jsonable(value), do: inspect(value)

  defp jsonable_key(k) when is_atom(k), do: Atom.to_string(k)
  defp jsonable_key(k) when is_binary(k), do: k
  defp jsonable_key(k), do: inspect(k)

  defp render_binary(value) do
    if String.valid?(value) and byte_size(value) <= @max_binary_bytes do
      value
    else
      "<#{byte_size(value)} bytes>"
    end
  end
end
