defmodule WandererApp.Zkb.SystemStatsTest do
  @moduledoc """
  Reading who flies in a system out of what zKillboard reports.

  Two things are worth pinning here. The rats are not the neighbours: an NPC corporation showing
  up in a quiet pocket of null sec must not pass for the people who live there, and must not stop
  the deeper list being read either - which is exactly what happened in Stain, where one kill by
  True Power hid five player alliances behind it. And which of the two lists answered is part of
  the answer, because a name from years ago is not the same claim as a name from this week.
  """

  use ExUnit.Case, async: false

  alias WandererApp.Zkb.SystemStats

  describe "what counts as somebody flying here" do
    test "an NPC corporation is the rats, not the neighbours" do
      # True Power is Sansha's, CONCORD is CONCORD; EVE keeps its NPC corporations below two
      # million, while a player corporation carrying an id from the old days sits far above
      refute SystemStats.npc?(1_027_262_090, :corporation)
      refute SystemStats.npc?(98_093_166, :corporation)
      assert SystemStats.npc?(1_000_162, :corporation)
      assert SystemStats.npc?(1_000_125, :corporation)
    end

    test "a faction is not an alliance, and an old alliance id still is one" do
      # Goonswarm has carried 1354830081 since long before the 99-prefixed ids
      refute SystemStats.npc?(1_354_830_081, :alliance)
      refute SystemStats.npc?(99_007_262, :alliance)
      assert SystemStats.npc?(500_019, :alliance)
      assert SystemStats.npc?(500_010, :alliance)
    end

    test "anything that is not a number is nobody" do
      refute SystemStats.npc?(nil, :alliance)
      refute SystemStats.npc?("98093166", :corporation)
    end
  end

  describe "reading a body" do
    test "prefers what is happening now" do
      body = %{
        "topLists" => [
          %{
            "type" => "alliance",
            "values" => [%{"id" => 99_007_262, "name" => "Wrecktical Supremacy.", "kills" => 4}]
          }
        ],
        "topAllTime" => [
          %{"type" => "alliance", "data" => [%{"allianceID" => 99_002_411, "kills" => 220}]}
        ]
      }

      assert {:ok, %{window: :recent, alliances: [%{name: "Wrecktical Supremacy.", kills: 4}]}} =
               SystemStats.read(body)
    end

    test "falls back to the deeper list when nothing recent is left after the rats are dropped" do
      body = %{
        "topLists" => [
          %{
            "type" => "corporation",
            "values" => [%{"id" => 1_000_162, "name" => "True Power", "kills" => 1}]
          }
        ],
        "topAllTime" => [
          %{"type" => "corporation", "data" => [%{"corporationID" => 1_000_162, "kills" => 248}]}
        ]
      }

      # every candidate is NPC, so there is nothing anybody would call neighbours
      assert {:error, :nothing_known} = SystemStats.read(body)
    end

    test "a system nobody has died in is not an error worth dressing up" do
      assert {:error, :nothing_known} = SystemStats.read(%{"topLists" => [], "topAllTime" => []})
    end
  end
end
