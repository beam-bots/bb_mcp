# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.MCP.ParameterValue do
  @moduledoc """
  Translate parameter values across the MCP boundary.

  Most parameter types are JSON scalars already, but a `{:unit, _}` parameter
  holds a `Localize.Unit` struct, which `JSON.encode!/1` cannot encode. Unit
  values travel as a tagged object carrying the magnitude and the CLDR unit
  name:

      %{"value" => -12.5, "unit" => "degree"}

  The tag makes the value self-describing, so a client can write back exactly
  what it read from `list_parameters`, `get_parameter` or the parameters
  resource without having to interpret the declared type. Writes also accept a
  bare number for a unit-typed parameter, which is given the unit declared in
  the robot's parameter schema.
  """

  alias BB.Parameter
  alias BB.Unit

  @doc """
  Describe one `BB.Parameter.list/2` entry for the parameter tools and resource.

  `min` and `max` come from the parameter's declared type, so an agent can see
  the range a write has to fall inside before `set_parameter` rejects it. Keys
  the robot didn't declare are left out rather than sent as null.
  """
  @spec describe({[atom()], term()}) :: map()
  def describe({path, metadata}) when is_map(metadata) do
    %{
      "path" => format_path(path),
      "value" => metadata |> Map.get(:value) |> serialise(),
      "type" => metadata |> Map.get(:type) |> format_type(),
      "doc" => Map.get(metadata, :doc),
      "default" => metadata |> Map.get(:default) |> serialise(),
      "min" => metadata |> Map.get(:min) |> serialise(),
      "max" => metadata |> Map.get(:max) |> serialise()
    }
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end

  def describe({path, value}) do
    %{"path" => format_path(path), "value" => serialise(value)}
  end

  @doc """
  Render a parameter value as a term `JSON.encode!/1` can carry.
  """
  @spec serialise(term()) :: term()
  def serialise(%Localize.Unit{name: name, value: value}),
    do: %{"value" => value, "unit" => name}

  def serialise(value), do: value

  @doc """
  Rebuild a parameter value from the JSON a client sent, ready for
  `BB.Parameter.set/3`.

  Returns `{:error, message}` when a tagged object names a unit which cannot be
  parsed.
  """
  @spec deserialise(module(), [atom()], term()) :: {:ok, term()} | {:error, String.t()}
  def deserialise(_robot, _path, %{"value" => magnitude, "unit" => unit})
      when is_number(magnitude) and is_binary(unit),
      do: build_unit(magnitude, unit)

  def deserialise(robot, path, magnitude) when is_number(magnitude) do
    case declared_unit(robot, path) do
      {:ok, unit} -> build_unit(magnitude, unit)
      :error -> {:ok, magnitude}
    end
  end

  def deserialise(_robot, _path, value), do: {:ok, value}

  defp format_path(path), do: Enum.map_join(path, ".", &Atom.to_string/1)

  defp format_type(nil), do: nil
  defp format_type(type), do: inspect(type)

  defp build_unit(magnitude, unit) do
    case Localize.Unit.new(magnitude, Unit.unit_name(unit)) do
      {:ok, unit} -> {:ok, unit}
      {:error, exception} -> {:error, Exception.message(exception)}
    end
  end

  defp declared_unit(robot, path) do
    robot
    |> Parameter.list(prefix: path)
    |> Enum.find_value(:error, fn
      {^path, %{type: {:unit, unit}}} -> {:ok, unit}
      _entry -> nil
    end)
  end
end
