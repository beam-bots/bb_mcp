# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.MCP.Json do
  @moduledoc """
  Render arbitrary BB terms as something `JSON.encode!/1` can carry.

  BB is full of values JSON has no equivalent for: `Nx` tensors behind
  `BB.Math.Vec3` and friends, `reference()` execution ids, pids, exception
  structs inside `BB.Error` payloads, and camera frames as raw binaries. Every
  MCP reply is encoded eagerly by `Anubis.Server.Response.json/3`, so a single
  un-encodable value anywhere in a payload fails the whole reply rather than
  degrading that one field.

  `encodable/1` walks a term and leaves only maps, lists, strings, numbers,
  booleans and `nil` behind, falling back to `inspect/1` for anything it has no
  better rendering for.
  """

  alias BB.MCP.ParameterValue

  @max_binary_bytes 64

  @doc """
  Convert a term into one `JSON.encode!/1` accepts.

  Atoms become bare strings without the leading colon, since an agent reading
  `"idle"` has no use for Elixir's atom syntax; a module atom is rendered the
  way it was written, without its `Elixir.` prefix. Tuples become lists, and
  binaries too long or too binary to read become a byte count.

  A struct that already implements `JSON.Encoder` — a `DateTime`, say — is
  handed straight through so it keeps its own rendering. Anything else becomes
  an object of its fields.
  """
  @spec encodable(term()) :: term()
  def encodable(nil), do: nil
  def encodable(value) when is_boolean(value), do: value
  def encodable(value) when is_number(value), do: value
  def encodable(value) when is_atom(value), do: atom_to_string(value)
  def encodable(value) when is_binary(value), do: render_binary(value)

  def encodable(%Nx.Tensor{} = tensor), do: inspect(tensor)

  def encodable(%Localize.Unit{} = unit), do: ParameterValue.serialise(unit)

  def encodable(error) when is_exception(error), do: message_for(error)

  def encodable(%_{} = struct) do
    if JSON.Encoder.impl_for(struct) do
      struct
    else
      struct |> Map.from_struct() |> encodable()
    end
  end

  def encodable(value) when is_map(value) do
    Map.new(value, fn {key, val} -> {key_for(key), encodable(val)} end)
  end

  def encodable(value) when is_list(value), do: Enum.map(value, &encodable/1)

  def encodable(value) when is_tuple(value),
    do: value |> Tuple.to_list() |> encodable()

  def encodable(value), do: inspect(value)

  # `Atom.to_string/1` on a module gives back the `Elixir.`-prefixed form the
  # compiler uses rather than the name anyone writes or reads.
  defp atom_to_string(value) do
    case Atom.to_string(value) do
      "Elixir." <> _rest -> inspect(value)
      string -> string
    end
  end

  defp message_for(error) do
    Exception.message(error)
  rescue
    _ -> inspect(error)
  end

  defp key_for(key) when is_atom(key), do: atom_to_string(key)
  defp key_for(key) when is_binary(key), do: key
  defp key_for(key), do: inspect(key)

  defp render_binary(value) do
    if String.valid?(value) and byte_size(value) <= @max_binary_bytes do
      value
    else
      "<#{byte_size(value)} bytes>"
    end
  end
end
