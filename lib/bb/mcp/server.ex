# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.MCP.Server do
  @grace_period 3_000

  @moduledoc """
  MCP server that exposes BB robots to AI agents.

  The set of robots this server makes available is read from application
  config at runtime:

      config :bb_mcp, robots: [MyApp.WX200, MyApp.SO101]

  ## Supervision

  Add the server to your supervision tree alongside your robots:

      children = [
        MyApp.WX200,
        MyApp.SO101,
        {BB.MCP.Server, transport: :streamable_http, streamable_http: [port: 4000]}
      ]

  ## Phoenix mount

  Mount over Streamable HTTP inside a Phoenix router using
  `BB.MCP.Router.bb_mcp/2`:

      import BB.MCP.Router
      scope "/" do
        bb_mcp "/mcp"
      end

  ## Tools

  Static cross-cutting tools (`list_robots`, `get_state`, `force_disarm`,
  `list_commands`, `list_parameters`, `get_parameter`, `set_parameter`,
  `send_joint_positions`) take a `robot` string argument identifying the
  target robot.

  Per-command tools are registered dynamically on session initialisation,
  one per `{robot, command}` pair declared in each robot's Spark DSL.
  Each is named `{robot}.{command}` (e.g. `wx200.home`) and carries the
  command's typed argument schema. They are dispatched through
  `handle_tool_call/3` to `BB.Robot.Runtime.execute/3` +
  `BB.Command.yield/2`.

  ## Long-running commands

  A command tool waits `#{@grace_period}ms` for a result, which keeps the many
  commands that finish promptly to a single round-trip. A command that takes
  longer is not interrupted: the tool replies with its `execution_id`, which
  the agent hands to `cancel_command` to stop it, or uses as a `query_events`
  path prefix to pick up the `succeeded`/`failed` event when it lands.

  Override the wait with:

      config :bb_mcp, command_grace_period: 10_000

  ## Resources

  Resources are URI-templated by robot name. See `BB.MCP.Resources.*`.
  """

  use Anubis.Server,
    name: "bb_mcp",
    version: "0.1.0",
    capabilities: [:tools, :resources]

  alias Anubis.MCP.Error
  alias Anubis.Server.Frame
  alias Anubis.Server.Response
  alias BB.Command
  alias BB.MCP.EventBuffer
  alias BB.MCP.PeriSchema
  alias BB.MCP.Robots
  alias BB.MCP.Tools
  alias BB.Message
  alias BB.PubSub
  alias BB.Robot.Runtime

  @collect_timeout 100

  component(BB.MCP.Tools.CancelCommand)
  component(BB.MCP.Tools.ForceDisarm)
  component(BB.MCP.Tools.GetParameter)
  component(BB.MCP.Tools.GetState)
  component(BB.MCP.Tools.ListCommands)
  component(BB.MCP.Tools.ListParameters)
  component(BB.MCP.Tools.ListRobots)
  component(BB.MCP.Tools.QueryEvents)
  component(BB.MCP.Tools.SendJointPositions)
  component(BB.MCP.Tools.SetParameter)

  component(BB.MCP.Resources.RobotCommands)
  component(BB.MCP.Resources.RobotIndex)
  component(BB.MCP.Resources.RobotJoints)
  component(BB.MCP.Resources.RobotParameters)
  component(BB.MCP.Resources.RobotState)
  component(BB.MCP.Resources.RobotTopology)

  @impl Anubis.Server
  def init(_client_info, frame) do
    robots = Tools.robots() |> Robots.to_list()

    frame =
      frame
      |> Frame.assign(:event_buffer, subscribe_to_events(robots))
      |> then(&Enum.reduce(robots, &1, fn robot, acc -> register_robot_tools(robot, acc) end))

    {:ok, frame}
  end

  @impl Anubis.Server
  def handle_info({:bb, path, %Message{} = message}, frame) do
    case Map.fetch(frame.assigns, :event_buffer) do
      {:ok, buffer} ->
        robot_name = robot_name_for(buffer, message) || "unknown"

        {:noreply,
         Frame.assign(frame, :event_buffer, EventBuffer.push(buffer, robot_name, path, message))}

      :error ->
        {:noreply, frame}
    end
  end

  def handle_info(_other, frame), do: {:noreply, frame}

  @impl Anubis.Server
  def terminate(_reason, frame) do
    case Map.get(frame.assigns, :event_buffer) do
      %{subscriptions: subs} -> Enum.each(subs, fn {_name, mod} -> safe_unsubscribe(mod) end)
      _ -> :ok
    end

    :ok
  end

  defp subscribe_to_events(robots) do
    capacity = EventBuffer.configured_capacity()

    Enum.reduce(robots, EventBuffer.new(capacity), fn {robot_name, robot_module}, buffer ->
      case safe_subscribe(robot_module) do
        :ok -> EventBuffer.record_subscription(buffer, robot_name, robot_module)
        :error -> buffer
      end
    end)
  end

  defp safe_subscribe(robot_module) do
    case PubSub.subscribe(robot_module, []) do
      {:ok, _pid} -> :ok
      _ -> :error
    end
  rescue
    _ -> :error
  end

  defp safe_unsubscribe(robot_module) do
    PubSub.unsubscribe(robot_module, [])
  rescue
    _ -> :ok
  end

  defp robot_name_for(%{subscriptions: subs}, %Message{robot: robot_module})
       when is_atom(robot_module) do
    case List.keyfind(subs, robot_module, 1) do
      {name, ^robot_module} -> name
      _ -> nil
    end
  end

  defp robot_name_for(_, _), do: nil

  @impl Anubis.Server
  def handle_tool_call(name, params, frame) do
    case parse_tool_name(name) do
      {:ok, robot_name, command_name} ->
        dispatch_command(robot_name, command_name, params, frame)

      :error ->
        {:error, Error.protocol(:method_not_found, %{message: "unknown tool: #{inspect(name)}"}),
         frame}
    end
  end

  @impl Anubis.Server
  def server_instructions do
    """
    This server exposes one or more BB-framework robots over MCP.

    Start by calling `list_robots` to see configured robots. Each
    robot's declared commands appear as their own tools, named
    `{robot}.{command}` — e.g. `wx200.home`, `wx200.arm`. Their input
    schemas come straight from the robot's Spark DSL.

    Cross-cutting tools (`get_state`, `force_disarm`,
    `list_parameters`, `get_parameter`, `set_parameter`,
    `send_joint_positions`, `list_commands`) take a `robot` argument
    selecting which robot to operate on.

    A command tool waits a few seconds for its result. If the command
    is still running it replies with `{"status": "running",
    "execution_id": ...}` — the command has NOT failed and the robot is
    still moving. Stop it with `cancel_command`, or wait and read its
    outcome from `query_events` under the path prefix
    `command.{command}.{execution_id}`.

    `query_events` returns recent pubsub events captured since this MCP
    session connected — useful for inspecting command outcomes,
    joint-state changes, and motion lifecycle without polling state.

    Resources are URI-templated by robot name, e.g.
    `bb://robots/{robot}/topology` or `bb://robots/{robot}/joints`.

    Robots must be armed before motion commands will run; arm using
    the `{robot}.arm` tool (or `{robot}.disarm` / `force_disarm` to
    stop).
    """
  end

  defp register_robot_tools({robot_name, robot_module}, frame) do
    robot_module
    |> Tools.commands()
    |> Enum.reduce(frame, fn command, acc ->
      register_command_tool(acc, robot_name, robot_module, command)
    end)
  end

  defp register_command_tool(frame, robot_name, _robot_module, command) do
    tool_name = "#{robot_name}.#{command.name}"
    schema = PeriSchema.for_command(command)

    frame
    |> Frame.register_tool(tool_name,
      description: tool_description(robot_name, command),
      input_schema: schema
    )
    |> wrap_tool_validator(tool_name, command)
  end

  # Some MCP clients reinterpret flat dotted property names (e.g. `"target.x"`)
  # as nested-object paths and send `{"target": {"x": ...}}`. We register the
  # flat shape on purpose (broader client compatibility) so we flatten any
  # nested values back to the dotted form before Peri validates them.
  defp wrap_tool_validator(frame, tool_name, command) do
    case Map.fetch(frame.tools, tool_name) do
      {:ok, %{validate_input: original} = tool} when is_function(original, 1) ->
        wrapped = fn params -> original.(PeriSchema.flatten_nested_params(command, params)) end
        %{frame | tools: Map.put(frame.tools, tool_name, %{tool | validate_input: wrapped})}

      _ ->
        frame
    end
  end

  defp tool_description(robot_name, command) do
    states = Enum.map_join(command.allowed_states, ", ", &Atom.to_string/1)

    cat = if command.category, do: " (category: #{command.category})", else: ""

    "Run the `#{command.name}` command on robot `#{robot_name}`#{cat}. " <>
      "Allowed when robot is in state: #{states}."
  end

  defp parse_tool_name(name) when is_binary(name) do
    case String.split(name, ".", parts: 2) do
      [robot, command] when robot != "" and command != "" -> {:ok, robot, command}
      _ -> :error
    end
  end

  defp dispatch_command(robot_name, command_name, params, frame) do
    with {:ok, robot_module} <- resolve_robot(robot_name),
         {:ok, command} <- fetch_command(robot_module, command_name),
         goal = PeriSchema.to_goal(command, params),
         {:ok, pid} <- Runtime.execute(robot_module, command.name, goal) do
      reply_for(Command.yield(pid, grace_period()), pid, robot_module, command, frame)
    else
      {:error, reason} ->
        {:error, Tools.to_anubis_error(reason), frame}
    end
  end

  # `BB.Command.yield/2` returns `nil` both for a command that is still running
  # and for one that finished with a `nil` result, so look the command up in the
  # robot's registry to tell the two apart.
  defp reply_for(nil, pid, robot_module, command, frame) do
    case execution_id_for(robot_module, pid) do
      nil -> completed(Command.yield(pid, @collect_timeout), frame)
      execution_id -> still_running(execution_id, command, frame)
    end
  end

  defp reply_for(result, _pid, _robot_module, _command, frame), do: completed(result, frame)

  defp completed({:ok, result}, frame), do: completed_reply(result, frame)
  defp completed({:ok, result, _opts}, frame), do: completed_reply(result, frame)
  defp completed(nil, frame), do: completed_reply(nil, frame)

  defp completed({:error, reason}, frame),
    do: {:error, Tools.to_anubis_error(reason), frame}

  defp completed_reply(result, frame) do
    payload = %{"status" => "ok", "result" => inspect(result)}
    {:reply, Response.json(Response.tool(), payload), frame}
  end

  defp still_running(execution_id, command, frame) do
    payload = %{
      "status" => "running",
      "execution_id" => execution_id,
      "note" =>
        "The command is still running. Stop it with `cancel_command`, or read " <>
          "its outcome from `query_events` under path prefix " <>
          "`command.#{command.name}.#{execution_id}`."
    }

    {:reply, Response.json(Response.tool(), payload), frame}
  end

  defp execution_id_for(robot_module, pid) do
    robot_module
    |> Command.list()
    |> Enum.find_value(fn entry ->
      if entry.pid == pid, do: Command.encode_execution_id(entry.execution_id)
    end)
  end

  defp grace_period do
    case Application.get_env(:bb_mcp, :command_grace_period, @grace_period) do
      ms when is_integer(ms) and ms > 0 -> ms
      _ -> @grace_period
    end
  end

  defp resolve_robot(name) do
    case Robots.fetch(Tools.robots(), name) do
      {:ok, module} ->
        {:ok, module}

      {:error, :unknown_robot} ->
        {:error, Error.protocol(:invalid_request, %{message: "unknown robot: #{inspect(name)}"})}
    end
  end

  # Matched by name string rather than interning the client's value as an atom:
  # a tool call naming a command that doesn't exist would otherwise grow the
  # atom table, which is never collected.
  defp fetch_command(robot_module, command_name) do
    robot_module
    |> Tools.commands()
    |> Enum.find(&(Atom.to_string(&1.name) == command_name))
    |> case do
      nil ->
        {:error,
         Error.protocol(:invalid_request, %{message: "unknown command: #{inspect(command_name)}"})}

      command ->
        {:ok, command}
    end
  end
end
