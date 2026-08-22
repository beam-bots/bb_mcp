# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.MCP.Tools.SendJointPositions do
  @moduledoc """
  Send target positions to one or more robot joints.

  Positions are SI units: radians for revolute/continuous joints, metres for
  prismatic joints. Send a single joint with `joint`/`position`, or a batch as a
  JSON object string in `positions_json`. The robot must be armed and idle.

  Delivery defaults to `pubsub`, which waits for every actuator to accept its
  command and reports the first refusal. `direct` casts instead and waits for
  nothing, so it answers `ok` whether or not the robot took the command.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.MCP.Error
  alias Anubis.Server.Response
  alias BB.MCP.Tools
  alias BB.Motion
  alias BB.Robot.Joint
  alias BB.Robot.Runtime
  alias BB.Safety

  schema do
    field(:robot, :string, required: true)

    field(:positions_json, :string,
      required: false,
      description: "JSON object mapping joint names to target positions"
    )

    field(:joint, :string,
      required: false,
      description: "Single joint name to move when positions is not supplied"
    )

    field(:position, :float,
      required: false,
      description: "Target position for joint in SI units"
    )

    field(:delivery, :string,
      required: false,
      description:
        "Delivery mode: pubsub (default) waits for every actuator to accept " <>
          "the command and reports the first refusal; direct casts and waits " <>
          "for nothing, so a refusal is never reported"
    )

    field(:duration, :integer,
      required: false,
      description: "Optional motion duration hint in milliseconds"
    )

    field(:velocity, :float,
      required: false,
      description: "Optional velocity hint in rad/s or m/s"
    )
  end

  @impl true
  def execute(params, frame) do
    with {:ok, robot} <- Tools.fetch_robot(params),
         :ok <- check_motion_allowed(robot),
         {:ok, positions} <- parse_positions(robot, params),
         {:ok, opts} <- parse_opts(params),
         :ok <- send_positions(robot, positions, opts) do
      payload = %{
        "delivery" => opts |> Keyword.fetch!(:delivery) |> Atom.to_string(),
        "positions" => format_positions(positions),
        "status" => "ok"
      }

      {:reply, Response.json(Response.tool(), payload), frame}
    else
      {:error, reason} when is_binary(reason) ->
        {:error, Error.protocol(:invalid_request, %{message: reason}), frame}

      {:error, reason} ->
        {:error, Tools.to_anubis_error(reason), frame}
    end
  end

  defp check_motion_allowed(robot) do
    case {Safety.state(robot), Runtime.operational_state(robot)} do
      {:armed, :idle} ->
        :ok

      {safety_state, operational_state} ->
        {:error,
         Error.execution(
           "robot must be armed and idle before sending joint positions; " <>
             "safety_state=#{inspect(safety_state)}, operational_state=#{inspect(operational_state)}"
         )}
    end
  end

  defp parse_positions(robot, params) when is_map(params) do
    positions_result = decode_positions_json(Tools.get_arg(params, :positions_json))
    joint = Tools.get_arg(params, :joint)
    position = Tools.get_arg(params, :position)

    case positions_result do
      {:ok, positions} ->
        parse_positions_map(robot, positions)

      {:error, _reason} = error ->
        error

      nil ->
        parse_single_position(robot, joint, position)
    end
  end

  defp parse_single_position(robot, joint, position)
       when is_binary(joint) and is_number(position) do
    parse_positions_map(robot, %{joint => position})
  end

  defp parse_single_position(_robot, joint, _position) when is_binary(joint) do
    {:error, "position is required when joint is supplied"}
  end

  defp parse_single_position(_robot, _joint, position) when is_number(position) do
    {:error, "joint is required when position is supplied"}
  end

  defp parse_single_position(_robot, _joint, _position),
    do: {:error, "positions_json or joint and position are required"}

  defp decode_positions_json(nil), do: nil

  defp decode_positions_json(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, positions} when is_map(positions) -> {:ok, positions}
      {:ok, _other} -> {:error, "positions_json must decode to an object"}
      {:error, _reason} -> {:error, "positions_json must be valid JSON"}
    end
  end

  defp decode_positions_json(_value), do: {:error, "positions_json must be a JSON string"}

  defp parse_positions_map(_robot, positions) when positions == %{} do
    {:error, "positions must not be empty"}
  end

  defp parse_positions_map(robot, positions) when is_map(positions) do
    joints_by_name =
      robot
      |> Runtime.get_robot()
      |> Map.fetch!(:joints)
      |> Map.new(fn {name, joint} -> {Atom.to_string(name), {name, joint}} end)

    positions
    |> Enum.reduce_while({:ok, %{}}, fn {raw_name, raw_position}, {:ok, acc} ->
      with {:ok, name} <- parse_joint_name(raw_name),
           {:ok, joint_name, joint} <- fetch_joint(joints_by_name, name),
           :ok <- validate_joint(joint),
           {:ok, position} <- parse_position(raw_position),
           :ok <- validate_limits(joint, position) do
        {:cont, {:ok, Map.put(acc, joint_name, position)}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp parse_joint_name(name) when is_atom(name), do: {:ok, Atom.to_string(name)}
  defp parse_joint_name(name) when is_binary(name), do: {:ok, name}
  defp parse_joint_name(_name), do: {:error, "joint names must be strings"}

  defp fetch_joint(joints_by_name, name) do
    case Map.fetch(joints_by_name, name) do
      {:ok, {joint_name, joint}} -> {:ok, joint_name, joint}
      :error -> {:error, "unknown joint: #{name}"}
    end
  end

  defp validate_joint(%Joint{} = joint) do
    cond do
      not Joint.movable?(joint) ->
        {:error, "joint is not movable: #{joint.name}"}

      joint.actuators == [] ->
        {:error, "joint has no actuators: #{joint.name}"}

      true ->
        :ok
    end
  end

  defp parse_position(position) when is_integer(position), do: {:ok, position * 1.0}
  defp parse_position(position) when is_float(position), do: {:ok, position}
  defp parse_position(_position), do: {:error, "joint positions must be numbers"}

  defp validate_limits(%Joint{type: :continuous}, _position), do: :ok
  defp validate_limits(%Joint{limits: nil}, _position), do: :ok

  defp validate_limits(%Joint{limits: limits} = joint, position) do
    lower = Map.get(limits, :lower)
    upper = Map.get(limits, :upper)

    cond do
      is_number(lower) and position < lower ->
        {:error, "position for #{joint.name} is below lower limit #{lower}: #{position}"}

      is_number(upper) and position > upper ->
        {:error, "position for #{joint.name} is above upper limit #{upper}: #{position}"}

      true ->
        :ok
    end
  end

  defp parse_opts(params) do
    with {:ok, delivery} <- parse_delivery(Tools.get_arg(params, :delivery)),
         {:ok, opts} <-
           maybe_put_positive_number(
             [delivery: delivery],
             :velocity,
             Tools.get_arg(params, :velocity)
           ) do
      maybe_put_positive_integer(opts, :duration, Tools.get_arg(params, :duration))
    end
  end

  defp parse_delivery(nil), do: {:ok, :pubsub}
  defp parse_delivery("direct"), do: {:ok, :direct}
  defp parse_delivery("pubsub"), do: {:ok, :pubsub}
  defp parse_delivery(_delivery), do: {:error, "delivery must be pubsub or direct"}

  defp maybe_put_positive_number(opts, _key, nil), do: {:ok, opts}

  defp maybe_put_positive_number(opts, key, value) when is_number(value) and value > 0 do
    {:ok, Keyword.put(opts, key, value * 1.0)}
  end

  defp maybe_put_positive_number(_opts, key, _value),
    do: {:error, "#{key} must be a positive number"}

  defp maybe_put_positive_integer(opts, _key, nil), do: {:ok, opts}

  defp maybe_put_positive_integer(opts, key, value) when is_integer(value) and value > 0,
    do: {:ok, Keyword.put(opts, key, value)}

  defp maybe_put_positive_integer(_opts, key, _value),
    do: {:error, "#{key} must be a positive integer"}

  defp send_positions(robot, positions, opts) do
    Motion.send_positions(robot, positions, opts)
  rescue
    exception ->
      {:error, Error.execution("send_joint_positions failed: #{Exception.message(exception)}")}
  catch
    kind, reason ->
      {:error, Error.execution("send_joint_positions failed: #{kind}: #{inspect(reason)}")}
  end

  defp format_positions(positions) do
    Map.new(positions, fn {joint, position} -> {Atom.to_string(joint), position} end)
  end
end
