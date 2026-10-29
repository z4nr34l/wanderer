defmodule WandererApp.Map.KspaceJumpConnectionsTest do
  @moduledoc """
  Integration tests for tracked moves between k-space systems with no stargate between them.

  Such a move used to be taken for a wormhole every time. In null-sec most of them are jump
  bridge jumps or jump-drive jumps, which must not draw a wormhole connection, nor bring in the
  systems a wormhole would have. A real k-space wormhole, a stargate jump and a connection added
  by hand are left as they were.
  """

  use WandererApp.IntegrationCase, async: false

  # These tests start real map servers, see WandererApp.IntegrationCase.
  @moduletag :shared_sandbox

  import Mox

  setup :verify_on_exit!

  import WandererApp.MapTestHelpers

  alias WandererApp.Map.Server.CharactersImpl
  alias WandererApp.Map.Server.ConnectionsImpl

  @connection_type_wormhole 0
  @connection_type_stargate 1

  # SAI-T9 and Y-FZ5N, a jump bridge pair on a real map
  @sai_t9 30_000_508
  @y_fz5n 30_002_162
  # 8-WYQZ and E-JCUS, no stargate and no bridge between them
  @eight_wyqz 30_000_775
  @e_jcus 30_000_531
  # LP1M-Q and O3-4MN, joined by a stargate for these tests
  @lp1m_q 30_000_533
  @o3_4mn 30_000_492

  @rifter 587
  @rhea 28_844

  setup do
    setup_system_static_info_cache(%{
      @sai_t9 => null_system(@sai_t9, "SAI-T9"),
      @y_fz5n => null_system(@y_fz5n, "Y-FZ5N"),
      @eight_wyqz => null_system(@eight_wyqz, "8-WYQZ"),
      @e_jcus => null_system(@e_jcus, "E-JCUS"),
      @lp1m_q => null_system(@lp1m_q, "LP1M-Q"),
      @o3_4mn => null_system(@o3_4mn, "O3-4MN")
    })

    setup_ddrt_mocks()

    # group 25 is Frigate, group 902 Jump Freighter
    Cachex.put(:ship_types_cache, @rifter, %{type_id: @rifter, group_id: 25})
    Cachex.put(:ship_types_cache, @rhea, %{type_id: @rhea, group_id: 902})

    # "jump_*" keys live in the global cache and are never invalidated, see
    # WandererApp.Map.MapScopeFilteringTest
    gate_key = "jump_#{min(@lp1m_q, @o3_4mn)}_#{max(@lp1m_q, @o3_4mn)}"

    WandererApp.Cache.insert(gate_key, %{
      from_solar_system_id: @lp1m_q,
      to_solar_system_id: @o3_4mn
    })

    on_exit(fn ->
      WandererApp.Cache.delete(gate_key)
      Cachex.del(:ship_types_cache, @rifter)
      Cachex.del(:ship_types_cache, @rhea)
    end)

    user = create_user(%{name: "Test User", hash: "test_hash_#{:rand.uniform(1_000_000)}"})

    character =
      create_character(%{
        eve_id: "#{2_100_000_000 + :rand.uniform(1_000_000)}",
        name: "Test Character",
        user_id: user.id,
        scopes: "esi-location.read_location.v1 esi-location.read_ship_type.v1",
        tracking_pool: "default"
      })

    {:ok, character: character}
  end

  describe "with [:pochven, :wormholes] scopes" do
    setup %{character: character}, do: start_map(character, [:pochven, :wormholes])

    @tag :integration
    test "a jump bridge jump adds no wormhole and no systems, either way round",
         %{map: map, character: character} do
      move(map, character, @sai_t9, @y_fz5n, @rifter)

      refute connected?(map.id, @sai_t9, @y_fz5n)
      refute system_on_map?(map.id, @sai_t9)
      refute system_on_map?(map.id, @y_fz5n)

      move(map, character, @y_fz5n, @sai_t9, @rifter)

      refute connected?(map.id, @sai_t9, @y_fz5n)
      refute system_on_map?(map.id, @sai_t9)
      refute system_on_map?(map.id, @y_fz5n)
    end

    @tag :integration
    test "a jump bridge jump is still recorded as a passage", %{map: map, character: character} do
      move(map, character, @sai_t9, @y_fz5n, @rifter)

      assert passage_recorded?(map.id, @sai_t9, @y_fz5n)
    end

    @tag :integration
    test "a jump-drive jump adds no wormhole and no systems", %{map: map, character: character} do
      move(map, character, @eight_wyqz, @e_jcus, @rhea)

      refute connected?(map.id, @eight_wyqz, @e_jcus)
      refute system_on_map?(map.id, @eight_wyqz)
      refute system_on_map?(map.id, @e_jcus)
    end

    @tag :integration
    test "an ordinary ship with no gate or bridge to explain the move went through a wormhole",
         %{map: map, character: character} do
      move(map, character, @eight_wyqz, @e_jcus, @rifter)

      assert wait_for_connection(map.id, @eight_wyqz, @e_jcus)
      assert connection_type(map.id, @eight_wyqz, @e_jcus) == @connection_type_wormhole
      assert system_on_map?(map.id, @eight_wyqz)
      assert system_on_map?(map.id, @e_jcus)
    end

    @tag :integration
    test "a connection added by hand between bridged systems is still drawn",
         %{map: map, character: character} do
      :ok =
        ConnectionsImpl.add_connection(map.id, %{
          solar_system_source_id: @sai_t9,
          solar_system_target_id: @y_fz5n,
          character_id: character.id
        })

      assert wait_for_connection(map.id, @sai_t9, @y_fz5n)
    end
  end

  describe "with [:null, :wormholes] scopes" do
    setup %{character: character}, do: start_map(character, [:null, :wormholes])

    @tag :integration
    test "a jump bridge jump adds the systems in scope but no wormhole",
         %{map: map, character: character} do
      move(map, character, @sai_t9, @y_fz5n, @rifter)

      assert wait_for_system_on_map(map.id, @sai_t9)
      assert wait_for_system_on_map(map.id, @y_fz5n)
      refute connected?(map.id, @sai_t9, @y_fz5n)
    end

    @tag :integration
    test "a stargate jump in a jump-drive hull is still a stargate connection",
         %{map: map, character: character} do
      move(map, character, @lp1m_q, @o3_4mn, @rhea)

      assert wait_for_connection(map.id, @lp1m_q, @o3_4mn)
      assert connection_type(map.id, @lp1m_q, @o3_4mn) == @connection_type_stargate
    end

    @tag :integration
    test "a stargate jump in an ordinary ship is still a stargate connection",
         %{map: map, character: character} do
      move(map, character, @o3_4mn, @lp1m_q, @rifter)

      assert wait_for_connection(map.id, @o3_4mn, @lp1m_q)
      assert connection_type(map.id, @o3_4mn, @lp1m_q) == @connection_type_stargate
    end
  end

  defp start_map(character, scopes) do
    map =
      create_map(%{
        name: "Test Kspace Jumps",
        slug: "test-kspace-jumps-#{:rand.uniform(1_000_000)}",
        owner_id: character.id,
        scope: :wormholes,
        scopes: scopes,
        only_tracked_characters: false
      })

    {:ok, _bridge} =
      WandererApp.Api.MapBridge.new(%{
        map_id: map.id,
        solar_system_source: min(@sai_t9, @y_fz5n),
        solar_system_target: max(@sai_t9, @y_fz5n)
      })

    on_exit(fn -> cleanup_test_data(map.id) end)

    ensure_map_started(map.id)
    track_character_on_map(map.id, character.id)

    {:ok, map: map}
  end

  # the character is seen in one system, then in the other, flying the same ship
  defp move(map, character, from_solar_system_id, to_solar_system_id, ship_type_id) do
    set_character_location(character.id, from_solar_system_id, ship: ship_type_id)

    WandererApp.Cache.insert(
      "map:#{map.id}:character:#{character.id}:start_solar_system_id",
      from_solar_system_id
    )

    CharactersImpl.update_characters(map.id)

    set_character_location(character.id, to_solar_system_id, ship: ship_type_id)
    CharactersImpl.update_characters(map.id)
  end

  defp connected?(map_id, from_solar_system_id, to_solar_system_id) do
    {:ok, connections} = WandererApp.Map.list_connections(map_id)

    Enum.any?(connections, fn connection ->
      MapSet.new([connection.solar_system_source, connection.solar_system_target]) ==
        MapSet.new([from_solar_system_id, to_solar_system_id])
    end)
  end

  defp connection_type(map_id, from_solar_system_id, to_solar_system_id) do
    WandererApp.Map.get_connection(map_id, from_solar_system_id, to_solar_system_id).type
  end

  defp wait_for_connection(map_id, from_solar_system_id, to_solar_system_id, timeout \\ 2000) do
    deadline = System.monotonic_time(:millisecond) + timeout

    Stream.repeatedly(fn ->
      cond do
        connected?(map_id, from_solar_system_id, to_solar_system_id) ->
          true

        System.monotonic_time(:millisecond) >= deadline ->
          false

        true ->
          Process.sleep(10)
          nil
      end
    end)
    |> Enum.find(&(not is_nil(&1)))
  end

  defp passage_recorded?(map_id, from_solar_system_id, to_solar_system_id) do
    {:ok, passages} = WandererApp.Api.MapChainPassages.read()

    Enum.any?(passages, fn passage ->
      passage.map_id == map_id and passage.solar_system_source_id == from_solar_system_id and
        passage.solar_system_target_id == to_solar_system_id
    end)
  end

  defp null_system(solar_system_id, name) do
    %{
      solar_system_id: solar_system_id,
      region_id: 10_000_060,
      constellation_id: 20_000_700,
      solar_system_name: name,
      solar_system_name_lc: String.downcase(name),
      constellation_name: "Test Constellation",
      region_name: "Test Region",
      system_class: 9,
      security: "-0.5",
      type_description: "Null Security",
      class_title: "Null Sec",
      is_shattered: false,
      effect_name: nil,
      effect_power: nil,
      statics: [],
      wandering: [],
      triglavian_invasion_status: nil,
      sun_type_id: 45_041
    }
  end
end
