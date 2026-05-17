# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.MCP.Tools.SetParameter do
  @moduledoc """
  Write a single runtime parameter on a robot.

  The path is a dotted string like `"motion.max_speed"`. The value is
  passed through to `BB.Parameter.set/3`, which validates it against the
  registered schema and publishes a change notification on success.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias BB.MCP.Tools
  alias BB.Parameter

  schema do
    field(:robot, :string, required: true)
    field(:path, :string, required: true, description: "Dotted parameter path")
    field(:value, :any, required: true, description: "New parameter value")
  end

  @impl true
  def execute(params, frame) do
    path_str = Tools.get_arg(params, :path)
    value = Tools.get_arg(params, :value)

    with {:ok, robot} <- Tools.fetch_robot(params),
         path = Tools.parse_path(path_str),
         :ok <- Parameter.set(robot, path, value) do
      {:reply,
       Response.json(Response.tool(), %{"path" => path_str, "value" => value, "status" => "ok"}),
       frame}
    else
      {:error, reason} ->
        {:error, Tools.to_anubis_error(reason), frame}
    end
  end
end
