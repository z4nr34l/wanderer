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

  describe "format_message/3" do
    test "one line per route, with what it flies through and what is left" do
      entries = [
        %{solar_system_id: @jita, name: "Jita", jumps: 5, holes: 1, security: :high},
        %{solar_system_id: @amarr, name: "Amarr", jumps: 7, holes: nil, security: :mixed},
        %{solar_system_id: @rens, name: "Rens", jumps: 9, holes: 3, security: :low}
      ]

      assert HomeRoutes.format_message("Jita", "J164751", entries) == """
             **Jita → J164751**
             5J via Jita (high sec only, then 1 hole)
             7J via Amarr
             9J via Rens (low/null only, then 3 holes)\
             """
    end

    test "says nothing when there is nowhere to go" do
      refute HomeRoutes.format_message("Jita", "J164751", [])
    end
  end

  describe "build/4" do
    test "a map without a hub or a home has no answer" do
      assert {:error, :no_home_system} = HomeRoutes.build("map", nil, 31_001_269)
      assert {:error, :no_home_system} = HomeRoutes.build("map", 30_000_142, nil)
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
