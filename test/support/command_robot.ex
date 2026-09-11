# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.MCP.CommandRobot do
  @moduledoc """
  A robot with a command that keeps running until it is told to stop, for
  exercising the tools that list and cancel in-flight commands.
  """

  defmodule LingeringHandler do
    @moduledoc false
    use BB.Command

    @impl BB.Command
    def handle_command(%{notify: pid}, _context, state) do
      send(pid, {:executing, self()})
      {:noreply, state}
    end

    @impl BB.Command
    def result(_state), do: {:error, :cancelled}
  end

  use BB

  topology do
    link(:base)
  end

  commands do
    command :arm do
      handler(BB.Command.Arm)
      allowed_states([:disarmed])
    end

    command :linger do
      handler(LingeringHandler)
      allowed_states([:idle])

      argument :notify, :any do
        required(true)
      end
    end
  end
end
