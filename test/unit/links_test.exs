defmodule WandererApp.Map.LinksTest do
  @moduledoc """
  Where two maps hold the same system, and what may be read of the other one.

  The rule this pins down is the one that keeps a token honest: a map reached by token is offered
  whole only when its owner has said so, and until then it hands over the way into the home and
  nothing more.
  """

  use WandererApp.DataCase, async: false

  alias WandererApp.Api.Map, as: MapResource
  alias WandererApp.Map.{HomeShares, Links}

  @home 31_001_269

  setup do
    ours = WandererAppWeb.Factory.create_map()
    theirs = WandererAppWeb.Factory.create_map()

    %{ours: ours, theirs: theirs}
  end

  describe "known/2 for a map reached by token" do
    test "says nothing until its owner shares it whole", %{ours: ours, theirs: theirs} do
      {:ok, theirs} = share(theirs)
      {:ok, _} = HomeShares.add(ours.id, %{"slug" => theirs.slug, "token" => "a-token"})

      assert %{links: [], overlaps: %{}} = Links.known(nil, ours.id)
    end

    test "offers the map once its owner has", %{ours: ours, theirs: theirs} do
      {:ok, theirs} = share(theirs)
      {:ok, theirs} = MapResource.update_home_share_full(theirs, %{home_share_full: true})
      {:ok, share} = HomeShares.add(ours.id, %{"slug" => theirs.slug, "token" => "a-token"})

      assert %{links: [link]} = Links.known(nil, ours.id)
      assert link.share_id == share.id
      assert link.link_id == "share:" <> share.id
      refute link[:remote?]
    end

    test "hands the whole map over only through a link it offered", %{ours: ours, theirs: theirs} do
      {:ok, theirs} = share(theirs)
      {:ok, share} = HomeShares.add(ours.id, %{"slug" => theirs.slug, "token" => "a-token"})

      # shared, but not shared whole
      assert {:error, :not_shared} = Links.preview(nil, ours.id, "share:" <> share.id)

      {:ok, _theirs} = MapResource.update_home_share_full(theirs, %{home_share_full: true})
      WandererApp.Cache.delete("home_share:#{share.base_url}:#{share.slug}")

      assert {:ok, %{"systems" => systems, "connections" => _}} =
               Links.preview(nil, ours.id, "share:" <> share.id)

      assert is_list(systems)
    end

    test "refuses a link this map was never offered", %{ours: ours} do
      assert {:error, :no_such_map} =
               Links.preview(nil, ours.id, "share:11111111-1111-1111-1111-111111111111")

      assert {:error, :no_such_map} =
               Links.preview(nil, ours.id, "map:11111111-1111-1111-1111-111111111111")

      assert {:error, :no_such_map} = Links.preview(nil, ours.id, "nonsense")
    end
  end

  describe "known/2 without a user" do
    test "offers no map from the instance, because nobody asked", %{ours: ours} do
      assert %{links: [], overlaps: %{}} = Links.known(nil, ours.id)
    end

    test "answers an empty map id with nothing" do
      assert %{links: [], overlaps: %{}} = Links.known(nil, nil)
    end
  end

  describe "whole/1" do
    test "gives a map in the shape the map itself is drawn from", %{theirs: theirs} do
      assert %{"systems" => systems, "connections" => connections} = Links.whole(theirs.id)
      assert is_list(systems)
      assert is_list(connections)
    end
  end

  defp share(map) do
    {:ok, map} =
      MapResource.update_discord_settings(map, %{
        discord_webhook_url: nil,
        home_solar_system_id: @home
      })

    MapResource.update_home_share_token(map, %{home_share_token: "a-token"})
  end
end
