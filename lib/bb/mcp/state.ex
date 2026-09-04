# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.MCP.State do
  @moduledoc """
  Describe a robot's current safety and operational state.

  Shared by the `get_state` tool and the `bb://robots/{robot}/state` resource
  so the two always answer with the same fields.
  """

  alias BB.MCP.Json
  alias BB.Robot.Runtime
  alias BB.Safety

  @doc """
  The state of `robot_module` as a JSON-encodable map.

  `BB.Robot.Runtime.executing_commands/1` reports each command's execution id
  as a `reference()` and its start as a `DateTime`, so the whole reply goes
  through `BB.MCP.Json.encodable/1` on the way out.
  """
  @spec describe(module()) :: map()
  def describe(robot_module) do
    %{
      "safety_state" => Json.encodable(Safety.state(robot_module)),
      "operational_state" => Json.encodable(Runtime.operational_state(robot_module)),
      "executing" => Runtime.executing?(robot_module),
      "executing_commands" => robot_module |> Runtime.executing_commands() |> Json.encodable()
    }
  end
end
