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
  alias BB.Dsl.Info
  alias BB.MCP.JsonSchema
  alias BB.MCP.Resources

  @impl true
  def description, do: "Commands declared in the robot's Spark DSL"

  @impl true
  def mime_type, do: "application/json"

  @impl true
  def read(params, frame) do
    case Resources.fetch_robot(params) do
      {:ok, module} ->
        commands =
          module
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

        {:reply, Response.json(Response.resource(), %{"commands" => commands}), frame}

      {:error, error} ->
        {:error, error, frame}
    end
  end

  defp format_timeout(:infinity), do: "infinity"
  defp format_timeout(timeout) when is_integer(timeout), do: timeout
end
