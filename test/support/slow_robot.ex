# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.MCP.SlowRobot do
  @moduledoc """
  A robot with a command that stays running until told to stop, so the state
  resource and tool can be read while a command is in flight.
  """

  defmodule SlowHandler do
    @moduledoc false
    use BB.Command

    @impl BB.Command
    def handle_command(_goal, _context, state), do: {:noreply, state}

    @impl BB.Command
    def handle_info(:finish, state), do: {:stop, :normal, state}
    def handle_info(_message, state), do: {:noreply, state}

    @impl BB.Command
    def result(state), do: {:ok, state.result}
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
    command :slow do
      handler(SlowHandler)
      allowed_states([:idle])
    end
  end
end
