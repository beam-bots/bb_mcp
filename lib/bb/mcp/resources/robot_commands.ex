# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.MCP.Resources.RobotCommands do
  @moduledoc """
  Declared commands on a robot, with typed argument schemas.

  Read via `bb://robots/{robot}/commands`. The same data is available
  via the `list_commands` tool — this resource exists so agents can
  load the command catalogue as context before invoking anything.
  """

  use Anubis.Server.Component,
    type: :resource,
    uri_template: "bb://robots/{robot}/commands",
    name: "robot_commands"

  alias Anubis.Server.Response
  alias BB.MCP.Resources
  alias BB.MCP.Tools

  @impl true
  def description, do: "Commands declared in the robot's Spark DSL"

  @impl true
  def mime_type, do: "application/json"

  @impl true
  def read(params, frame) do
    case Resources.fetch_robot(params) do
      {:ok, module} ->
        commands = module |> Tools.commands() |> Enum.map(&Tools.describe_command/1)

        {:reply, Response.json(Response.resource(), %{"commands" => commands}), frame}

      {:error, error} ->
        {:error, error, frame}
    end
  end
end
