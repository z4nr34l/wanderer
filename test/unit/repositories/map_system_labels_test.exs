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
             %{"id" => "route", "name" => "Home", "color" => "#aabbcc", "description" => ""},
             %{"id" => "danger", "name" => "Danger", "color" => "#ff0000", "description" => ""}
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

  describe "a label's description" do
    test "travels with the definition, trimmed" do
      map = create_map()

      labels = [
        %{"id" => "s", "name" => "S", "color" => "#2d803b", "description" => "  static to HS  "}
      ]

      assert {:ok, _map, [%{"description" => "static to HS"}]} =
               MapRepo.update_system_labels(map.id, labels)

      assert {:ok, [%{"description" => "static to HS"}]} = MapRepo.get_system_labels(map.id)
    end

    test "is optional, so a list saved before it existed still reads" do
      map = create_map()

      assert {:ok, _map, [%{"description" => ""}]} =
               MapRepo.update_system_labels(map.id, [
                 %{"id" => "s", "name" => "S", "color" => "#2d803b"}
               ])
    end

    test "is refused when too long or not text, and leaves the map as it was" do
      map = create_map()
      defaults = MapRepo.default_system_labels()

      too_long = String.duplicate("x", 257)

      assert {:error, :invalid_system_labels} =
               MapRepo.update_system_labels(map.id, [
                 %{"id" => "s", "name" => "S", "color" => "#2d803b", "description" => too_long}
               ])

      assert {:error, :invalid_system_labels} =
               MapRepo.update_system_labels(map.id, [
                 %{"id" => "s", "name" => "S", "color" => "#2d803b", "description" => 42}
               ])

      assert {:ok, ^defaults} = MapRepo.get_system_labels(map.id)
    end
  end
end
