defmodule WandererApp.Map.BridgesImportTest do
  @moduledoc """
  Importing a pasted bridge list, and what the router is then allowed to use.
  """

  use WandererApp.DataCase, async: false

  alias WandererApp.Map.Bridges

  @ualx 30_004_759
  @onedq 30_004_760
  @t5zi 30_004_761

  setup do
    map = WandererAppWeb.Factory.create_map()

    WandererAppWeb.Factory.create_solar_system(%{
      solar_system_id: @ualx,
      solar_system_name: "UALX-3"
    })

    WandererAppWeb.Factory.create_solar_system(%{
      solar_system_id: @onedq,
      solar_system_name: "1DQ1-A"
    })

    WandererAppWeb.Factory.create_solar_system(%{
      solar_system_id: @t5zi,
      solar_system_name: "T5ZI-S"
    })

    %{map: map}
  end

  test "imports what it can name and says what it could not", %{map: map} do
    text = """
    UALX-3 » 1DQ1-A
    T5ZI-S -> 1DQ1-A
    NOT-A-SYSTEM » 1DQ1-A
    gibberish
    """

    assert {:ok, %{imported: 2, unknown: ["NOT-A-SYSTEM"], unreadable: ["gibberish"]}} =
             Bridges.import(map.id, text)

    assert length(Bridges.list(map.id)) == 2
  end

  test "the same bridge pasted twice, either way round, stays one bridge", %{map: map} do
    assert {:ok, %{imported: 1}} = Bridges.import(map.id, "UALX-3 » 1DQ1-A")
    assert {:ok, %{imported: 1}} = Bridges.import(map.id, "1DQ1-A » UALX-3")

    assert [bridge] = Bridges.list(map.id)
    assert bridge.solar_system_source == min(@ualx, @onedq)
    assert bridge.solar_system_target == max(@ualx, @onedq)
  end

  test "a route may use a bridge, unless it is told not to", %{map: map} do
    {:ok, _} = Bridges.import(map.id, "UALX-3 » 1DQ1-A")

    pair = %{first: min(@ualx, @onedq), second: max(@ualx, @onedq)}

    assert [^pair] = Bridges.route_pairs(map.id, %{})
    assert [] = Bridges.route_pairs(map.id, %{include_bridges: false})

    # safe by default, so avoiding dangerous ones changes nothing yet
    assert [^pair] = Bridges.route_pairs(map.id, %{avoid_dangerous_bridges: true})
  end

  test "a bridge marked dangerous is skipped for anyone avoiding those", %{map: map} do
    {:ok, _} = Bridges.import(map.id, "UALX-3 » 1DQ1-A", dangerous: true)

    assert [%{dangerous: true}] = Bridges.list(map.id)
    assert [] = Bridges.route_pairs(map.id, %{avoid_dangerous_bridges: true})
    assert [_pair] = Bridges.route_pairs(map.id, %{avoid_dangerous_bridges: false})
  end

  test "the flag can be flipped and the bridge forgotten", %{map: map} do
    {:ok, _} = Bridges.import(map.id, "UALX-3 » 1DQ1-A")
    [bridge] = Bridges.list(map.id)

    assert :ok = Bridges.set_dangerous(bridge.id, true)
    assert [%{dangerous: true}] = Bridges.list(map.id)

    assert :ok = Bridges.delete(bridge.id)
    assert [] = Bridges.list(map.id)
  end
end
