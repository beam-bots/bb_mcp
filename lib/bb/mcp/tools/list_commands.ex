# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.MCP.Tools.ListCommands do
  @moduledoc """
  List the commands declared on a robot, with their typed argument schemas.

  Each command is invokable as its own tool named `{robot}.{command}` — the
  `arguments` schema here is that tool's input schema.

  The same data is available as the `bb://robots/{robot}/commands` resource.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias BB.MCP.Tools

  schema do
    field(:robot, :string, required: true)
  end

  @impl true
  def execute(params, frame) do
    case Tools.fetch_robot(params) do
      {:ok, robot} ->
        commands = robot |> Tools.commands() |> Enum.map(&Tools.describe_command/1)

        {:reply, Response.json(Response.tool(), %{"commands" => commands}), frame}

      {:error, error} ->
        {:error, error, frame}
    end
  end
end
