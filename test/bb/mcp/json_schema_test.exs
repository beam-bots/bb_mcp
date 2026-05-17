# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.MCP.JsonSchemaTest do
  use ExUnit.Case, async: true

  alias BB.Dsl.Command
  alias BB.Dsl.Command.Argument
  alias BB.MCP.JsonSchema

  describe "for_argument/1" do
    test "maps primitive types to JSON Schema types" do
      assert JsonSchema.for_argument(%Argument{type: :integer}) == %{"type" => "integer"}
      assert JsonSchema.for_argument(%Argument{type: :float}) == %{"type" => "number"}
      assert JsonSchema.for_argument(%Argument{type: :string}) == %{"type" => "string"}
      assert JsonSchema.for_argument(%Argument{type: :boolean}) == %{"type" => "boolean"}
      assert JsonSchema.for_argument(%Argument{type: :atom}) == %{"type" => "string"}
      assert JsonSchema.for_argument(%Argument{type: :map}) == %{"type" => "object"}
    end

    test "carries doc and default through" do
      arg = %Argument{type: :integer, doc: "duration in ms", default: 1000}
      schema = JsonSchema.for_argument(arg)

      assert schema["type"] == "integer"
      assert schema["description"] == "duration in ms"
      assert schema["default"] == 1000
    end

    test "module types become descriptions" do
      schema = JsonSchema.for_argument(%Argument{type: BB.Pose})
      assert schema == %{"description" => "complex type: BB.Pose"}
    end

    test "list types nest correctly" do
      schema = JsonSchema.for_argument(%Argument{type: {:list, :integer}})
      assert schema == %{"type" => "array", "items" => %{"type" => "integer"}}
    end
  end

  describe "for_command/1" do
    test "builds an object schema with required arguments" do
      command = %Command{
        name: :wave,
        arguments: [
          %Argument{name: :cycles, type: :integer, required: true, doc: "number of cycles"},
          %Argument{name: :speed, type: :float, required: false, default: 1.0}
        ]
      }

      schema = JsonSchema.for_command(command)

      assert schema["type"] == "object"
      assert schema["required"] == ["cycles"]
      assert schema["properties"]["cycles"]["type"] == "integer"
      assert schema["properties"]["cycles"]["description"] == "number of cycles"
      assert schema["properties"]["speed"]["type"] == "number"
      assert schema["properties"]["speed"]["default"] == 1.0
    end

    test "omits the required field when no arguments are required" do
      command = %Command{name: :ping, arguments: []}
      schema = JsonSchema.for_command(command)
      refute Map.has_key?(schema, "required")
      assert schema == %{"type" => "object", "properties" => %{}}
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

      schema = JsonSchema.for_command(command)

      assert schema["required"] == ["target.x", "target.y", "target.z"]
      assert schema["properties"]["target.x"] == %{"type" => "number"}
      assert schema["properties"]["target.y"] == %{"type" => "number"}
      assert schema["properties"]["target.z"] == %{"type" => "number"}
    end
  end
end
