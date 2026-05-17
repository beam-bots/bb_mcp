# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.MCP.Resources.RobotJoints do
  @moduledoc """
  Current joint positions and velocities of a robot, in SI base units
  (metres or radians for position, m/s or rad/s for velocity).

  Read via `bb://robots/{robot}/joints`.
  """

  use Anubis.Server.Component,
    type: :resource,
    uri_template: "bb://robots/{robot}/joints",
    name: "robot_joints"

  alias Anubis.Server.Response
  alias BB.MCP.Resources
  alias BB.Robot.Runtime

  @impl true
  def description, do: "Current joint positions and velocities (SI units)"

  @impl true
  def mime_type, do: "application/json"

  @impl true
  def read(params, frame) do
    case Resources.fetch_robot(params) do
      {:ok, module} ->
        payload = %{
          "positions" => stringify_keys(Runtime.positions(module)),
          "velocities" => stringify_keys(Runtime.velocities(module))
        }

        {:reply, Response.json(Response.resource(), payload), frame}

      {:error, error} ->
        {:error, error, frame}
    end
  end

  defp stringify_keys(map) when is_map(map),
    do: Map.new(map, fn {k, v} -> {to_string(k), v} end)
end
