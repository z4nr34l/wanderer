defmodule WandererApp.Character.ScopesTest do
  @moduledoc """
  Telling a character that predates a scope from one that is current.
  """

  use WandererApp.DataCase, async: true

  alias WandererApp.Character.Scopes

  test "required/0 reads what a plain authorisation asks for" do
    required = Scopes.required()

    assert "esi-location.read_location.v1" in required
    assert "esi-characters.read_contacts.v1" in required
  end

  test "a character granted everything asked for is not stale" do
    character = %{scopes: Enum.join(Scopes.required(), " ")}

    assert Scopes.missing(character) == []
    refute Scopes.stale?(character)
  end

  test "a character authorised before the contacts scopes is stale, and says which are missing" do
    character = %{
      scopes:
        "esi-location.read_location.v1 esi-location.read_ship_type.v1 esi-location.read_online.v1 esi-ui.write_waypoint.v1 esi-search.search_structures.v1"
    }

    assert Scopes.stale?(character)
    assert "esi-characters.read_contacts.v1" in Scopes.missing(character)
    refute "esi-location.read_location.v1" in Scopes.missing(character)
  end

  test "extra scopes beyond what is asked for do not make a character stale" do
    character = %{
      scopes: Enum.join(["esi-wallet.read_character_wallet.v1" | Scopes.required()], " ")
    }

    refute Scopes.stale?(character)
  end

  test "a character with no scopes recorded is stale rather than crashing" do
    assert Scopes.stale?(%{scopes: nil})
  end
end
