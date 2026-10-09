defmodule WandererApp.Server.SystemKillsFetcherTest do
  @moduledoc """
  NPC kills, an hour at a time and a day at a time.

  ESI only says what happened in the last hour, and leaves out every system where nothing died.
  So a system it does not mention has had zero kills, not unknown ones, and the day is the sum of
  the hours that have been kept - which right after this is switched on is fewer than twenty four,
  and says so.
  """

  use ExUnit.Case, async: false

  alias WandererApp.Server.SystemKillsFetcher

  @busy 30_004_712
  @quiet 30_001_949

  describe "reading what ESI sends" do
    test "keeps only the systems where something died, keyed as the database hands them back" do
      body = [
        %{"system_id" => @busy, "npc_kills" => 29, "ship_kills" => 0, "pod_kills" => 0},
        %{"system_id" => @quiet, "npc_kills" => 0, "ship_kills" => 3, "pod_kills" => 1},
        %{"system_id" => 30_000_142, "ship_kills" => 4}
      ]

      assert SystemKillsFetcher.npc_by_system(body) == %{"30004712" => 29}
    end
  end

  describe "npc_kills/1" do
    setup do
      on_exit(fn -> WandererApp.Cache.delete(:system_kills_day) end)
      :ok
    end

    test "is the latest hour and the day summed, with how many hours the day covers" do
      WandererApp.Cache.insert(:system_kills_day, %{
        hours: [
          %{hour: ~U[2026-10-09 12:58:53Z], npc_kills: %{"30004712" => 29}},
          %{hour: ~U[2026-10-09 11:58:53Z], npc_kills: %{"30004712" => 40}},
          %{hour: ~U[2026-10-09 10:58:53Z], npc_kills: %{}}
        ]
      })

      assert %{last_hour: 29, last_day: 69, hours: 3} = SystemKillsFetcher.npc_kills(@busy)
    end

    test "a system ESI never mentioned had nothing die in it" do
      WandererApp.Cache.insert(:system_kills_day, %{
        hours: [%{hour: ~U[2026-10-09 12:58:53Z], npc_kills: %{"30004712" => 29}}]
      })

      assert %{last_hour: 0, last_day: 0, hours: 1} = SystemKillsFetcher.npc_kills(@quiet)
    end

    test "says nothing before the first hour has been read" do
      assert SystemKillsFetcher.npc_kills(@busy) == nil
      assert SystemKillsFetcher.npc_kills(nil) == nil
    end
  end
end
