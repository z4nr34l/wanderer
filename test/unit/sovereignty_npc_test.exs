defmodule WandererApp.Server.SovereigntyNpcTest do
  @moduledoc """
  The faction whose space a system sits in, where no alliance holds it.

  Most of the null sec nobody claims is not nobody's: CCP names the faction on the same
  sovereignty map, which is what tells a reader whether it is Sansha's or the Guristas out there.
  What this pins down is that such a record never passes for sovereignty an alliance holds - the
  Ansiblex rule reads that question and must not get an answer from a faction.
  """

  use ExUnit.Case, async: false

  alias WandererApp.Map.Ansiblex

  @ours 99_000_001
  @held 30_000_001
  @npc 30_000_002
  @nobody 30_000_003

  setup do
    WandererApp.Cache.insert(:sovereignty_data_fetcher, %{
      @held => %{alliance_id: @ours, alliance_name: "Ours", alliance_ticker: "OURS"},
      @npc => %{faction_id: 500_019, faction_name: "Sansha's Nation"}
    })

    on_exit(fn -> WandererApp.Cache.delete(:sovereignty_data_fetcher) end)
    :ok
  end

  describe "what the map is told about a system" do
    test "a faction is passed on for null sec, and kept out of empire space" do
      # CCP names CONCORD for Jita; a chip saying so on every high sec system is noise
      assert %{sovereignty: %{faction_name: "Sansha's Nation"}} =
               WandererAppWeb.MapEventHandler.map_ui_system_static_info(%{
                 solar_system_id: @npc,
                 security: "-0.5"
               })

      assert %{sovereignty: nil} =
               WandererAppWeb.MapEventHandler.map_ui_system_static_info(%{
                 solar_system_id: @npc,
                 security: "0.9"
               })
    end

    test "an alliance holding a system is passed on whatever the security" do
      assert %{sovereignty: %{alliance_ticker: "OURS"}} =
               WandererAppWeb.MapEventHandler.map_ui_system_static_info(%{
                 solar_system_id: @held,
                 security: "-0.3"
               })
    end
  end

  describe "a faction's space, asked about as sovereignty" do
    test "names no alliance holding it" do
      assert Ansiblex.holder(@held) == @ours
      assert Ansiblex.holder(@npc) == nil
      assert Ansiblex.holder(@nobody) == nil
    end

    test "takes no bridge away, because a faction is not somebody else's alliance" do
      refute Ansiblex.foreign?(@held, @npc, @ours)
      refute Ansiblex.foreign?(@npc, @npc, @ours)
      refute Ansiblex.foreign?(@npc, @nobody, @ours)
    end
  end
end
