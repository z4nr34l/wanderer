defmodule WandererApp.Kills.Subscription.SystemMapIndexTest do
  use WandererApp.DataCase, async: false

  import WandererAppWeb.Factory

  alias WandererApp.Kills.Subscription.SystemMapIndex

  test "a system taken off a map no longer routes that map's kills" do
    map = create_map()
    shown = create_map_system(map.id, %{solar_system_id: 31_001_148})
    _hidden = create_map_system(map.id, %{solar_system_id: 31_001_149, visible: false})

    index = SystemMapIndex.index_for_maps([map])

    assert index[shown.solar_system_id] == [map.id]
    refute Map.has_key?(index, 31_001_149)
  end

  test "a system shown on two maps routes kills to both" do
    map_a = create_map()
    map_b = create_map()
    create_map_system(map_a.id, %{solar_system_id: 31_001_150})
    create_map_system(map_b.id, %{solar_system_id: 31_001_150})

    index = SystemMapIndex.index_for_maps([map_a, map_b])

    assert Enum.sort(index[31_001_150]) == Enum.sort([map_a.id, map_b.id])
  end
end
