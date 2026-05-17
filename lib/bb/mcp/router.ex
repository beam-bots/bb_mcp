# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.MCP.Router do
  @moduledoc """
  Phoenix router macro for mounting the BB MCP server over Streamable HTTP.

  ## Usage

      defmodule MyAppWeb.Router do
        use Phoenix.Router
        import BB.MCP.Router

        scope "/" do
          bb_mcp "/mcp"
        end
      end

  This forwards requests at the given path to
  `Anubis.Server.Transport.StreamableHTTP.Plug`, configured for
  `BB.MCP.Server`. Pass `server: MyOtherServerModule` to mount a
  different server module (useful if you've defined your own
  `use Anubis.Server` module).
  """

  @doc """
  Forwards `path` to the Anubis Streamable HTTP plug for the BB MCP server.

  ## Options

  - `:server` — the server module to mount. Defaults to `BB.MCP.Server`.
  """
  defmacro bb_mcp(path, opts \\ []) do
    server = Keyword.get(opts, :server, BB.MCP.Server)
    other_opts = Keyword.delete(opts, :server)
    # Resolve the plug at macro-expansion time so that a surrounding
    # `scope "/", MyAppWeb do … end` cannot rewrite the alias.
    plug = Anubis.Server.Transport.StreamableHTTP.Plug

    quote do
      forward(
        unquote(path),
        unquote(plug),
        [server: unquote(server)] ++ unquote(other_opts)
      )
    end
  end
end
