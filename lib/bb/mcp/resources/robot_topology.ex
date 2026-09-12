# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.MCP.Resources.RobotTopology do
  @moduledoc """
  Static topology of a robot — links, joints, sensors, and actuators.

  Read via `bb://robots/{robot}/topology`. The contents do not change
  after the robot is compiled.

  Every value is in SI base units: metres, radians, and their per-second and
  per-second-squared derivatives. A joint reports the fields its type gives it,
  so `axis`, `origin`, `limit` and `dynamics` are each present only where the
  robot declares them.

  `axis` is the joint's axis of rotation or translation as a unit vector, and
  is what a `planar` joint's in-plane numbers from
  `bb://robots/{robot}/joints` are measured against — it is that plane's
  normal.
  """

  use Anubis.Server.Component,
    type: :resource,
    uri_template: "bb://robots/{robot}/topology",
    name: "robot_topology"

  alias Anubis.Server.Response
  alias BB.MCP.Resources
  alias BB.Robot
  alias BB.Robot.Joint
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
          "name" => inspect(robot.name),
          "root_link" => to_string(robot.root_link),
          "links" => robot.links |> Map.keys() |> Enum.map(&to_string/1) |> Enum.sort(),
          "joints" => Enum.map(Robot.joints_in_order(robot), &format_joint/1),
          "sensors" => robot.sensors |> Map.values() |> Enum.map(&format_sensor/1),
          "actuators" => robot.actuators |> Map.values() |> Enum.map(&format_actuator/1)
        }

        {:reply, Response.json(Response.resource(), payload), frame}

      {:error, error} ->
        {:error, error, frame}
    end
  end

  defp format_joint(%Joint{} = joint) do
    %{
      "name" => to_string(joint.name),
      "type" => to_string(joint.type),
      "degrees_of_freedom" => Joint.dof(joint),
      "parent_link" => to_string(joint.parent_link),
      "child_link" => to_string(joint.child_link)
    }
    |> put_present("axis", format_axis(joint.axis))
    |> put_present("origin", format_origin(joint.origin))
    |> put_present("limit", format_limit(joint.limits))
    |> put_present("dynamics", format_dynamics(joint.dynamics))
  end

  defp format_axis(nil), do: nil
  defp format_axis({x, y, z}), do: %{"x" => x, "y" => y, "z" => z}

  defp format_origin(nil), do: nil

  defp format_origin(%{position: {x, y, z}, orientation: {roll, pitch, yaw}}) do
    %{
      "position" => %{"x" => x, "y" => y, "z" => z},
      "orientation" => %{"roll" => roll, "pitch" => pitch, "yaw" => yaw}
    }
  end

  defp format_limit(nil), do: nil

  defp format_limit(limit) when is_map(limit) do
    %{
      "lower" => Map.get(limit, :lower),
      "upper" => Map.get(limit, :upper),
      "velocity" => Map.get(limit, :velocity),
      "acceleration" => Map.get(limit, :acceleration),
      "effort" => Map.get(limit, :effort)
    }
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp format_dynamics(nil), do: nil

  defp format_dynamics(dynamics) when is_map(dynamics) do
    %{
      "damping" => Map.get(dynamics, :damping),
      "friction" => Map.get(dynamics, :friction)
    }
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp put_present(map, _key, nil), do: map
  defp put_present(map, _key, empty) when empty == %{}, do: map
  defp put_present(map, key, value), do: Map.put(map, key, value)

  defp format_sensor(%{name: name, attached_to: attached_to} = sensor) do
    %{"name" => to_string(name), "attached_to" => format_attached_to(attached_to)}
    |> put_present("transmission", format_transmission(sensor.transmission))
  end

  defp format_actuator(%{name: name, joint: joint} = actuator) do
    %{"name" => to_string(name), "joint" => to_string(joint)}
    |> put_present("transmission", format_transmission(actuator.transmission))
  end

  # Gearing between an actuator or sensor and the joint it drives or reads, so
  # an agent comparing a joint position against a raw actuator reading knows
  # what sits in between.
  defp format_transmission(nil), do: nil

  defp format_transmission(transmission) when is_map(transmission) do
    %{
      "reduction" => Map.get(transmission, :reduction),
      "offset" => Map.get(transmission, :offset),
      "reversed" => Map.get(transmission, :reversed?)
    }
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp format_attached_to({:link, name}), do: %{"link" => to_string(name)}
  defp format_attached_to({:joint, name}), do: %{"joint" => to_string(name)}
  defp format_attached_to(:robot), do: %{"robot" => true}
  defp format_attached_to(other), do: inspect(other)
end
