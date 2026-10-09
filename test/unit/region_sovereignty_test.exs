defmodule WandererApp.Server.RegionSovereigntyTest do
  @moduledoc """
  Whose part of space a system sits in, told to the map.

  A null sec system nobody holds outright still sits in somebody's region - Fountain is INIT.'s
  whether or not a given pocket of it is - and that is the answer somebody wants on arriving
  there. It is passed on for null sec alone: a region's high sec belongs to an empire, and an
  alliance owning the area around Jita would be nonsense.
  """

  use ExUnit.Case, async: false

  alias WandererAppWeb.MapEventHandler

  @region 10_000_058
  @init %{alliance_id: 1_900_696_668, alliance_name: "The Initiative.", alliance_ticker: "INIT."}

  setup do
    WandererApp.Cache.insert(:sovereignty_regions, %{
      @region => Map.merge(@init, %{held: 108, total: 115})
    })

    on_exit(fn -> WandererApp.Cache.delete(:sovereignty_regions) end)
    :ok
  end

  test "a null sec system is told whose region it sits in, and by how much" do
    assert %{region_sovereignty: %{alliance_ticker: "INIT.", held: 108, total: 115}} =
             MapEventHandler.map_ui_system_static_info(%{
               solar_system_id: 30_004_712,
               region_id: @region,
               security: "-0.2"
             })
  end

  test "high sec is not told an alliance owns the area around it" do
    assert %{region_sovereignty: nil} =
             MapEventHandler.map_ui_system_static_info(%{
               solar_system_id: 30_000_142,
               region_id: @region,
               security: "0.9"
             })
  end

  test "a wormhole has no region anybody holds" do
    assert %{region_sovereignty: nil} =
             MapEventHandler.map_ui_system_static_info(%{
               solar_system_id: 31_001_269,
               region_id: @region,
               security: "-1.0"
             })
  end

  test "a region nobody dominates says nothing rather than guess" do
    assert %{region_sovereignty: nil} =
             MapEventHandler.map_ui_system_static_info(%{
               solar_system_id: 30_001_949,
               region_id: 10_000_022,
               security: "-0.5"
             })
  end
end
