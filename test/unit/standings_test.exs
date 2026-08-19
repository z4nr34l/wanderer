defmodule WandererApp.StandingsTest do
  @moduledoc """
  Which contact list wins when they disagree.
  """

  use WandererApp.DataCase, async: true

  alias WandererApp.Standings

  # ESI is not reachable from here, so alliance lookups fall back to the id as the ticker - which
  # is what these assertions match on.
  defp contact(id, standing),
    do: %{"contact_id" => id, "standing" => standing, "contact_type" => "alliance"}

  describe "merge/1" do
    test "the alliance list overrides the corporation, and the corporation the character" do
      read = [
        {"character", [contact(99_000_001, 10.0)]},
        {"corporation", [contact(99_000_001, 0.0)]},
        {"alliance", [contact(99_000_001, -10.0)]}
      ]

      assert [%{alliance: "99000001", standing: -10.0}] = Standings.merge(read)
    end

    test "order of the lists as they arrive does not matter" do
      read = [
        {"alliance", [contact(99_000_001, -10.0)]},
        {"character", [contact(99_000_001, 10.0)]}
      ]

      assert [%{standing: -10.0}] = Standings.merge(read)
    end

    test "a standing only one list carries still comes through" do
      read = [
        {"character", [contact(99_000_001, 5.0)]},
        {"alliance", [contact(99_000_002, -5.0)]}
      ]

      assert [%{alliance: "99000002", standing: -5.0}, %{alliance: "99000001", standing: 5.0}] =
               Standings.merge(read)
    end

    test "contacts that are not alliances are dropped" do
      read = [
        {"character",
         [
           %{"contact_id" => 90_000_001, "standing" => -10.0, "contact_type" => "character"},
           %{"contact_id" => 98_000_001, "standing" => -10.0, "contact_type" => "corporation"},
           contact(99_000_001, -10.0)
         ]}
      ]

      assert [%{alliance: "99000001"}] = Standings.merge(read)
    end
  end

  describe "sources/1" do
    test "reports what answered, in the order it is applied" do
      read = [{"alliance", []}, {"character", []}, {"alliance", []}]

      assert ["character", "alliance"] = Standings.sources(read)
    end
  end
end
