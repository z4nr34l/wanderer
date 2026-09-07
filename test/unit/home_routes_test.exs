defmodule WandererApp.Map.HomeRoutesTest do
  @moduledoc """
  Reading a route home: where it leaves k-space, and what the k-space part of it flies through.
  """

  use ExUnit.Case, async: true

  alias WandererApp.Map.HomeRoutes
  alias WandererApp.Map.HomeRoutesNotifier

  @jita 30_000_142
  @perimeter 30_000_144
  @home 31_001_269
  @hole 31_000_556

  describe "split_at_chain/1" do
    test "takes the first k-space system, which is where the chain is entered" do
      # the route builder hands the systems back starting at home
      assert {@perimeter, [@perimeter, @jita]} =
               HomeRoutes.split_at_chain([@hole, @perimeter, @jita])
    end

    test "a route that never leaves the chain has no entrance to name" do
      assert :error = HomeRoutes.split_at_chain([@hole, @home])
      assert :error = HomeRoutes.split_at_chain([])
    end

    test "the whole route counts as the k-space leg when it starts outside the chain" do
      assert {@perimeter, [@perimeter, @jita]} = HomeRoutes.split_at_chain([@perimeter, @jita])
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

  describe "format_message/2" do
    test "one line per hub: the whole trip, and where the chain is entered" do
      entries = [
        %{hub_name: "Jita", entrance_name: "Perimeter", jumps: 11, security: :high},
        %{hub_name: "C-J6MT", entrance_name: "Eha", jumps: 12, security: :mixed},
        %{hub_name: "Hek", entrance_name: "Barkrik", jumps: 16, security: :low}
      ]

      assert HomeRoutes.format_message("J164751", entries) == """
             **Way home to J164751**
             Jita: 11J via Perimeter (high sec only)
             C-J6MT: 12J via Eha
             Hek: 16J via Barkrik (low/null only)\
             """
    end

    test "says nothing when no hub can reach home" do
      refute HomeRoutes.format_message("J164751", [])
    end
  end

  describe "route_settings/0" do
    test "somebody else's holes do not count towards the way home" do
      assert %{include_thera: false} = HomeRoutes.route_settings()
    end
  end

  describe "build/4" do
    test "a map with no hubs cannot answer" do
      assert {:error, :no_hubs} = HomeRoutes.build("map", [], @home)
    end

    test "a map without a home cannot answer" do
      assert {:error, :no_home_system} = HomeRoutes.build("map", [@jita], nil)
    end

    test "home being one of the hubs is not a route" do
      assert {:ok, []} = HomeRoutes.build("map", [@home], @home)
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
