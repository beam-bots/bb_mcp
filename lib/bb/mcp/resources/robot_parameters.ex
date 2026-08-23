# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.MCP.Resources.RobotParameters do
  @moduledoc """
  All runtime parameters registered on a robot, with their current values.

  Read via `bb://robots/{robot}/parameters`.

  A parameter declared with a unit type reports its value and default as an
  object carrying the magnitude and the unit name, e.g.
  `{"value": -12.5, "unit": "degree"}`. That object is exactly what the
  `set_parameter` tool accepts for the same parameter.
  """

  use Anubis.Server.Component,
    type: :resource,
    uri_template: "bb://robots/{robot}/parameters",
    name: "robot_parameters"

  alias Anubis.Server.Response
  alias BB.MCP.ParameterValue
  alias BB.MCP.Resources
  alias BB.Parameter

  @impl true
  def description, do: "All registered runtime parameters with current values"

  @impl true
  def mime_type, do: "application/json"

  @impl true
  def read(params, frame) do
    case Resources.fetch_robot(params) do
      {:ok, module} ->
        payload =
          module
          |> Parameter.list()
          |> Enum.map(&format_parameter/1)

        {:reply, Response.json(Response.resource(), %{"parameters" => payload}), frame}

      {:error, error} ->
        {:error, error, frame}
    end
  end

  defp format_parameter({path, metadata}) when is_map(metadata) do
    base = %{
      "path" => format_path(path),
      "value" => metadata |> Map.get(:value) |> serialise()
    }

    Enum.reduce([:type, :doc, :default, :required], base, fn key, acc ->
      case Map.get(metadata, key) do
        nil -> acc
        value -> Map.put(acc, Atom.to_string(key), serialise(value))
      end
    end)
  end

  defp format_parameter({path, value}) do
    %{"path" => format_path(path), "value" => serialise(value)}
  end

  defp format_path(path), do: Enum.map_join(path, ".", &Atom.to_string/1)

  defp serialise(value) when is_atom(value) and not is_boolean(value) and not is_nil(value),
    do: Atom.to_string(value)

  defp serialise(value) when is_tuple(value), do: inspect(value)
  defp serialise(value), do: ParameterValue.serialise(value)
end
