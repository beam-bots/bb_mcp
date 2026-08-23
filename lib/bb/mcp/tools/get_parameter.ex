# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.MCP.Tools.GetParameter do
  @moduledoc """
  Read a single runtime parameter from a robot.

  The path is a dotted string like `"motion.max_speed"`.

  A parameter declared with a unit type reports its value as an object
  carrying the magnitude and the unit name, e.g.
  `{"value": -12.5, "unit": "degree"}`. That object is exactly what
  `set_parameter` accepts for the same parameter.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.MCP.Error
  alias Anubis.Server.Response
  alias BB.MCP.ParameterValue
  alias BB.MCP.Tools
  alias BB.Parameter

  schema do
    field(:robot, :string, required: true)
    field(:path, :string, required: true, description: "Dotted parameter path")
  end

  @impl true
  def execute(params, frame) do
    path_str = Tools.get_arg(params, :path)

    with {:ok, robot} <- Tools.fetch_robot(params),
         path = Tools.parse_path(path_str),
         {:ok, value} <- Parameter.get(robot, path) do
      payload = %{"path" => path_str, "value" => ParameterValue.serialise(value)}
      {:reply, Response.json(Response.tool(), payload), frame}
    else
      {:error, :not_found} ->
        {:error, Error.resource(:not_found, %{message: "parameter not found: #{path_str}"}),
         frame}

      {:error, reason} ->
        {:error, Tools.to_anubis_error(reason), frame}
    end
  end
end
