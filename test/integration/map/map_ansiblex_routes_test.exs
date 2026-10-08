defmodule WandererApp.Map.AnsiblexRoutesTest do
  @moduledoc """
  What the route graph does with a bridge somebody drew on the map.

  A bridge used to be a road for whoever could see it. Since CCP's Cradle of War update it is a
  road only for the alliance that holds the space it runs through, so the graph has to drop the
  rest rather than offer a jump nobody can fly.
  """

  use WandererApp.DataCase, async: false

  import WandererApp.MapTestHelpers

  alias WandererApp.Map.Routes
  alias WandererApp.Map.Server

  @system_a 30_000_142
  @system_b 30_002_187

  @ours 99_000_001
  @theirs 99_000_002

  setup do
    setup_connection_test_systems()

    map = start_bridged_map()

    on_exit(fn -> WandererApp.Cache.delete(:sovereignty_data_fetcher) end)

    %{map: map}
  end

  describe "unusable_bridge_pairs/2" do
    test "keeps a bridge where our own alliance holds both ends", %{map: map} do
      hold(%{@system_a => @ours, @system_b => @ours})

      assert MapSet.size(Routes.unusable_bridge_pairs(map.map_id, @ours)) == 0
    end

    test "drops a bridge that runs into somebody else's space", %{map: map} do
      hold(%{@system_a => @ours, @system_b => @theirs})

      assert MapSet.size(Routes.unusable_bridge_pairs(map.map_id, @ours)) == 1
    end

    # sovereignty comes from a background fetch, so an empty one must not empty the map
    test "leaves a bridge alone in space nobody holds", %{map: map} do
      hold(%{})

      assert MapSet.size(Routes.unusable_bridge_pairs(map.map_id, @ours)) == 0
    end

    test "takes nothing away from a pilot whose alliance is not known", %{map: map} do
      hold(%{@system_a => @theirs, @system_b => @theirs})

      assert MapSet.size(Routes.unusable_bridge_pairs(map.map_id, nil)) == 0
    end

    # CCP took the Ansiblex away from capitals in the Cradle of War update
    test "a capital flies no bridge, even one of our own", %{map: map} do
      hold(%{@system_a => @ours, @system_b => @ours})

      assert MapSet.size(Routes.unusable_bridge_pairs(map.map_id, @ours, false)) == 0
      assert MapSet.size(Routes.unusable_bridge_pairs(map.map_id, @ours, true)) == 1
    end

    test "their gate is a road for them and not for us", %{map: map} do
      hold(%{@system_a => @theirs, @system_b => @theirs})

      assert MapSet.size(Routes.unusable_bridge_pairs(map.map_id, @theirs)) == 0
      assert MapSet.size(Routes.unusable_bridge_pairs(map.map_id, @ours)) == 1
    end
  end

  defp hold(by_system) do
    WandererApp.Cache.insert(
      :sovereignty_data_fetcher,
      Map.new(by_system, fn {system, alliance} -> {system, %{alliance_id: alliance}} end)
    )
  end

  defp start_bridged_map do
    setup_ddrt_mocks()

    user = insert(:user)
    character = insert(:character, %{user_id: user.id})
    map = insert(:map, %{owner_id: character.id})

    :ok = ensure_map_started(map.id)

    Enum.each([@system_a, @system_b], fn solar_system_id ->
      :ok =
        Server.add_system(
          map.id,
          %{solar_system_id: solar_system_id, coordinates: %{"x" => 0, "y" => 0}},
          user.id,
          character.id
        )

      assert wait_for_system_on_map(map.id, solar_system_id)
    end)

    :ok =
      Server.add_connection(map.id, %{
        solar_system_source_id: @system_a,
        solar_system_target_id: @system_b,
        character_id: character.id
      })

    # the map draws an Ansiblex as a connection of its own type
    Server.update_connection_type(map.id, %{
      solar_system_source_id: @system_a,
      solar_system_target_id: @system_b,
      type: 2
    })

    %{map_id: map.id, user_id: user.id, character_id: character.id}
  end

  defp setup_connection_test_systems do
    setup_system_static_info_cache(%{
      @system_a => %{
        solar_system_id: @system_a,
        solar_system_name: "Jita",
        solar_system_name_lc: "jita",
        region_id: 10_000_002,
        region_name: "The Forge",
        constellation_id: 20_000_020,
        constellation_name: "Kimotoro",
        system_class: 7,
        security: "0.9"
      },
      @system_b => %{
        solar_system_id: @system_b,
        solar_system_name: "Amarr",
        solar_system_name_lc: "amarr",
        region_id: 10_000_043,
        region_name: "Domain",
        constellation_id: 20_000_322,
        constellation_name: "Throne Worlds",
        system_class: 7,
        security: "1.0"
      }
    })
  end
end
