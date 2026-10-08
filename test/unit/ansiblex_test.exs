defmodule WandererApp.Map.AnsiblexTest do
  @moduledoc """
  Who may fly an Ansiblex now that a gate belongs to its alliance and nobody else.

  The rule is CCP's, from the Cradle of War update of 2026-09-22: an access list can no longer let
  an outsider through, and a jump needs the pilot to be in the alliance holding sovereignty where
  the jump starts. What is pinned here is that a bridge counts as a road only for the alliance
  that holds the space it runs through.
  """

  use ExUnit.Case, async: false

  alias WandererApp.Map.Ansiblex

  @ours 99_000_001
  @theirs 99_000_002

  @home 30_000_001
  @far_side 30_000_002
  @their_space 30_000_003
  @no_sov 30_000_004

  setup do
    WandererApp.Cache.insert(:sovereignty_data_fetcher, %{
      @home => %{alliance_id: @ours},
      @far_side => %{alliance_id: @ours},
      @their_space => %{alliance_id: @theirs}
    })

    on_exit(fn -> WandererApp.Cache.delete(:sovereignty_data_fetcher) end)
    :ok
  end

  describe "usable?/3" do
    test "a gate inside our own sovereignty is a road" do
      assert Ansiblex.usable?(@home, @far_side, @ours)
    end

    test "a gate belonging to another alliance is not, whichever way it is read" do
      refute Ansiblex.usable?(@home, @their_space, @ours)
      refute Ansiblex.usable?(@their_space, @home, @ours)
      refute Ansiblex.usable?(@their_space, @their_space, @ours)
    end

    test "nobody flies a gate in space no alliance holds" do
      refute Ansiblex.usable?(@home, @no_sov, @ours)
      refute Ansiblex.usable?(@no_sov, @no_sov, @ours)
    end

    test "a pilot without an alliance flies no gate at all" do
      refute Ansiblex.usable?(@home, @far_side, nil)
    end

    test "their own gates are roads for them, and not for us" do
      assert Ansiblex.usable?(@their_space, @their_space, @theirs)
      refute Ansiblex.usable?(@home, @far_side, @theirs)
    end
  end

  describe "holder/1" do
    test "names the alliance holding a system, and nobody where nobody does" do
      assert Ansiblex.holder(@home) == @ours
      assert Ansiblex.holder(@their_space) == @theirs
      assert Ansiblex.holder(@no_sov) == nil
      assert Ansiblex.holder(nil) == nil
    end
  end
end
