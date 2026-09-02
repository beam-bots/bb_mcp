# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.MCP.ArgumentType do
  @moduledoc """
  How a BB command argument's declared type appears on the MCP wire.

  `BB.MCP.JsonSchema` advertises a command's arguments and `BB.MCP.PeriSchema`
  validates what comes back against the same command, so the two have to agree
  on the rendering exactly — a value advertised as `"gentle"` but validated as
  `:gentle` is rejected for looking like what we asked for. They share this
  module rather than each deciding for themselves.
  """

  @doc """
  Render one member of an `{:in, values}` enum as the value a client sends.

  JSON has no atoms, so an atom member travels as its name.
  """
  @spec wire_value(term()) :: term()
  def wire_value(value) when is_atom(value) and not is_boolean(value) and not is_nil(value),
    do: Atom.to_string(value)

  def wire_value(value), do: value

  @doc """
  The base type every member of an `{:in, values}` enum shares, or `:any` when
  they have none in common.
  """
  @spec enum_base([term()]) :: :integer | :float | :string | :any
  def enum_base(values) when is_list(values) do
    cond do
      Enum.all?(values, &is_integer/1) -> :integer
      Enum.all?(values, &is_number/1) -> :float
      Enum.all?(values, &is_binary/1) -> :string
      Enum.all?(values, &wire_atom?/1) -> :string
      true -> :any
    end
  end

  defp wire_atom?(value),
    do: is_atom(value) and not is_boolean(value) and not is_nil(value)
end
