defmodule WandererApp.StandingsTest do
  @moduledoc """
  Which contact list wins when they disagree.
  """

  use WandererApp.DataCase, async: true

  alias WandererApp.Standings

  defp contact(id, standing),
    do: %{"contact_id" => id, "standing" => standing, "contact_type" => "alliance"}

  # the merge is about which list wins, not about what ESI calls an alliance, so the lookup is
  # stubbed rather than left to reach the network
  defp resolve, do: fn id -> {"T#{id}", "Alliance #{id}"} end

  describe "merge/1" do
    test "the alliance list overrides the corporation, and the corporation the character" do
      read = [
        {"character", [contact(99_000_001, 10.0)]},
        {"corporation", [contact(99_000_001, 0.0)]},
        {"alliance", [contact(99_000_001, -10.0)]}
      ]

      assert [%{alliance: "T99000001", standing: -10.0}] = Standings.merge(read, resolve())
    end

    test "order of the lists as they arrive does not matter" do
      read = [
        {"alliance", [contact(99_000_001, -10.0)]},
        {"character", [contact(99_000_001, 10.0)]}
      ]

      assert [%{standing: -10.0}] = Standings.merge(read, resolve())
    end

    test "a standing only one list carries still comes through" do
      read = [
        {"character", [contact(99_000_001, 5.0)]},
        {"alliance", [contact(99_000_002, -5.0)]}
      ]

      assert [%{alliance: "T99000002", standing: -5.0}, %{alliance: "T99000001", standing: 5.0}] =
               Standings.merge(read, resolve())
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

      assert [%{alliance: "T99000001"}] = Standings.merge(read, resolve())
    end
  end

  describe "sources/1" do
    test "reports what answered, in the order it is applied" do
      read = [{"alliance", []}, {"character", []}, {"alliance", []}]

      assert ["character", "alliance"] = Standings.sources(read)
    end
  end
end
