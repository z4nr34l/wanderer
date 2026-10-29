defmodule WandererApp.Map.Server.BridgeOrJumpDriveMoveTest do
  @moduledoc """
  Tests for ConnectionsImpl.bridge_or_jump_drive_move?/4: a move between two k-space
  systems with no stargate between them is only a wormhole when neither a jump bridge on the
  map nor the ship's own jump drive explains it.
  """

  use WandererApp.DataCase, async: false

  alias WandererApp.Map.Server.ConnectionsImpl

  @c2 2
  @ns 9

  # SAI-T9 and Y-FZ5N, a jump bridge pair on a real map
  @sai_t9 30_000_508
  @y_fz5n 30_002_162
  # 8-WYQZ and E-JCUS, no stargate and no bridge between them
  @eight_wyqz 30_000_775
  @e_jcus 30_000_531
  # two null-sec systems joined by a stargate
  @gate_from 30_000_533
  @gate_to 30_000_492
  @wh_system 31_000_002

  @rifter 587
  @rhea 28_844

  setup do
    for solar_system_id <- [@sai_t9, @y_fz5n, @eight_wyqz, @e_jcus, @gate_from, @gate_to] do
      Cachex.put(:system_static_info_cache, solar_system_id, %{
        solar_system_id: solar_system_id,
        system_class: @ns
      })
    end

    Cachex.put(:system_static_info_cache, @wh_system, %{
      solar_system_id: @wh_system,
      system_class: @c2
    })

    # group 25 is Frigate, group 902 Jump Freighter
    Cachex.put(:ship_types_cache, @rifter, %{type_id: @rifter, group_id: 25})
    Cachex.put(:ship_types_cache, @rhea, %{type_id: @rhea, group_id: 902})

    gate_key = "jump_#{min(@gate_from, @gate_to)}_#{max(@gate_from, @gate_to)}"

    WandererApp.Cache.insert(gate_key, %{
      from_solar_system_id: @gate_from,
      to_solar_system_id: @gate_to
    })

    on_exit(fn ->
      WandererApp.Cache.delete(gate_key)
      Cachex.del(:ship_types_cache, @rifter)
      Cachex.del(:ship_types_cache, @rhea)
    end)

    map = WandererAppWeb.Factory.create_map()

    {:ok, _bridge} =
      WandererApp.Api.MapBridge.new(%{
        map_id: map.id,
        solar_system_source: min(@sai_t9, @y_fz5n),
        solar_system_target: max(@sai_t9, @y_fz5n)
      })

    %{map: map}
  end

  test "a jump bridge on the map explains the move, either way round", %{map: map} do
    assert ConnectionsImpl.bridge_or_jump_drive_move?(map.id, @rifter, @sai_t9, @y_fz5n)
    assert ConnectionsImpl.bridge_or_jump_drive_move?(map.id, @rifter, @y_fz5n, @sai_t9)
  end

  test "a bridge on another map explains nothing", %{map: map} do
    other_map = WandererAppWeb.Factory.create_map()

    refute ConnectionsImpl.bridge_or_jump_drive_move?(other_map.id, @rifter, @sai_t9, @y_fz5n)
    assert ConnectionsImpl.bridge_or_jump_drive_move?(map.id, @rifter, @sai_t9, @y_fz5n)
  end

  test "a jump-drive hull explains the move", %{map: map} do
    assert ConnectionsImpl.bridge_or_jump_drive_move?(map.id, @rhea, @eight_wyqz, @e_jcus)
  end

  test "an ordinary ship between systems with no gate or bridge went through a wormhole",
       %{map: map} do
    refute ConnectionsImpl.bridge_or_jump_drive_move?(map.id, @rifter, @eight_wyqz, @e_jcus)
    refute ConnectionsImpl.bridge_or_jump_drive_move?(map.id, nil, @eight_wyqz, @e_jcus)
  end

  test "a stargate jump is neither, whatever the ship", %{map: map} do
    refute ConnectionsImpl.bridge_or_jump_drive_move?(map.id, @rhea, @gate_from, @gate_to)
    refute ConnectionsImpl.bridge_or_jump_drive_move?(map.id, @rifter, @gate_from, @gate_to)
  end

  test "a move into wormhole space is never a bridge or jump drive move", %{map: map} do
    refute ConnectionsImpl.bridge_or_jump_drive_move?(map.id, @rhea, @eight_wyqz, @wh_system)
  end
end
