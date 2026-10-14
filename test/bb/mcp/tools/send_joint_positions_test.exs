# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.MCP.Tools.SendJointPositionsTest do
  use ExUnit.Case, async: false

  alias Anubis.MCP.Error
  alias Anubis.Server.Frame
  alias Anubis.Server.Response
  alias BB.MCP.PlanarRobot
  alias BB.MCP.Tools.SendJointPositions
  alias BB.Safety

  defmodule LaggingActuator do
    @moduledoc false
    # Holds every command until the test sends it `:release`, so it can't
    # answer before the caller gives up, however long the caller waits.
    use BB.Actuator, options_schema: []

    @impl BB.Actuator
    def disarm(_opts), do: :ok

    @impl BB.Actuator
    def init(opts) do
      bb = Keyword.fetch!(opts, :bb)
      {:ok, %{recipient: :persistent_term.get({__MODULE__, bb.robot})}}
    end

    @impl BB.Actuator
    def handle_command(message, state) do
      send(state.recipient, {:holding, self(), message})

      receive do
        :release -> send(state.recipient, {:applied, message})
      end

      {:noreply, state}
    end
  end

  defmodule AbsentActuator do
    @moduledoc false
    use BB.Actuator, options_schema: []

    @impl BB.Actuator
    def disarm(_opts), do: :ok

    @impl BB.Actuator
    def init(_opts), do: :ignore
  end

  defmodule SluggishRobot do
    @moduledoc false
    use BB
    import BB.Unit

    topology do
      link :base do
        joint :lagging do
          type(:revolute)

          limit do
            effort(~u(1 newton_meter))
            velocity(~u(90 degree_per_second))
          end

          actuator(:lagging_servo, LaggingActuator)
          link(:lagging_arm)
        end

        joint :absent do
          type(:revolute)

          limit do
            effort(~u(1 newton_meter))
            velocity(~u(90 degree_per_second))
          end

          actuator(:absent_servo, AbsentActuator)
          link(:absent_arm)
        end
      end
    end
  end

  setup do
    original = Application.get_env(:bb_mcp, :robots, [])
    Application.put_env(:bb_mcp, :robots, [PlanarRobot, SluggishRobot])
    on_exit(fn -> Application.put_env(:bb_mcp, :robots, original) end)

    start_supervised!({PlanarRobot, [simulation: :kinematic]})
    :ok = Safety.arm(PlanarRobot)

    {:ok, frame: Frame.new()}
  end

  # A planar joint's configuration is a whole 2D pose, so a scalar leaves two
  # of its three numbers unsaid. Accepting one and reporting `ok` would tell an
  # agent the robot moved when nothing did.
  test "refuses a single position for a joint with more than one degree of freedom",
       %{frame: frame} do
    assert {:error, %Error{} = error, ^frame} =
             SendJointPositions.execute(
               %{robot: "planar_robot", joint: "ground", position: 0.5},
               frame
             )

    assert error.data.message =~ "ground"
    assert error.data.message =~ "3 degrees of freedom"
  end

  test "refuses a joint that has no actuators to drive it", %{frame: frame} do
    assert {:error, %Error{} = error, ^frame} =
             SendJointPositions.execute(
               %{robot: "planar_robot", joint: "shoulder", position: 0.5},
               frame
             )

    assert error.data.message =~ "no actuators"
  end

  describe "an actuator that has not answered in time" do
    setup :start_sluggish_robot

    # Its command is still queued and will most likely be applied, so calling
    # the move a failure would invite an agent to send it again, queueing a
    # second copy behind the first.
    test "is reported as pending rather than as a failure", %{frame: frame} do
      assert {:reply, %Response{isError: false} = response, ^frame} =
               SendJointPositions.execute(
                 %{robot: "sluggish_robot", joint: "lagging", position: 0.5},
                 frame
               )

      assert %{"status" => "pending", "message" => message} = decode_payload(response)
      assert message =~ "lagging_servo"
      assert message =~ "will most likely be applied"

      assert_receive {:holding, actuator, _message}
      send(actuator, :release)
      assert_receive {:applied, _message}
    end
  end

  describe "an actuator that is not running" do
    setup :start_sluggish_robot

    test "is reported as a failure", %{frame: frame} do
      assert {:error, %Error{} = error, ^frame} =
               SendJointPositions.execute(
                 %{robot: "sluggish_robot", joint: "absent", position: 0.5},
                 frame
               )

      assert error.data.error_type == "BB.Error.State.ActuatorNotRunning"
      assert error.message =~ "absent_servo"
    end
  end

  defp start_sluggish_robot(_context) do
    :persistent_term.put({LaggingActuator, SluggishRobot}, self())
    start_supervised!(SluggishRobot)
    :ok = Safety.arm(SluggishRobot)
    :ok
  end

  defp decode_payload(%Response{content: [%{"text" => json}]}), do: Jason.decode!(json)
end
