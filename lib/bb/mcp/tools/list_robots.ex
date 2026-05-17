# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.MCP.Tools.ListRobots do
  @moduledoc """
  List the robots this MCP server is configured to expose.

  Returns a list of `{name, module}` entries. Use `name` as the `robot`
  argument to every other tool.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias BB.MCP.Robots
  alias BB.MCP.Tools

  schema do
  end

  @impl true
  def execute(_params, frame) do
    payload =
      Tools.robots()
      |> Robots.to_list()
      |> Enum.map(fn {name, module} ->
        %{"name" => name, "module" => inspect(module)}
      end)

    {:reply, Response.json(Response.tool(), %{"robots" => payload}), frame}
  end
end
