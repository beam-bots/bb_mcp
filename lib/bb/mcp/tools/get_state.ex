# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.MCP.Tools.GetState do
  @moduledoc """
  Get the current operational and safety state of a robot.

  Returns the safety state (`armed`, `disarmed`, `disarming` or `error`), the
  operational state, and the list of currently executing commands. The
  operational states a robot can be in are declared in its DSL, so they vary
  per robot; `idle` is always one of them.

  The same data is available as the `bb://robots/{robot}/state` resource.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias BB.MCP.State
  alias BB.MCP.Tools

  schema do
    field(:robot, :string, required: true)
  end

  @impl true
  def execute(params, frame) do
    case Tools.fetch_robot(params) do
      {:ok, robot} ->
        payload =
          robot
          |> State.describe()
          |> Map.put("robot", Tools.get_arg(params, :robot))

        {:reply, Response.json(Response.tool(), payload), frame}

      {:error, error} ->
        {:error, error, frame}
    end
  end
end
