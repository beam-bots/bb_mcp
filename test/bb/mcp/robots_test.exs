# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.MCP.RobotsTest do
  use ExUnit.Case, async: true

  alias BB.MCP.Robots

  describe "name_for/1" do
    test "uses the last module segment, snake-cased" do
      assert Robots.name_for(MyApp.WX200) == "wx200"
      assert Robots.name_for(MyApp.SO101) == "so101"
      assert Robots.name_for(MyApp.TwoWord) == "two_word"
      assert Robots.name_for(SingleName) == "single_name"
    end
  end

  describe "build!/1" do
    test "builds a name → module map from a list of modules" do
      config = Robots.build!([MyApp.WX200, MyApp.SO101])

      assert config == %{
               "wx200" => MyApp.WX200,
               "so101" => MyApp.SO101
             }
    end

    test "raises on name collision between distinct modules" do
      assert_raise ArgumentError, ~r/robot name collision/, fn ->
        Robots.build!([MyApp.WX200, OtherApp.WX200])
      end
    end

    test "tolerates duplicate modules" do
      assert %{"wx200" => MyApp.WX200} =
               Robots.build!([MyApp.WX200, MyApp.WX200])
    end
  end

  describe "fetch/2" do
    test "returns {:ok, module} for known names" do
      config = Robots.build!([MyApp.WX200])
      assert Robots.fetch(config, "wx200") == {:ok, MyApp.WX200}
    end

    test "returns {:error, :unknown_robot} for unknown names" do
      assert Robots.fetch(%{}, "nope") == {:error, :unknown_robot}
    end
  end

  describe "to_list/1" do
    test "returns sorted {name, module} tuples" do
      config = Robots.build!([MyApp.WX200, MyApp.SO101])
      assert Robots.to_list(config) == [{"so101", MyApp.SO101}, {"wx200", MyApp.WX200}]
    end
  end
end
