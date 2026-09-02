# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.MCP.FixtureRobot do
  @moduledoc """
  Minimal BB-DSL robot used for introspection in the bb_mcp test suite.

  Its `commands` block declares a category alongside its commands, because the
  DSL's `commands` section holds both and `BB.Dsl.Info.commands/1` returns them
  together.
  """

  defmodule HomeHandler do
    @moduledoc false
    use BB.Command

    @impl BB.Command
    def handle_command(_goal, _context, state), do: {:stop, :normal, state}

    @impl BB.Command
    def result(state), do: state.result
  end

  defmodule WaveHandler do
    @moduledoc false
    use BB.Command

    @impl BB.Command
    def handle_command(_goal, _context, state), do: {:stop, :normal, state}

    @impl BB.Command
    def result(state), do: state.result
  end

  use BB
  import BB.Unit

  topology do
    link :base do
      joint :shoulder do
        type(:revolute)

        limit do
          lower(~u(-90 degree))
          upper(~u(90 degree))
          effort(~u(1 newton_meter))
          velocity(~u(90 degree_per_second))
        end

        actuator(:motor, BB.Sim.Actuator)
        sensor(:motor_position, {BB.Sensor.OpenLoopPositionEstimator, actuator: :motor})

        link(:arm)
      end
    end
  end

  commands do
    category :motion do
      concurrency_limit(1)
      doc("Commands that move the arm")
    end

    command :arm do
      handler(BB.Command.Arm)
      allowed_states([:disarmed])
    end

    command :disarm do
      handler(BB.Command.Disarm)
      allowed_states([:idle])
    end

    command :go_home do
      handler(HomeHandler)
      allowed_states([:idle])
      category(:motion)

      argument :duration, :integer do
        required(false)
        default(1000)
        doc("Duration in milliseconds")
      end
    end

    command :wave do
      handler(WaveHandler)
      allowed_states([:idle])

      argument :cycles, :integer do
        required(true)
        doc("Number of cycles")
      end

      argument :speed, :float do
        required(false)
        default(1.0)
      end

      argument :style, {:in, [:gentle, :enthusiastic]} do
        required(false)
        default(:gentle)
        doc("How to wave")
      end

      argument :about, :atom do
        required(false)
        doc("Joint to wave about")
      end
    end
  end
end
