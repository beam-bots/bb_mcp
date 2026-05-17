# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.MCP.Tools.ListCommands do
  @moduledoc """
  List the commands declared on a robot, with their typed argument schemas.

  Use the returned `arguments` schemas to know what to pass to the
  `invoke_command` tool.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias BB.Dsl.Info
  alias BB.MCP.JsonSchema
  alias BB.MCP.Tools

  schema do
    field(:robot, :string, required: true)
  end

  @impl true
  def execute(params, frame) do
    case Tools.fetch_robot(params) do
      {:ok, robot} ->
        commands =
          robot
          |> Info.commands()
          |> Enum.map(fn cmd ->
            %{
              "name" => Atom.to_string(cmd.name),
              "category" => to_string(cmd.category || ""),
              "allowed_states" => Enum.map(cmd.allowed_states, &Atom.to_string/1),
              "timeout" => format_timeout(cmd.timeout),
              "arguments" => JsonSchema.for_command(cmd)
            }
          end)

        {:reply, Response.json(Response.tool(), %{"commands" => commands}), frame}

      {:error, error} ->
        {:error, error, frame}
    end
  end

  defp format_timeout(:infinity), do: "infinity"
  defp format_timeout(timeout) when is_integer(timeout), do: timeout
end
