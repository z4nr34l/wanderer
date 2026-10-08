defmodule WandererApp.Map.RoutePairsTest do
  @moduledoc """
  Folding the sources of a route graph together.

  A pair can reach the graph from more than one place - a connection drawn on the map and the
  same gate in the imported bridge list - and the two need not name their ends in the same order.
  Such a pair used to cancel itself out, which took the road away from both systems.
  """

  use ExUnit.Case, async: true

  alias WandererApp.Map.Routes

  describe "the route graph's pairs" do
    test "a pair named end-first in either order is kept once, not dropped twice" do
      chains =
        Routes.chain_pairs([
          %{first: 30_000_783, second: 30_000_772},
          %{first: 30_000_772, second: 30_000_783}
        ])

      assert length(chains) == 1
      assert [%{first: first, second: second}] = chains
      assert Enum.sort([first, second]) == [30_000_772, 30_000_783]
    end

    test "a pair named twice the same way is still kept once" do
      assert [_one] =
               Routes.chain_pairs([
                 %{first: 1, second: 2},
                 %{first: 1, second: 2}
               ])
    end

    test "different pairs all survive" do
      assert length(
               Routes.chain_pairs([
                 %{first: 1, second: 2},
                 %{first: 2, second: 3},
                 %{first: 3, second: 1}
               ])
             ) == 3
    end

    test "nothing in, nothing out" do
      assert Routes.chain_pairs([]) == []
    end
  end
end
