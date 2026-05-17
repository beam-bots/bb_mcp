# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.MCP.PeriSchemaTest do
  use ExUnit.Case, async: true

  alias BB.Dsl.Command
  alias BB.Dsl.Command.Argument
  alias BB.MCP.PeriSchema

  describe "for_argument/1" do
    test "maps :integer to :integer" do
      assert PeriSchema.for_argument(%Argument{type: :integer}) == :integer
    end

    test "maps :float and :number to :float" do
      assert PeriSchema.for_argument(%Argument{type: :float}) == :float
      assert PeriSchema.for_argument(%Argument{type: :number}) == :float
    end

    test "maps :string, :boolean, :atom, :map verbatim" do
      assert PeriSchema.for_argument(%Argument{type: :string}) == :string
      assert PeriSchema.for_argument(%Argument{type: :boolean}) == :boolean
      assert PeriSchema.for_argument(%Argument{type: :atom}) == :atom
      assert PeriSchema.for_argument(%Argument{type: :map}) == :map
    end

    test "falls back to :any for module / unknown types" do
      assert PeriSchema.for_argument(%Argument{type: BB.Pose}) == :any
      assert PeriSchema.for_argument(%Argument{type: :weird}) == :any
    end

    test "wraps with :required when the argument is required" do
      assert PeriSchema.for_argument(%Argument{type: :integer, required: true}) ==
               {:required, :integer}
    end

    test "applies default with the Peri {type, {:default, v}} shape" do
      assert PeriSchema.for_argument(%Argument{type: :integer, default: 1000}) ==
               {:integer, {:default, 1000}}
    end

    test "wraps with :meta when a doc string is set" do
      schema = PeriSchema.for_argument(%Argument{type: :string, doc: "name"})
      assert schema == {:meta, :string, description: "name"}
    end

    test "default + doc + required compose in the expected order" do
      schema =
        PeriSchema.for_argument(%Argument{
          type: :integer,
          default: 1000,
          doc: "ms",
          required: true
        })

      # required wraps meta, which wraps default, which wraps base
      assert schema ==
               {:required, {:meta, {:integer, {:default, 1000}}, description: "ms"}}
    end
  end

  describe "for_command/1" do
    test "produces a map keyed by argument name" do
      command = %Command{
        name: :wave,
        arguments: [
          %Argument{name: :cycles, type: :integer, required: true, doc: "n"},
          %Argument{name: :speed, type: :float, required: false, default: 1.0}
        ]
      }

      schema = PeriSchema.for_command(command)

      assert schema == %{
               cycles: {:required, {:meta, :integer, description: "n"}},
               speed: {:float, {:default, 1.0}}
             }
    end

    test "handles commands with no arguments" do
      assert PeriSchema.for_command(%Command{name: :ping, arguments: []}) == %{}
    end

    test "flattens typed map arguments with dotted keys" do
      command = %Command{
        name: :move_to_pose,
        arguments: [
          %Argument{
            name: :target,
            type:
              {:map,
               [
                 x: [type: :float, required: true],
                 y: [type: :float, required: true],
                 z: [type: :float, required: true]
               ]},
            required: true
          }
        ]
      }

      assert PeriSchema.for_command(command) == %{
               "target.x" => {:required, :float},
               "target.y" => {:required, :float},
               "target.z" => {:required, :float}
             }

      assert PeriSchema.to_goal(command, %{
               "target.x" => 1.0,
               "target.y" => 2.0,
               "target.z" => 3.0
             }) == %{
               target: %{"x" => 1.0, "y" => 2.0, "z" => 3.0}
             }
    end
  end

  describe "flatten_nested_params/2" do
    setup do
      command = %Command{
        name: :move_to_pose,
        arguments: [
          %Argument{
            name: :target,
            type:
              {:map,
               [
                 x: [type: :float, required: true],
                 y: [type: :float, required: true],
                 z: [type: :float, required: true]
               ]},
            required: true
          },
          %Argument{name: :speed, type: :float, required: false}
        ]
      }

      {:ok, command: command}
    end

    test "rewrites a nested object for a map argument into dotted keys", %{command: cmd} do
      assert PeriSchema.flatten_nested_params(cmd, %{
               "target" => %{"x" => 1.0, "y" => 2.0, "z" => 3.0},
               "speed" => 0.5
             }) == %{
               "target.x" => 1.0,
               "target.y" => 2.0,
               "target.z" => 3.0,
               "speed" => 0.5
             }
    end

    test "leaves already-dotted params unchanged", %{command: cmd} do
      params = %{"target.x" => 1.0, "target.y" => 2.0, "target.z" => 3.0}
      assert PeriSchema.flatten_nested_params(cmd, params) == params
    end

    test "ignores non-map arguments", %{command: cmd} do
      params = %{"speed" => 0.5}
      assert PeriSchema.flatten_nested_params(cmd, params) == params
    end

    test "handles atom-keyed nested values", %{command: cmd} do
      assert PeriSchema.flatten_nested_params(cmd, %{
               target: %{x: 1.0, y: 2.0, z: 3.0}
             }) == %{
               "target.x" => 1.0,
               "target.y" => 2.0,
               "target.z" => 3.0
             }
    end

    test "coerces integer values to floats for :float fields (JSON has no 0 vs 0.0)",
         %{command: cmd} do
      assert PeriSchema.flatten_nested_params(cmd, %{
               "target" => %{"x" => 0.15, "y" => 0, "z" => 0.15}
             }) == %{
               "target.x" => 0.15,
               "target.y" => 0.0,
               "target.z" => 0.15
             }
    end

    test "leaves integer values alone for :integer fields" do
      command = %Command{
        name: :wave,
        arguments: [
          %Argument{name: :cycles, type: :integer, required: true},
          %Argument{name: :speed, type: :float, required: false}
        ]
      }

      assert PeriSchema.flatten_nested_params(command, %{
               "cycles" => 5,
               "speed" => 1
             }) == %{
               "cycles" => 5,
               "speed" => 1.0
             }
    end
  end
end
