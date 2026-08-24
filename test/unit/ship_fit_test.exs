defmodule WandererApp.Character.ShipFitTest do
  @moduledoc """
  Picking a fit out of a character's assets. Everything ESI returns is handed in rather than
  fetched.
  """

  use ExUnit.Case, async: true

  alias WandererApp.Character.ShipFit

  @ship_item_id 1_020_000_000_001

  defp asset(flag, type_id, location_id \\ @ship_item_id) do
    %{
      "location_flag" => flag,
      "location_id" => location_id,
      "type_id" => type_id,
      "quantity" => 1
    }
  end

  describe "fitted_type_ids/2" do
    test "takes what is in a slot on this ship" do
      assets = [
        asset("HiSlot0", 1),
        asset("MedSlot3", 2),
        asset("LoSlot7", 3),
        asset("RigSlot1", 4),
        asset("SubSystemSlot0", 5)
      ]

      assert ShipFit.fitted_type_ids(assets, @ship_item_id) == [1, 2, 3, 4, 5]
    end

    test "leaves the holds alone - cargo does not weigh on the ship" do
      assets = [
        asset("HiSlot0", 1),
        asset("Cargo", 99),
        asset("DroneBay", 98),
        asset("FighterBay", 97),
        asset("FleetHangar", 96)
      ]

      assert ShipFit.fitted_type_ids(assets, @ship_item_id) == [1]
    end

    test "ignores modules fitted to another ship" do
      assets = [asset("HiSlot0", 1), asset("LoSlot0", 2, 555), asset("RigSlot0", 3)]

      assert ShipFit.fitted_type_ids(assets, @ship_item_id) == [1, 3]
    end

    test "survives assets that are missing the fields we look at" do
      assets = [
        %{"type_id" => 7},
        asset("HiSlot0", 1),
        Map.delete(asset("LoSlot0", 2), "type_id")
      ]

      assert ShipFit.fitted_type_ids(assets, @ship_item_id) == [1]
    end
  end

  describe "for_character/1" do
    test "a character with no ship has nothing to weigh" do
      assert {:error, :no_ship} = ShipFit.for_character(%{ship: nil, ship_item_id: nil})
      assert {:error, :no_ship} = ShipFit.for_character(%{})
    end
  end
end
