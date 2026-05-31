<!--
SPDX-FileCopyrightText: 2026 James Harton

SPDX-License-Identifier: Apache-2.0
-->

<img src="https://github.com/beam-bots/bb/blob/main/logos/beam_bots_logo.png?raw=true" alt="Beam Bots Logo" width="250" />

# BB.MCP

[![CI](https://github.com/beam-bots/bb_mcp/actions/workflows/ci.yml/badge.svg)](https://github.com/beam-bots/bb_mcp/actions/workflows/ci.yml)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache--2.0-green.svg)](https://opensource.org/licenses/Apache-2.0)
[![Hex version badge](https://img.shields.io/hexpm/v/bb_mcp.svg)](https://hex.pm/packages/bb_mcp)
[![Hexdocs badge](https://img.shields.io/badge/docs-hexdocs-purple)](https://hexdocs.pm/bb_mcp)
[![REUSE status](https://api.reuse.software/badge/github.com/beam-bots/bb_mcp)](https://api.reuse.software/info/github.com/beam-bots/bb_mcp)
[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/beam-bots/bb_mcp)

Model Context Protocol (MCP) server for [Beam Bots](https://github.com/beam-bots/bb) robots.

`bb_mcp` lets AI agents (Claude Desktop, Claude Code, custom LLM agents) drive
your BB-powered robots over the standard [Model Context
Protocol](https://modelcontextprotocol.io/). Every robot you list at startup
exposes its safety controls, declared commands, runtime parameters, and live
state to any connected MCP client.

## Status

Early. Multi-robot, no authentication — assume a trusted local or LAN
environment.

## Installation

Add `bb_mcp` to your dependencies:

```elixir
def deps do
  [
    {:bb_mcp, "~> 0.1"}
  ]
end
```

Or run the installer:

```bash
mix igniter.install bb_mcp
```

## Usage

List the robots to expose in config:

```elixir
# config/config.exs
config :bb_mcp, robots: [MyApp.WX200, MyApp.SO101]
```

Start the server alongside your robots in the supervision tree:

```elixir
children = [
  MyApp.WX200,
  MyApp.SO101,
  {BB.MCP.Server, transport: :streamable_http, streamable_http: [port: 4000]}
]
```

Or mount it in a Phoenix router (Streamable HTTP transport):

```elixir
defmodule MyAppWeb.Router do
  use Phoenix.Router
  import BB.MCP.Router

  scope "/" do
    bb_mcp "/mcp"
  end
end
```

## What gets exposed

For each robot, agents see:

### Tools

Cross-cutting tools — each takes a `robot` string argument selecting
the target robot:

| Tool                | Source                       |
|---------------------|------------------------------|
| `list_robots`       | configured robots index      |
| `get_state`         | `BB.Safety.state/1` + `BB.Robot.Runtime` |
| `force_disarm`      | `BB.Safety.force_disarm/1`   |
| `list_commands`     | `BB.Dsl.Info.commands/1`     |
| `list_parameters`   | `BB.Parameter.list/2`        |
| `get_parameter`     | `BB.Parameter.get/2`         |
| `set_parameter`     | `BB.Parameter.set/3`         |
| `send_joint_positions` | `BB.Motion.send_positions/3` |
| `query_events`      | per-session `BB.PubSub` ring buffer |

Per-command tools (×N) — one tool per `{robot, command}` pair declared
in each robot's Spark DSL, registered at session startup. Tool name is
`{robot}.{command}` (e.g. `wx200.home`); the input schema is derived
from the command's typed arguments. Dispatch goes through
`BB.Robot.Runtime.execute/3` + `BB.Command.await/2`. The built-in
`arm`/`disarm` commands surface as `{robot}.arm` and `{robot}.disarm`.

### Resources

- `bb://robots` — index of configured robots
- `bb://robots/{robot}/topology` — links, joints, sensors, actuators
- `bb://robots/{robot}/state` — operational state, safety state, running commands
- `bb://robots/{robot}/joints` — current joint positions and velocities
- `bb://robots/{robot}/commands` — declared commands and their argument schemas
- `bb://robots/{robot}/parameters` — registered parameters with current values

## Licence

Apache-2.0. See `LICENSES/Apache-2.0.txt`.
