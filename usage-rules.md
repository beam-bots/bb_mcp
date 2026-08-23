<!--
SPDX-FileCopyrightText: 2026 James Harton

SPDX-License-Identifier: Apache-2.0
-->

# BB.MCP Usage Rules

`bb_mcp` is a [Model Context Protocol](https://modelcontextprotocol.io/) server
that exposes running [Beam Bots](https://hexdocs.pm/bb) robots to MCP clients
(Claude Desktop, Claude Code, custom LLM agents). It is **not** a `BB` DSL
component — you never wire it into a robot's `topology`. It runs alongside your
robots and reflects them as MCP tools and resources. For BB framework basics,
see `bb`'s rules (`mix usage_rules.sync <file> bb:all`); this file covers only
how to stand the server up and what it exposes.

## Core principles

1. **The server is a process, not a component.** `BB.MCP.Server` runs as a child
   in your supervision tree (or is mounted into a Phoenix endpoint). It reads
   the robots it exposes from application config, not from its child-spec
   options.
2. **Robots are named by module tail.** Each configured robot is addressed by
   the last segment of its module name, underscored and lowercased —
   `MyApp.WX200` → `"wx200"`, `MyApp.Robot` → `"robot"`. A collision raises at
   startup.
3. **The MCP client can arm and move the robot.** Declared commands (including
   `arm`/`disarm`) and `send_joint_positions` are exposed as callable tools.
   Treat a connected client as an operator with physical control.
4. **No authentication.** Assume a trusted local or LAN environment only.

## Setting it up

List the robots to expose in config:

```elixir
# config/config.exs
config :bb_mcp, robots: [MyApp.WX200, MyApp.SO101]
```

Then either run the server as a supervision child over Streamable HTTP:

```elixir
children = [
  MyApp.WX200,
  MyApp.SO101,
  {BB.MCP.Server, transport: :streamable_http, streamable_http: [port: 4000]}
]

Supervisor.start_link(children, strategy: :one_for_one)
```

Or mount it into a Phoenix router (the endpoint serves the HTTP; `BB.MCP.Server`
must still be in the supervision tree):

```elixir
defmodule MyAppWeb.Router do
  use Phoenix.Router
  import BB.MCP.Router

  scope "/" do
    bb_mcp "/mcp"
  end
end
```

`mix igniter.install bb_mcp` wires whichever of the two applies to your app.

## What gets exposed

**Cross-cutting tools** — each takes a `robot` string argument selecting the
target: `list_robots`, `get_state`, `force_disarm`, `list_commands`,
`list_parameters`, `get_parameter`, `set_parameter`, `send_joint_positions`,
`query_events`. `query_events` reads a per-session ring buffer of `BB.PubSub`
events captured since the session connected.

A parameter declared with a unit type crosses the boundary as an object
carrying the magnitude and the CLDR unit name — `{"value": -12.5, "unit":
"degree"}`. That is what `list_parameters`, `get_parameter` and the parameters
resource report, and what `set_parameter` accepts; a bare number is also
accepted on write and takes the parameter's declared unit.

**Per-command tools** — one per `{robot, command}` pair declared in each robot's
DSL, registered at session start, named `{robot}.{command}` (e.g. `wx200.home`,
`wx200.arm`). Input schema is derived from the command's typed arguments;
dispatch goes through `BB.Robot.Runtime.execute/3` + `BB.Command.await/2`.

**Resources** — URI-templated by robot name: `bb://robots`,
`bb://robots/{robot}/topology`, `/state`, `/joints`, `/commands`,
`/parameters`.

## Config

| Key | Default | Meaning |
|---|---|---|
| `:robots` | `[]` | Robot modules to expose (required to expose anything) |
| `:event_buffer_size` | `1000` | Per-session `query_events` ring-buffer capacity |

## Anti-patterns

- **Don't pass `robots:` in the child spec.** The server reads its robot list
  from `config :bb_mcp, robots: [...]`; options given to `{BB.MCP.Server, ...}`
  are transport options only. Setting `robots:` there does nothing.
- **Don't expose the server on an untrusted network.** There is no auth; any
  connected client can invoke `arm` and `send_joint_positions` and drive real
  hardware. Bind it to localhost/LAN behind your own access control.
- **Don't expect motion before arming.** A robot starts `:disarmed` and refuses
  motion; `send_joint_positions` requires `:armed` + `:idle`. The client arms
  via the `{robot}.arm` tool, which runs the robot's prearm checks — the server
  never pokes `BB.Safety` to change state. Use `force_disarm` only to clear the
  `:error` state.

## Further reading

- [bb_mcp docs](https://hexdocs.pm/bb_mcp)
- `bb`'s safety rules (`bb:safety-and-commands`) and
  [Understanding Safety](https://hexdocs.pm/bb/understanding-safety.html)
