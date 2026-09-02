# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.MCP.Resources.RobotState do
  @moduledoc """
  Current operational and safety state of a robot.

  Read via `bb://robots/{robot}/state`. The same data is available via the
  `get_state` tool.

  Each entry in `executing_commands` carries the command name, its execution
  id, the pid running it, its concurrency category, and when it started.
  """

  use Anubis.Server.Component,
    type: :resource,
    uri_template: "bb://robots/{robot}/state",
    name: "robot_state"

  alias Anubis.Server.Response
  alias BB.MCP.Resources
  alias BB.MCP.State

  @impl true
  def description, do: "Current safety and operational state of the robot"

  @impl true
  def mime_type, do: "application/json"

  @impl true
  def read(params, frame) do
    case Resources.fetch_robot(params) do
      {:ok, module} ->
        {:reply, Response.json(Response.resource(), State.describe(module)), frame}

      {:error, error} ->
        {:error, error, frame}
    end
  end
end
