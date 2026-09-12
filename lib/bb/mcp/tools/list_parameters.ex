# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.MCP.Tools.ListParameters do
  @moduledoc """
  List the runtime parameters registered on a robot, optionally filtered
  by a path prefix.

  Returns each parameter's dotted path, current value, declared type, and the
  `min`/`max` range a write has to fall inside where the robot declares one.

  A parameter declared with a unit type reports its value and default as an
  object carrying the magnitude and the unit name, e.g.
  `{"value": -12.5, "unit": "degree"}`. That object is exactly what
  `set_parameter` accepts for the same parameter.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias BB.MCP.ParameterValue
  alias BB.MCP.Tools
  alias BB.Parameter

  schema do
    field(:robot, :string, required: true)

    field(:prefix, :string,
      required: false,
      description: "Dotted path prefix to filter by (e.g. \"controller.pid\")"
    )
  end

  @impl true
  def execute(params, frame) do
    case Tools.fetch_robot(params) do
      {:ok, robot} ->
        {:reply, Response.json(Response.tool(), list(robot, params)), frame}

      {:error, error} ->
        {:error, error, frame}
    end
  end

  defp list(robot, params) do
    case parse_prefix(Tools.get_arg(params, :prefix)) do
      {:ok, prefix} ->
        %{
          "parameters" =>
            robot |> Parameter.list(prefix: prefix) |> Enum.map(&ParameterValue.describe/1)
        }

      # A prefix naming a segment that was never interned cannot match a
      # registered parameter, so it filters everything out rather than erroring.
      :error ->
        %{"parameters" => []}
    end
  end

  defp parse_prefix(nil), do: {:ok, []}
  defp parse_prefix(""), do: {:ok, []}
  defp parse_prefix(prefix) when is_binary(prefix), do: Tools.parse_path(prefix)
end
