# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.MCP.Resources.RobotIndex do
  @moduledoc """
  Index of all configured robots exposed by this MCP server.

  Read via the URI `bb://robots`. Returns each robot's name and module.
  """

  use Anubis.Server.Component, type: :resource, name: "robot_index"

  alias Anubis.Server.Response
  alias BB.MCP.Robots
  alias BB.MCP.Tools

  @impl true
  def uri, do: "bb://robots"

  @impl true
  def description, do: "List of robots configured on this MCP server"

  @impl true
  def mime_type, do: "application/json"

  @impl true
  def read(_params, frame) do
    payload =
      Tools.robots()
      |> Robots.to_list()
      |> Enum.map(fn {name, module} ->
        %{"name" => name, "module" => inspect(module)}
      end)

    {:reply, Response.json(Response.resource(), %{"robots" => payload}), frame}
  end
end
