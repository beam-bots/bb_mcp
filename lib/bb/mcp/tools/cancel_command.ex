# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.MCP.Tools.CancelCommand do
  @moduledoc """
  Cancel a command running on a robot.

  Takes the `execution_id` reported by `get_state`, so a command started by
  anything — an operator, another agent, a scheduled routine — can be stopped
  from here. The command's `result/1` runs as usual and awaiting callers
  receive its result.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.MCP.Error
  alias Anubis.Server.Response
  alias BB.MCP.Tools

  schema do
    field(:robot, :string, required: true)
    field(:execution_id, :string, required: true)
  end

  @impl true
  def execute(params, frame) do
    case Tools.fetch_robot(params) do
      {:ok, robot} -> cancel(robot, Tools.get_arg(params, :execution_id), frame)
      {:error, error} -> {:error, error, frame}
    end
  end

  defp cancel(robot, execution_id, frame) do
    case BB.Command.cancel(robot, execution_id) do
      :ok ->
        {:reply,
         Response.json(Response.tool(), %{
           "status" => "cancelled",
           "execution_id" => execution_id
         }), frame}

      {:error, :not_found} ->
        {:error, not_running_error(robot, execution_id), frame}
    end
  end

  defp not_running_error(robot, execution_id) do
    running =
      robot
      |> BB.Command.list()
      |> Enum.map_join(", ", &BB.Command.encode_execution_id(&1.execution_id))

    Error.protocol(:invalid_request, %{
      message:
        "no command running with execution_id #{inspect(execution_id)}; " <>
          "it may have already finished. Currently running: #{running_or_none(running)}"
    })
  end

  defp running_or_none(""), do: "(none)"
  defp running_or_none(running), do: running
end
