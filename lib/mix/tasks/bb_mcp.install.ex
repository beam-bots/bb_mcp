# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.BbMcp.Install do
    @shortdoc "Installs BB.MCP into an application"
    @moduledoc """
    #{@shortdoc}

    Configures `:bb_mcp, :robots` from the supplied `--robot` module(s),
    then wires up an MCP transport:

      * If the host app uses Phoenix, the installer locates the
        application's router and adds the `BB.MCP.Router.bb_mcp/2`
        mount (defaulting to `/mcp`).
      * Otherwise it adds `BB.MCP.Server` as a Streamable HTTP child to
        the application's supervision tree, listening on `--port`.

    ## Example

    ```bash
    mix igniter.install bb_mcp
    mix igniter.install bb_mcp --robot MyApp.Robot
    mix igniter.install bb_mcp --robot MyApp.WX200 --robot MyApp.SO101
    mix igniter.install bb_mcp --path /mcp --port 4001
    ```

    ## Options

      * `--robot` — Robot module to expose. May be supplied multiple
        times. Defaults to `{AppPrefix}.Robot`.
      * `--path` — URL path for the Phoenix mount (default `/mcp`).
      * `--port` — Streamable HTTP port for the non-Phoenix mount
        (default `4000`).
    """

    use Igniter.Mix.Task

    alias Igniter.Libs.Phoenix
    alias Igniter.Project.Application, as: ProjectApplication
    alias Igniter.Project.Config, as: ProjectConfig
    alias Igniter.Project.Formatter, as: ProjectFormatter
    alias Igniter.Project.Module, as: ProjectModule

    @impl Igniter.Mix.Task
    def info(_argv, _parent) do
      %Igniter.Mix.Task.Info{
        schema: [
          robot: :keep,
          path: :string,
          port: :integer
        ],
        aliases: [r: :robot, p: :path]
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      options = igniter.args.options
      path = Keyword.get(options, :path, "/mcp")
      port = Keyword.get(options, :port, 4000)
      robots = resolve_robots(igniter, options)

      igniter
      |> ProjectFormatter.import_dep(:bb_mcp)
      |> ProjectConfig.configure(
        "config.exs",
        :bb_mcp,
        [:robots],
        {:code, robots_list_ast(robots)}
      )
      |> wire_transport(path, port)
    end

    defp wire_transport(igniter, path, port) do
      case Phoenix.select_router(igniter) do
        {igniter, nil} -> add_standalone_server(igniter, port)
        {igniter, router} -> mount_into_phoenix(igniter, router, path)
      end
    end

    defp mount_into_phoenix(igniter, router, path) do
      # Do not pass :arg2 — bb_mcp must live in an unaliased scope so
      # Phoenix doesn't rewrite the underlying Anubis Plug module.
      # BB.MCP.Server still needs to be running for the plug to find it,
      # so add it to the supervision tree. Phoenix's endpoint handles the
      # HTTP listener; Anubis just needs the server's transport process.
      igniter
      |> maybe_add_router_scope(router, path)
      |> ProjectApplication.add_new_child({BB.MCP.Server, transport: :streamable_http})
      |> Igniter.add_notice("""
      bb_mcp: mounted at #{inspect(path)} on #{inspect(router)}. The MCP
      Streamable HTTP endpoint will be served by your Phoenix endpoint;
      BB.MCP.Server has been added to the application supervision tree.
      """)
    end

    defp maybe_add_router_scope(igniter, router, path) do
      if router_already_mounts_bb_mcp?(igniter, router) do
        igniter
      else
        Phoenix.add_scope(igniter, "/", router_scope(path), router: router)
      end
    end

    defp router_already_mounts_bb_mcp?(igniter, router) do
      case ProjectModule.find_module(igniter, router) do
        {:ok, {_igniter, source, _zipper}} ->
          source |> Rewrite.Source.get(:content) |> String.contains?("BB.MCP.Router")

        _ ->
          false
      end
    end

    defp router_scope(path) do
      """
      import BB.MCP.Router
      bb_mcp #{inspect(path)}
      """
    end

    defp add_standalone_server(igniter, port) do
      igniter
      |> ProjectApplication.add_new_child(
        {BB.MCP.Server, transport: :streamable_http, streamable_http: [port: port]}
      )
      |> Igniter.add_notice("""
      bb_mcp: BB.MCP.Server added to the supervision tree, serving Streamable
      HTTP on http://localhost:#{port}/. No Phoenix dep detected — the
      server runs standalone via Anubis' built-in HTTP transport.
      """)
    end

    defp resolve_robots(igniter, options) do
      case options |> Keyword.get_values(:robot) |> List.flatten() do
        [] -> [ProjectModule.module_name(igniter, "Robot")]
        names -> Enum.map(names, &ProjectModule.parse/1)
      end
    end

    defp robots_list_ast(robots) do
      Enum.map(robots, &module_ast/1)
    end

    defp module_ast(module) do
      {:__aliases__, [alias: false], module |> Module.split() |> Enum.map(&String.to_atom/1)}
    end
  end
else
  defmodule Mix.Tasks.BbMcp.Install do
    @shortdoc "Installs BB.MCP into an application"
    @moduledoc false
    use Mix.Task

    def run(_argv) do
      Mix.shell().error("""
      The bb_mcp.install task requires igniter.

          mix igniter.install bb_mcp
      """)

      exit({:shutdown, 1})
    end
  end
end
