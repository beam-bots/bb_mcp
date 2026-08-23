# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.MCP.Resources.RobotJoints do
  @moduledoc """
  Current joint positions and velocities of a robot, in SI base units
  (metres or radians for position, m/s or rad/s for velocity).

  Read via `bb://robots/{robot}/joints`.

  A joint with more than one degree of freedom carries more than one number, so
  its value is an object rather than a scalar, shaped to the joint's type:

  | Type | Position | Velocity |
  |---|---|---|
  | `:revolute`, `:continuous`, `:prismatic` | a number | a number |
  | `:planar` | `x`, `y`, `theta` | `vx`, `vy`, `omega` |
  | `:floating` | `xyz`, `quat` | `linear`, `angular` |

  A planar joint's numbers are in the plane its `axis` is normal to — read the
  topology resource for that axis. `theta` is about the normal, right-handed.
  """

  use Anubis.Server.Component,
    type: :resource,
    uri_template: "bb://robots/{robot}/joints",
    name: "robot_joints"

  alias Anubis.Server.Response
  alias BB.Math.Quaternion
  alias BB.Math.Transform
  alias BB.Math.Transform2D
  alias BB.Math.Vec3
  alias BB.MCP.Resources
  alias BB.Message.Geometry.Twist
  alias BB.Message.Geometry.Twist2D
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
          "positions" => format_joint_values(Runtime.configurations(module)),
          "velocities" => format_joint_values(Runtime.velocities(module))
        }

        {:reply, Response.json(Response.resource(), payload), frame}

      {:error, error} ->
        {:error, error, frame}
    end
  end

  defp format_joint_values(map) when is_map(map),
    do: Map.new(map, fn {name, value} -> {to_string(name), format_value(value)} end)

  defp format_value(value) when is_number(value), do: value

  defp format_value(%Transform2D{x: x, y: y, theta: theta}),
    do: %{"x" => x, "y" => y, "theta" => theta}

  defp format_value(%Twist2D{vx: vx, vy: vy, omega: omega}),
    do: %{"vx" => vx, "vy" => vy, "omega" => omega}

  defp format_value(%Transform{} = transform) do
    [qx, qy, qz, qw] = transform |> Transform.get_quaternion() |> Quaternion.to_xyzw_list()

    %{
      "xyz" => transform |> Transform.get_translation() |> format_vec3(),
      "quat" => %{"x" => qx, "y" => qy, "z" => qz, "w" => qw}
    }
  end

  defp format_value(%Twist{linear: linear, angular: angular}),
    do: %{"linear" => format_vec3(linear), "angular" => format_vec3(angular)}

  defp format_vec3(vec3) do
    [x, y, z] = Vec3.to_list(vec3)
    %{"x" => x, "y" => y, "z" => z}
  end
end
