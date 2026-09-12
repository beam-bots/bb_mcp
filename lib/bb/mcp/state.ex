# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.MCP.State do
  @moduledoc """
  Describe a robot's current safety and operational state.

  Shared by the `get_state` tool and the `bb://robots/{robot}/state` resource
  so the two always answer with the same fields.
  """

  alias BB.Command
  alias BB.MCP.Json
  alias BB.Robot.Runtime
  alias BB.Safety

  @doc """
  The state of `robot_module` as a JSON-encodable map.

  `BB.Robot.Runtime.executing_commands/1` reports each command's execution id
  as a `reference()` and its start as a `DateTime`, so the whole reply goes
  through `BB.MCP.Json.encodable/1` on the way out. The execution id is encoded
  by `BB.Command.encode_execution_id/1` rather than inspected, since
  `cancel_command` hands it straight back to `BB.Command.cancel/2`.
  """
  @spec describe(module()) :: map()
  def describe(robot_module) do
    %{
      "safety_state" => Json.encodable(Safety.state(robot_module)),
      "operational_state" => Json.encodable(Runtime.operational_state(robot_module)),
      "executing" => Runtime.executing?(robot_module),
      "executing_commands" =>
        robot_module |> Runtime.executing_commands() |> Enum.map(&describe_command/1)
    }
  end

  defp describe_command(%{execution_id: execution_id} = command) do
    command
    |> Json.encodable()
    |> Map.put("execution_id", Command.encode_execution_id(execution_id))
  end
end
