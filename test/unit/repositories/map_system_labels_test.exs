defmodule WandererApp.MapSystemLabelsTest do
  use WandererApp.DataCase, async: false

  import WandererAppWeb.Factory

  alias WandererApp.MapRepo

  test "new maps expose server-side default labels" do
    map = create_map()

    assert {:ok, labels} = MapRepo.get_system_labels(map.id)
    assert labels == MapRepo.default_system_labels()
  end

  test "valid labels are normalized and persisted on the map" do
    map = create_map()

    labels = [
      %{"id" => " route ", "name" => " Home ", "color" => "#AABBCC"},
      %{"id" => "danger", "name" => "Danger", "color" => "#ff0000"}
    ]

    assert {:ok, _map, normalized} = MapRepo.update_system_labels(map.id, labels)

    assert normalized == [
             %{"id" => "route", "name" => "Home", "color" => "#aabbcc"},
             %{"id" => "danger", "name" => "Danger", "color" => "#ff0000"}
           ]

    assert {:ok, ^normalized} = MapRepo.get_system_labels(map.id)
  end

  test "invalid and duplicate label ids are rejected without changing the map" do
    map = create_map()
    defaults = MapRepo.default_system_labels()

    duplicate_labels = [
      %{"id" => "a", "name" => "First", "color" => "#112233"},
      %{"id" => "a", "name" => "Second", "color" => "#445566"}
    ]

    assert {:error, :invalid_system_labels} =
             MapRepo.update_system_labels(map.id, duplicate_labels)

    assert {:ok, ^defaults} = MapRepo.get_system_labels(map.id)
  end
end
