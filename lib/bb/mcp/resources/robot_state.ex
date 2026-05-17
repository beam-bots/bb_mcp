# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.MCP.Resources.RobotState do
  @moduledoc """
  Current operational and safety state of a robot.

  Read via `bb://robots/{robot}/state`.
  """

  use Anubis.Server.Component,
    type: :resource,
    uri_template: "bb://robots/{robot}/state",
    name: "robot_state"

  alias Anubis.Server.Response
  alias BB.MCP.Resources
  alias BB.Robot.Runtime
  alias BB.Safety

  @impl true
  def description, do: "Current safety and operational state of the robot"

  @impl true
  def mime_type, do: "application/json"

  @impl true
  def read(params, frame) do
    case Resources.fetch_robot(params) do
      {:ok, module} ->
        payload = %{
          "safety_state" => Safety.state(module),
          "operational_state" => Runtime.operational_state(module),
          "executing" => Runtime.executing?(module),
          "executing_commands" => Enum.map(Runtime.executing_commands(module), &format_command/1)
        }

        {:reply, Response.json(Response.resource(), payload), frame}

      {:error, error} ->
        {:error, error, frame}
    end
  end

  defp format_command(%_{} = struct) do
    struct |> Map.from_struct() |> stringify_keys()
  end

  defp format_command(map) when is_map(map), do: stringify_keys(map)
  defp format_command(other), do: inspect(other)

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), stringify_value(v)} end)
  end

  defp stringify_value(pid) when is_pid(pid), do: inspect(pid)
  defp stringify_value(value), do: value
end
