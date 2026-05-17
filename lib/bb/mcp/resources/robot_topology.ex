# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.MCP.Resources.RobotTopology do
  @moduledoc """
  Static topology of a robot — links, joints, sensors, and actuators.

  Read via `bb://robots/{robot}/topology`. The contents do not change
  after the robot is compiled.
  """

  use Anubis.Server.Component,
    type: :resource,
    uri_template: "bb://robots/{robot}/topology",
    name: "robot_topology"

  alias Anubis.Server.Response
  alias BB.MCP.Resources
  alias BB.Robot
  alias BB.Robot.Runtime

  @impl true
  def description, do: "Links, joints, sensors, and actuators that make up the robot"

  @impl true
  def mime_type, do: "application/json"

  @impl true
  def read(params, frame) do
    case Resources.fetch_robot(params) do
      {:ok, module} ->
        robot = Runtime.get_robot(module)

        payload = %{
          "name" => to_string(robot.name),
          "root_link" => to_string(robot.root_link),
          "links" => robot.links |> Map.keys() |> Enum.map(&to_string/1) |> Enum.sort(),
          "joints" => Enum.map(Robot.joints_in_order(robot), &format_joint(robot, &1)),
          "sensors" => robot.sensors |> Map.values() |> Enum.map(&format_sensor/1),
          "actuators" => robot.actuators |> Map.values() |> Enum.map(&format_actuator/1)
        }

        {:reply, Response.json(Response.resource(), payload), frame}

      {:error, error} ->
        {:error, error, frame}
    end
  end

  defp format_joint(_robot, joint) do
    %{
      "name" => to_string(joint.name),
      "type" => to_string(joint.type),
      "parent_link" => to_string(joint.parent_link),
      "child_link" => to_string(joint.child_link)
    }
    |> maybe_put_limits(joint)
  end

  defp maybe_put_limits(map, %{limit: nil}), do: map

  defp maybe_put_limits(map, %{limit: limit}) when is_map(limit) do
    Map.put(map, "limit", %{
      "lower" => Map.get(limit, :lower),
      "upper" => Map.get(limit, :upper),
      "velocity" => Map.get(limit, :velocity),
      "effort" => Map.get(limit, :effort)
    })
  end

  defp maybe_put_limits(map, _), do: map

  defp format_sensor(%{name: name, attached_to: attached_to}) do
    %{"name" => to_string(name), "attached_to" => format_attached_to(attached_to)}
  end

  defp format_actuator(%{name: name, joint: joint}) do
    %{"name" => to_string(name), "joint" => to_string(joint)}
  end

  defp format_attached_to({:link, name}), do: %{"link" => to_string(name)}
  defp format_attached_to({:joint, name}), do: %{"joint" => to_string(name)}
  defp format_attached_to(:robot), do: %{"robot" => true}
  defp format_attached_to(other), do: inspect(other)
end
