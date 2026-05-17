# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.MCP.Tools.ForceDisarm do
  @moduledoc """
  Force-disarm a robot from `:error` state.

  WARNING: this bypasses normal disarm safety checks. Only invoke after
  manually verifying that hardware is in a safe state.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias BB.MCP.Tools
  alias BB.Safety

  schema do
    field(:robot, :string, required: true)
  end

  @impl true
  def execute(params, frame) do
    with {:ok, robot} <- Tools.fetch_robot(params),
         :ok <- Safety.force_disarm(robot) do
      {:reply, Response.json(Response.tool(), %{"status" => "disarmed"}), frame}
    else
      {:error, reason} ->
        {:error, Tools.to_anubis_error(reason), frame}
    end
  end
end
