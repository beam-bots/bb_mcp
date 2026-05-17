# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.MCP.Robots do
  @moduledoc """
  Resolves between agent-facing robot name strings and robot modules.

  Robot names are derived from the last segment of the module name, lowercased.

      MyApp.WX200    -> "wx200"
      MyApp.SO101    -> "so101"
      MyApp.Robot    -> "robot"
      MyApp.Two.Word -> "two_word" (only when the segment is itself camel-cased,
                                    e.g. `MyApp.TwoWord` -> "two_word")
  """

  @type config :: %{required(String.t()) => module()}

  @doc """
  Build a name → module map from a list of robot modules, raising on collisions.
  """
  @spec build!([module()]) :: config()
  def build!(modules) when is_list(modules) do
    Enum.reduce(modules, %{}, fn module, acc ->
      name = name_for(module)

      case Map.fetch(acc, name) do
        {:ok, other} when other != module ->
          raise ArgumentError,
                "bb_mcp: robot name collision on #{inspect(name)} between " <>
                  "#{inspect(other)} and #{inspect(module)}"

        _ ->
          Map.put(acc, name, module)
      end
    end)
  end

  @doc """
  The agent-facing name for a robot module.
  """
  @spec name_for(module()) :: String.t()
  def name_for(module) when is_atom(module) do
    module
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
  end

  @doc """
  Look up a robot module by name. Returns `{:ok, module}` or `{:error, :unknown_robot}`.
  """
  @spec fetch(config(), String.t()) :: {:ok, module()} | {:error, :unknown_robot}
  def fetch(config, name) when is_binary(name) do
    case Map.fetch(config, name) do
      {:ok, module} -> {:ok, module}
      :error -> {:error, :unknown_robot}
    end
  end

  @doc """
  List all configured robots as `{name, module}` tuples, sorted by name.
  """
  @spec to_list(config()) :: [{String.t(), module()}]
  def to_list(config), do: config |> Map.to_list() |> Enum.sort()
end
