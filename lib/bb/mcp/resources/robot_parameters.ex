# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.MCP.Resources.RobotParameters do
  @moduledoc """
  All runtime parameters registered on a robot, with their current values.

  Read via `bb://robots/{robot}/parameters`. The same data is available via the
  `list_parameters` tool, which can also filter by path prefix.

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
        payload = module |> Parameter.list() |> Enum.map(&ParameterValue.describe/1)

        {:reply, Response.json(Response.resource(), %{"parameters" => payload}), frame}

      {:error, error} ->
        {:error, error, frame}
    end
  end
end
