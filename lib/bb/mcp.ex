# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.MCP do
  @moduledoc """
  Model Context Protocol server for Beam Bots robots.

  This module is the public entry point. The server itself is
  `BB.MCP.Server`; see its documentation for supervision and transport
  configuration.

  ## Quick start

      children = [
        MyApp.WX200,
        {BB.MCP.Server, name: MyApp.MCP, robots: [MyApp.WX200]}
      ]

      Supervisor.start_link(children, strategy: :one_for_one)

  Then mount over Streamable HTTP in a Phoenix router:

      import BB.MCP.Router
      scope "/" do
        bb_mcp "/mcp", server: MyApp.MCP
      end
  """
end
