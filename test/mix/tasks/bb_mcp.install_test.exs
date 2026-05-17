# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule Mix.Tasks.BbMcp.InstallTest do
  use ExUnit.Case

  import Igniter.Test

  @moduletag :igniter

  defp source_content(igniter, path) do
    igniter.rewrite |> Rewrite.source!(path) |> Rewrite.Source.get(:content)
  end

  @router """
  defmodule TestWeb.Router do
    use Phoenix.Router

    pipeline :browser do
      plug(:accepts, ["html"])
    end

    scope "/", TestWeb do
      pipe_through(:browser)

      get("/", PageController, :home)
    end
  end
  """

  describe "standalone (no Phoenix)" do
    test "creates config/config.exs configuring :bb_mcp, :robots with the default robot" do
      test_project()
      |> Igniter.compose_task("bb_mcp.install")
      |> assert_creates("config/config.exs", """
      import Config
      config :bb_mcp, robots: [Test.Robot]
      """)
    end

    test "honours one or more --robot options" do
      test_project()
      |> Igniter.compose_task("bb_mcp.install", [
        "--robot",
        "MyApp.WX200",
        "--robot",
        "MyApp.SO101"
      ])
      |> assert_creates("config/config.exs", """
      import Config
      config :bb_mcp, robots: [MyApp.WX200, MyApp.SO101]
      """)
    end

    test "adds BB.MCP.Server to the application supervision tree" do
      igniter =
        test_project()
        |> Igniter.compose_task("bb_mcp.install")
        |> apply_igniter!()

      assert source_content(igniter, "lib/test/application.ex") =~
               "{BB.MCP.Server, [transport: :streamable_http, streamable_http: [port: 4000]]}"
    end

    test "honours --port" do
      igniter =
        test_project()
        |> Igniter.compose_task("bb_mcp.install", ["--port", "4321"])
        |> apply_igniter!()

      assert source_content(igniter, "lib/test/application.ex") =~
               "streamable_http: [port: 4321]"
    end

    test "imports bb_mcp into .formatter.exs" do
      test_project()
      |> Igniter.compose_task("bb_mcp.install")
      |> assert_has_patch(".formatter.exs", """
      + |  import_deps: [:bb_mcp]
      """)
    end

    test "notice mentions the standalone HTTP endpoint" do
      test_project()
      |> Igniter.compose_task("bb_mcp.install")
      |> assert_has_notice(&String.contains?(&1, "Streamable"))
    end
  end

  describe "Phoenix project" do
    defp phx_project, do: test_project(files: %{"lib/test_web/router.ex" => @router})

    test "adds an unaliased scope with bb_mcp/1 mounting at /mcp" do
      phx_project()
      |> Igniter.compose_task("bb_mcp.install")
      |> assert_has_patch("lib/test_web/router.ex", """
      + |  scope "/" do
      + |    import BB.MCP.Router
      + |    bb_mcp("/mcp")
      + |  end
      """)
    end

    test "honours --path" do
      phx_project()
      |> Igniter.compose_task("bb_mcp.install", ["--path", "/agent"])
      |> assert_has_patch("lib/test_web/router.ex", """
      + |    bb_mcp("/agent")
      """)
    end

    test "still adds BB.MCP.Server to the supervision tree (no port; Phoenix owns HTTP)" do
      igniter =
        phx_project()
        |> Igniter.compose_task("bb_mcp.install")
        |> apply_igniter!()

      content = source_content(igniter, "lib/test/application.ex")
      assert content =~ "{BB.MCP.Server, [transport: :streamable_http]}"
      refute content =~ "streamable_http: [port:"
    end

    test "notice mentions the mount path" do
      phx_project()
      |> Igniter.compose_task("bb_mcp.install")
      |> assert_has_notice(&String.contains?(&1, "/mcp"))
    end
  end

  describe "idempotency" do
    test "running twice produces no further changes (standalone)" do
      test_project()
      |> Igniter.compose_task("bb_mcp.install")
      |> apply_igniter!()
      |> Igniter.compose_task("bb_mcp.install")
      |> assert_unchanged()
    end

    test "running twice produces no further changes (Phoenix)" do
      test_project(files: %{"lib/test_web/router.ex" => @router})
      |> Igniter.compose_task("bb_mcp.install")
      |> apply_igniter!()
      |> Igniter.compose_task("bb_mcp.install")
      |> assert_unchanged()
    end
  end
end
