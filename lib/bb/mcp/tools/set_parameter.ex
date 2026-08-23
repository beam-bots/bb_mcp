# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.MCP.Tools.SetParameter do
  @moduledoc """
  Write a single runtime parameter on a robot.

  The path is a dotted string like `"motion.max_speed"`. The value is
  passed through to `BB.Parameter.set/3`, which validates it against the
  registered schema and publishes a change notification on success.

  A parameter declared with a unit type takes an object carrying the magnitude
  and the unit name, e.g. `{"value": -12.5, "unit": "degree"}` — the same shape
  the read paths report. A bare number is also accepted and is taken to be in
  the unit the parameter declares.
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

    field(:value, :any,
      required: true,
      description:
        ~s(New parameter value. A unit-typed parameter takes either an ) <>
          ~s(object like {"value": -12.5, "unit": "degree"}, or a bare ) <>
          ~s(number in the parameter's declared unit.)
    )
  end

  @impl true
  def execute(params, frame) do
    path_str = Tools.get_arg(params, :path)

    with {:ok, robot} <- Tools.fetch_robot(params),
         path = Tools.parse_path(path_str),
         {:ok, value} <- ParameterValue.deserialise(robot, path, Tools.get_arg(params, :value)),
         :ok <- Parameter.set(robot, path, value) do
      payload = %{
        "path" => path_str,
        "value" => ParameterValue.serialise(value),
        "status" => "ok"
      }

      {:reply, Response.json(Response.tool(), payload), frame}
    else
      {:error, message} when is_binary(message) ->
        {:error, Error.protocol(:invalid_params, %{message: message}), frame}

      {:error, reason} ->
        {:error, Tools.to_anubis_error(reason), frame}
    end
  end
end
