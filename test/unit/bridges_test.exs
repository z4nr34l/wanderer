defmodule WandererApp.Map.BridgesTest do
  @moduledoc """
  Reading a pasted bridge list, and which bridges a route may use.
  """

  use ExUnit.Case, async: true

  alias WandererApp.Map.Bridges

  describe "parse_line/1" do
    test "takes the shapes a copy produces" do
      for line <- [
            "UALX-3 » 1DQ1-A",
            "UALX-3 >> 1DQ1-A",
            "UALX-3 -> 1DQ1-A",
            "UALX-3 => 1DQ1-A",
            "UALX-3 <-> 1DQ1-A",
            "UALX-3, 1DQ1-A",
            "UALX-3; 1DQ1-A",
            "UALX-3\t1DQ1-A",
            "UALX-3 | 1DQ1-A",
            "UALX-3 - 1DQ1-A"
          ] do
        assert {:ok, %{source: "UALX-3", target: "1DQ1-A"}} = Bridges.parse_line(line)
      end
    end

    test "drops the structure name the game puts behind the systems" do
      assert {:ok, %{source: "UALX-3", target: "1DQ1-A"}} =
               Bridges.parse_line("UALX-3 » 1DQ1-A - Ansiblex Jump Gate")
    end

    test "drops what a copy brings along in brackets" do
      assert {:ok, %{source: "UALX-3", target: "1DQ1-A"}} =
               Bridges.parse_line("UALX-3 (0.0) » 1DQ1-A (0.0)")
    end

    test "a line that names one system is not a bridge" do
      assert :error = Bridges.parse_line("UALX-3")
      assert :error = Bridges.parse_line("UALX-3 » UALX-3")
      assert :error = Bridges.parse_line("» 1DQ1-A")
    end
  end

  describe "parse/1" do
    test "keeps the lines it could not read instead of dropping them quietly" do
      text = """
      # our bridges
      UALX-3 » 1DQ1-A

      nonsense line
      T5ZI-S -> 1DQ1-A
      """

      assert %{pairs: pairs, unreadable: ["nonsense line"]} = Bridges.parse(text)

      assert pairs == [
               %{source: "UALX-3", target: "1DQ1-A"},
               %{source: "T5ZI-S", target: "1DQ1-A"}
             ]
    end
  end

  describe "parse/1 on an alliance's own bridge list" do
    test "reads the arrow and the grid marker such a list is written with" do
      text = """
      PQRE-W 1-1  -->  A-7XFN 3-1
      H-FGJO 2-1  -->  G3D-ZT 2-1
      """

      assert %{pairs: pairs, unreadable: []} = Bridges.parse(text)

      assert pairs == [
               %{source: "PQRE-W", target: "A-7XFN"},
               %{source: "H-FGJO", target: "G3D-ZT"}
             ]
    end

    test "leaves a system whose whole name reads like a marker alone" do
      # 5-3722 is a real system, not a grid reference
      assert {:ok, %{source: "5-3722", target: "X-7OMU"}} =
               Bridges.parse_line("5-3722 --> X-7OMU")

      assert {:ok, %{source: "5-3722", target: "X-7OMU"}} =
               Bridges.parse_line("5-3722 2-1 --> X-7OMU 1-1")
    end
  end

  describe "route_pairs/2" do
    setup do
      map_id = Ecto.UUID.generate()
      %{map_id: map_id}
    end

    test "a map with no bridges offers none", %{map_id: map_id} do
      assert [] = Bridges.route_pairs(map_id, %{})
    end

    test "bridges turned off means none of them count", %{map_id: map_id} do
      assert [] = Bridges.route_pairs(map_id, %{include_bridges: false})
    end
  end
end
