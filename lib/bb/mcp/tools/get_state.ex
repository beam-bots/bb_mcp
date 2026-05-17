# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.MCP.Tools.GetState do
  @moduledoc """
  Get the current operational and safety state of a robot.

  Returns the safety state (`:armed | :disarmed | :disarming | :error`),
  the operational state (e.g. `:idle`, `:executing`), and the list of
  currently executing commands.
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

  defp command_info(%{name: name, pid: pid}) do
    %{"name" => to_string(name), "pid" => inspect(pid)}
  end

  defp command_info(other), do: %{"raw" => inspect(other)}
end
