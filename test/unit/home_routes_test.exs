defmodule WandererApp.Map.HomeRoutesTest do
  @moduledoc """
  Picking the mouths of a chain and saying how far they are. The parts that talk to the route
  builder are left out - what is tested here is what goes in and what comes back out.
  """

  use ExUnit.Case, async: true

  alias WandererApp.Map.HomeRoutes
  alias WandererApp.Map.HomeRoutesNotifier

  defp system(id, visible \\ true), do: %{solar_system_id: id, visible: visible}

  defp connection(source, target),
    do: %{solar_system_source: source, solar_system_target: target}

  # J-space ids start at 31_000_000
  @jita 30_000_142
  @amarr 30_002_187
  @rens 30_002_510
  @hole 31_000_001
  @deeper_hole 31_000_002

  describe "entrances/2" do
    test "takes the k-space side of a hole" do
      systems = [system(@jita), system(@hole)]

      assert HomeRoutes.entrances(systems, [connection(@hole, @jita)]) == [@jita]
      assert HomeRoutes.entrances(systems, [connection(@jita, @hole)]) == [@jita]
    end

    test "ignores gates and holes that stay inside the chain" do
      systems = [system(@jita), system(@amarr), system(@hole), system(@deeper_hole)]

      connections = [connection(@jita, @amarr), connection(@hole, @deeper_hole)]

      assert HomeRoutes.entrances(systems, connections) == []
    end

    test "names a system once however many holes it has" do
      systems = [system(@jita), system(@hole), system(@deeper_hole)]

      connections = [connection(@hole, @jita), connection(@deeper_hole, @jita)]

      assert HomeRoutes.entrances(systems, connections) == [@jita]
    end

    test "leaves out systems that are not shown on the map" do
      systems = [system(@jita, false), system(@amarr), system(@hole)]

      connections = [connection(@hole, @jita), connection(@hole, @amarr)]

      assert HomeRoutes.entrances(systems, connections) == [@amarr]
    end
  end

  describe "security_label/1" do
    test "0.45 is high sec, because that is what the game rounds up" do
      assert HomeRoutes.security_label([0.45, 0.9]) == :high
      assert HomeRoutes.security_label([0.4]) == :low
    end

    test "a single low sec system makes the whole route mixed" do
      assert HomeRoutes.security_label([0.9, 0.5, 0.3]) == :mixed
    end

    test "nothing known is not a claim about anything" do
      assert HomeRoutes.security_label([]) == :mixed
    end
  end

  describe "hole_depths/2" do
    test "counts the holes between home and everything the chain reaches" do
      connections = [
        connection(@hole, @deeper_hole),
        connection(@deeper_hole, @jita),
        connection(@hole, @amarr)
      ]

      depths = HomeRoutes.hole_depths(connections, @hole)

      assert depths[@hole] == 0
      assert depths[@deeper_hole] == 1
      assert depths[@amarr] == 1
      assert depths[@jita] == 2
    end

    test "a mouth on a piece of chain nobody joined to home is not counted" do
      connections = [connection(@hole, @amarr), connection(@deeper_hole, @jita)]

      depths = HomeRoutes.hole_depths(connections, @hole)

      refute Map.has_key?(depths, @jita)
    end

    test "the shorter way round wins" do
      connections = [
        connection(@hole, @deeper_hole),
        connection(@deeper_hole, @jita),
        connection(@hole, @jita)
      ]

      assert HomeRoutes.hole_depths(connections, @hole)[@jita] == 1
    end
  end

  describe "ways_home/3" do
    test "keeps the mouths that lead home apart from the ones that do not" do
      systems = [system(@jita), system(@amarr), system(@hole), system(@deeper_hole)]

      connections = [
        # home - hole - jita
        connection(@hole, @deeper_hole),
        connection(@deeper_hole, @jita),
        # a mouth on somebody else's chain, sitting on the same map
        connection(@amarr, 31_000_009)
      ]

      assert {[@jita], [@amarr], depths} = HomeRoutes.ways_home(systems, connections, @hole)
      assert depths[@jita] == 2
      refute Map.has_key?(depths, @amarr)
    end

    test "a chain with no k-space mouth at all has neither" do
      systems = [system(@hole), system(@deeper_hole)]

      assert {[], [], _depths} =
               HomeRoutes.ways_home(systems, [connection(@hole, @deeper_hole)], @hole)
    end
  end

  describe "format_message/2" do
    test "one line per mouth, with the nearest hub and what is left behind it" do
      entries = [
        %{
          hub_name: "Jita",
          solar_system_id: @amarr,
          name: "Amarr",
          jumps: 5,
          holes: 1,
          security: :high
        },
        %{
          hub_name: "Rens",
          solar_system_id: @rens,
          name: "Hek",
          jumps: 7,
          holes: 2,
          security: :mixed
        },
        %{
          hub_name: "Dodixie",
          solar_system_id: @jita,
          name: "Villore",
          jumps: 9,
          holes: 3,
          security: :low
        }
      ]

      assert HomeRoutes.format_message("J164751", %{home: entries, unlinked: []}) == """
             **Way home to J164751**
             Amarr: 5J from Jita (high sec only, then 1 hole)
             Hek: 7J from Rens (then 2 holes)
             Villore: 9J from Dodixie (low/null only, then 3 holes)\
             """
    end

    test "says nothing when the map has no mouth at all" do
      refute HomeRoutes.format_message("J164751", %{home: [], unlinked: []})
    end

    test "a mouth nobody has joined to home is still worth naming, but kept apart" do
      unlinked = [
        %{
          hub_name: "Jita",
          solar_system_id: @jita,
          name: "Perimeter",
          jumps: 1,
          holes: nil,
          security: :high
        }
      ]

      message = HomeRoutes.format_message("J164751", %{home: [], unlinked: unlinked})

      assert message == """
             **Way home to J164751**
             Nothing on the map leads home yet.

             Mouths not joined to home on the map yet:
             Perimeter: 1J from Jita (high sec only)\
             """
    end
  end

  describe "build/4" do
    test "a map with no hubs cannot answer" do
      assert {:error, :no_hubs} = HomeRoutes.build("map", [], 31_001_269)
    end

    test "a map without a home cannot answer" do
      assert {:error, :no_home_system} = HomeRoutes.build("map", [30_000_142], nil)
    end
  end

  describe "notifier" do
    setup do
      start_supervised!(HomeRoutesNotifier)
      :ok
    end

    test "scanning restarts the quiet period" do
      assert :ok = HomeRoutesNotifier.map_changed("map-1", :add_system)

      assert %{timers: %{"map-1" => first}} = :sys.get_state(HomeRoutesNotifier)

      assert :ok = HomeRoutesNotifier.map_changed("map-1", :connection_added)

      assert %{timers: %{"map-1" => second}} = :sys.get_state(HomeRoutesNotifier)
      assert first != second
    end

    test "characters moving about are not a change to the chain" do
      assert :ok = HomeRoutesNotifier.map_changed("map-2", :character_updated)
      assert :ok = HomeRoutesNotifier.map_changed("map-2", :map_kill)

      assert %{timers: timers} = :sys.get_state(HomeRoutesNotifier)
      refute Map.has_key?(timers, "map-2")
    end
  end
end
