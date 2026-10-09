defmodule WandererApp.Zkb.SystemStatsTest do
  @moduledoc """
  Counting who has been seen in a system out of the kills in it.

  Two things are worth pinning. A fleet is one group being somewhere, not thirty, so a kill
  counts once for anybody who was in it however many ships they brought. And the rats are not the
  neighbours: an NPC corporation taking the final blow in a hole says nothing about who is in the
  chain.
  """

  use ExUnit.Case, async: true

  alias WandererApp.Zkb.SystemStats

  describe "what counts as somebody seen here" do
    test "an NPC corporation is the rats, not the neighbours" do
      # True Power is Sansha's and CONCORD is CONCORD; EVE keeps its NPC corporations below two
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
    end

    test "anything that is not a number is nobody" do
      refute SystemStats.npc?(nil, :alliance)
      refute SystemStats.npc?("98093166", :corporation)
    end
  end

  describe "counting killmails" do
    test "a fleet in one kill is one group being there, not one per ship" do
      killmails = [
        %{
          "victim" => %{"alliance_id" => 99_000_002},
          "attackers" => [
            %{"alliance_id" => 99_000_001},
            %{"alliance_id" => 99_000_001},
            %{"alliance_id" => 99_000_001}
          ]
        }
      ]

      assert SystemStats.counts(killmails, "alliance_id", :alliance) == [
               {99_000_001, 1},
               {99_000_002, 1}
             ]
    end

    test "somebody in two kills has been there twice, and comes first" do
      seen_twice = %{
        "victim" => %{"alliance_id" => 99_000_002},
        "attackers" => [%{"alliance_id" => 99_000_001}]
      }

      once = %{
        "victim" => %{"alliance_id" => 99_000_003},
        "attackers" => [%{"alliance_id" => 99_000_001}]
      }

      assert [{99_000_001, 3}, {99_000_002, 2}, {99_000_003, 1}] =
               SystemStats.counts([seen_twice, seen_twice, once], "alliance_id", :alliance)
    end

    test "the rats are left out of it" do
      killmails = [
        %{
          "victim" => %{"corporation_id" => 98_093_166},
          "attackers" => [%{"corporation_id" => 1_000_162}]
        }
      ]

      assert SystemStats.counts(killmails, "corporation_id", :corporation) == [{98_093_166, 1}]
    end

    test "a pilot in no alliance is nobody's, not a group of nil" do
      killmails = [%{"victim" => %{"alliance_id" => nil}, "attackers" => [%{}]}]

      assert SystemStats.counts(killmails, "alliance_id", :alliance) == []
    end

    test "a hole nobody has died in says nothing" do
      assert SystemStats.counts([], "alliance_id", :alliance) == []
    end
  end
end
