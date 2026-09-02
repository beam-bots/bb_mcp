# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.MCP.JsonTest do
  use ExUnit.Case, async: true

  alias BB.Math.Vec3
  alias BB.MCP.Json

  test "leaves values JSON already carries alone" do
    assert Json.encodable(1) == 1
    assert Json.encodable(1.5) == 1.5
    assert Json.encodable(true) == true
    assert Json.encodable(nil) == nil
    assert Json.encodable("hello") == "hello"
  end

  test "renders atoms without their leading colon" do
    assert Json.encodable(:idle) == "idle"
    assert Json.encodable(%{state: :armed}) == %{"state" => "armed"}
  end

  test "renders a module atom the way it was written" do
    assert Json.encodable(BB.MCP.Json) == "BB.MCP.Json"
    assert Json.encodable(%{handler: BB.Command.Arm}) == %{"handler" => "BB.Command.Arm"}
  end

  test "leaves a struct that encodes itself to do so" do
    encoded = %{at: ~U[2026-09-02 08:00:00Z]} |> Json.encodable() |> JSON.encode!()

    assert encoded == ~s({"at":"2026-09-02T08:00:00Z"})
  end

  test "renders references and pids, which JSON has no encoding for" do
    assert Json.encodable(make_ref()) =~ "#Reference<"
    assert Json.encodable(self()) =~ "#PID<"
  end

  test "renders an exception as its message" do
    assert Json.encodable(%RuntimeError{message: "kaboom"}) == "kaboom"
  end

  test "renders a unit as the magnitude and unit name set_parameter accepts" do
    assert Json.encodable(Localize.Unit.new!(45, "degree")) ==
             %{"value" => 45, "unit" => "degree"}
  end

  test "renders a tensor-backed value rather than recursing into it" do
    assert Json.encodable(Vec3.new(1.0, 2.0, 3.0)) |> JSON.encode!()
  end

  test "turns tuples into lists" do
    assert Json.encodable({:joint, :shoulder}) == ["joint", "shoulder"]
  end

  test "walks structs into objects" do
    assert Json.encodable(%{outer: %{inner: [{:a, 1}]}}) ==
             %{"outer" => %{"inner" => [["a", 1]]}}
  end

  test "replaces a binary too long or too binary to read with its size" do
    assert Json.encodable(<<0xFF, 0xFE>>) == "<2 bytes>"
    assert Json.encodable(String.duplicate("a", 65)) == "<65 bytes>"
  end
end
