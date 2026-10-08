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

  describe "foreign?/3" do
    test "a gate inside our own sovereignty is ours to fly" do
      refute Ansiblex.foreign?(@home, @far_side, @ours)
    end

    test "a gate running into another alliance's space is theirs, whichever way it is read" do
      assert Ansiblex.foreign?(@home, @their_space, @ours)
      assert Ansiblex.foreign?(@their_space, @home, @ours)
      assert Ansiblex.foreign?(@their_space, @their_space, @ours)
    end

    test "their own gates are theirs to fly, and ours are not" do
      refute Ansiblex.foreign?(@their_space, @their_space, @theirs)
      assert Ansiblex.foreign?(@home, @far_side, @theirs)
    end

    # the rule is only allowed to take a road away on what it knows: sovereignty comes from a
    # background fetch, and an empty one must not empty the map
    test "space nobody holds is left alone" do
      refute Ansiblex.foreign?(@home, @no_sov, @ours)
      refute Ansiblex.foreign?(@no_sov, @no_sov, @ours)
    end

    test "a pilot whose alliance is not known loses nothing" do
      refute Ansiblex.foreign?(@home, @far_side, nil)
      refute Ansiblex.foreign?(@their_space, @their_space, nil)
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
