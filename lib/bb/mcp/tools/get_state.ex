# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.MCP.Tools.GetState do
  @moduledoc """
  Get the current operational and safety state of a robot.

  Returns the safety state (`:armed | :disarmed | :disarming | :error`),
  the operational state (e.g. `:idle`, `:executing`), and the list of
  currently executing commands. Each command carries an `execution_id` that
  `cancel_command` accepts.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias BB.MCP.Tools
  alias BB.Robot.Runtime
  alias BB.Safety

  schema do
    field(:robot, :string, required: true)
  end

  @impl true
  def execute(params, frame) do
    case Tools.fetch_robot(params) do
      {:ok, robot} ->
        payload = %{
          "robot" => Tools.get_arg(params, :robot),
          "safety_state" => Safety.state(robot),
          "operational_state" => Runtime.operational_state(robot),
          "executing" => Runtime.executing?(robot),
          "executing_commands" => Enum.map(Runtime.executing_commands(robot), &command_info/1)
        }

        {:reply, Response.json(Response.tool(), payload), frame}

      {:error, error} ->
        {:error, error, frame}
    end
  end

  defp command_info(%{name: name, execution_id: execution_id} = info) do
    %{
      "name" => to_string(name),
      "execution_id" => BB.Command.encode_execution_id(execution_id),
      "pid" => inspect(info.pid),
      "category" => to_string(info.category),
      "started_at" => DateTime.to_iso8601(info.started_at)
    }
  end

  defp command_info(other), do: %{"raw" => inspect(other)}
end
