defmodule WandererApp.Map.CacheRTreeTest do
  use ExUnit.Case, async: false

  alias WandererApp.Map.CacheRTree

  setup do
    # Unique tree name per test to ensure isolation
    tree_name = "test_rtree_#{:rand.uniform(1_000_000)}"
    CacheRTree.init_tree(tree_name)

    on_exit(fn ->
      CacheRTree.clear_tree(tree_name)
    end)

    {:ok, tree_name: tree_name}
  end

  describe "init_tree/2" do
    test "initializes empty tree with default config" do
      tree_name = "test_init_#{:rand.uniform(1_000_000)}"
      assert :ok = CacheRTree.init_tree(tree_name)

      # Verify empty tree
      assert {:ok, []} = CacheRTree.query([{0, 100}, {0, 100}], tree_name)

      # Cleanup
      CacheRTree.clear_tree(tree_name)
    end

    test "initializes tree with custom config" do
      tree_name = "test_init_config_#{:rand.uniform(1_000_000)}"
      assert :ok = CacheRTree.init_tree(tree_name, %{width: 200, verbose: true})

      # Cleanup
      CacheRTree.clear_tree(tree_name)
    end
  end

  describe "insert/2" do
    test "inserts single leaf", %{tree_name: name} do
      leaf = {30_000_142, [{100, 230}, {50, 84}]}
      assert {:ok, %{}} = CacheRTree.insert(leaf, name)

      # Verify insertion
      {:ok, ids} = CacheRTree.query([{100, 230}, {50, 84}], name)
      assert 30_000_142 in ids
    end

    test "inserts multiple leaves", %{tree_name: name} do
      leaves = [
        {30_000_142, [{100, 230}, {50, 84}]},
        {30_000_143, [{250, 380}, {100, 134}]},
        {30_000_144, [{400, 530}, {50, 84}]}
      ]

      assert {:ok, %{}} = CacheRTree.insert(leaves, name)

      # Verify all insertions
      {:ok, ids1} = CacheRTree.query([{100, 230}, {50, 84}], name)
      assert 30_000_142 in ids1

      {:ok, ids2} = CacheRTree.query([{250, 380}, {100, 134}], name)
      assert 30_000_143 in ids2

      {:ok, ids3} = CacheRTree.query([{400, 530}, {50, 84}], name)
      assert 30_000_144 in ids3
    end

    test "handles duplicate ID by overwriting", %{tree_name: name} do
      # Insert first time
      CacheRTree.insert({30_000_142, [{100, 230}, {50, 84}]}, name)

      # Insert same ID with different bounding box
      CacheRTree.insert({30_000_142, [{200, 330}, {100, 134}]}, name)

      # Should find in new location
      {:ok, ids_new} = CacheRTree.query([{200, 330}, {100, 134}], name)
      assert 30_000_142 in ids_new

      # Should NOT find in old location
      {:ok, ids_old} = CacheRTree.query([{100, 230}, {50, 84}], name)
      assert 30_000_142 not in ids_old
    end

    test "handles integer IDs", %{tree_name: name} do
      leaf = {123_456, [{0, 130}, {0, 34}]}
      assert {:ok, %{}} = CacheRTree.insert(leaf, name)
    end

    test "handles string IDs", %{tree_name: name} do
      leaf = {"system_abc", [{0, 130}, {0, 34}]}
      assert {:ok, %{}} = CacheRTree.insert(leaf, name)

      {:ok, ids} = CacheRTree.query([{0, 130}, {0, 34}], name)
      assert "system_abc" in ids
    end
  end

  describe "delete/2" do
    test "deletes single leaf", %{tree_name: name} do
      CacheRTree.insert({30_000_142, [{100, 230}, {50, 84}]}, name)
      assert {:ok, %{}} = CacheRTree.delete([30_000_142], name)

      # Verify deletion
      {:ok, ids} = CacheRTree.query([{100, 230}, {50, 84}], name)
      assert ids == []
    end

    test "deletes multiple leaves", %{tree_name: name} do
      leaves = [
        {30_000_142, [{100, 230}, {50, 84}]},
        {30_000_143, [{250, 380}, {100, 134}]},
        {30_000_144, [{400, 530}, {50, 84}]}
      ]

      CacheRTree.insert(leaves, name)

      # Delete two of them
      assert {:ok, %{}} = CacheRTree.delete([30_000_142, 30_000_143], name)

      # Verify deletions
      {:ok, ids1} = CacheRTree.query([{100, 230}, {50, 84}], name)
      assert ids1 == []

      {:ok, ids2} = CacheRTree.query([{250, 380}, {100, 134}], name)
      assert ids2 == []

      # Third should still exist
      {:ok, ids3} = CacheRTree.query([{400, 530}, {50, 84}], name)
      assert 30_000_144 in ids3
    end

    test "handles non-existent ID gracefully", %{tree_name: name} do
      assert {:ok, %{}} = CacheRTree.delete([99999], name)
      assert {:ok, %{}} = CacheRTree.delete([99998, 99999], name)
    end

    test "handles deleting from empty tree", %{tree_name: name} do
      assert {:ok, %{}} = CacheRTree.delete([30_000_142], name)
    end
  end

  describe "update/3" do
    test "updates leaf with new bounding box", %{tree_name: name} do
      CacheRTree.insert({30_000_142, [{100, 230}, {50, 84}]}, name)

      # Update to new position
      new_box = [{200, 330}, {100, 134}]
      assert {:ok, %{}} = CacheRTree.update(30_000_142, new_box, name)

      # Should find in new location
      {:ok, ids_new} = CacheRTree.query(new_box, name)
      assert 30_000_142 in ids_new

      # Should NOT find in old location
      {:ok, ids_old} = CacheRTree.query([{100, 230}, {50, 84}], name)
      assert 30_000_142 not in ids_old
    end

    test "updates leaf with old/new tuple", %{tree_name: name} do
      old_box = [{100, 230}, {50, 84}]
      new_box = [{200, 330}, {100, 134}]

      CacheRTree.insert({30_000_142, old_box}, name)

      # Update with tuple
      assert {:ok, %{}} = CacheRTree.update(30_000_142, {old_box, new_box}, name)

      # Should find in new location
      {:ok, ids_new} = CacheRTree.query(new_box, name)
      assert 30_000_142 in ids_new
    end

    test "handles updating non-existent leaf", %{tree_name: name} do
      # Should work like insert
      new_box = [{200, 330}, {100, 134}]
      assert {:ok, %{}} = CacheRTree.update(99999, new_box, name)

      {:ok, ids} = CacheRTree.query(new_box, name)
      assert 99999 in ids
    end

    test "updates preserve ID type", %{tree_name: name} do
      CacheRTree.insert({"system_abc", [{100, 230}, {50, 84}]}, name)

      new_box = [{200, 330}, {100, 134}]
      CacheRTree.update("system_abc", new_box, name)

      {:ok, ids} = CacheRTree.query(new_box, name)
      assert "system_abc" in ids
    end
  end

  describe "query/2" do
    test "returns empty list for empty tree", %{tree_name: name} do
      assert {:ok, []} = CacheRTree.query([{0, 100}, {0, 100}], name)
    end

    test "finds intersecting leaves", %{tree_name: name} do
      leaves = [
        {30_000_142, [{100, 230}, {50, 84}]},
        {30_000_143, [{250, 380}, {100, 134}]},
        {30_000_144, [{400, 530}, {50, 84}]}
      ]

      CacheRTree.insert(leaves, name)

      # Query overlapping with first system
      {:ok, ids} = CacheRTree.query([{150, 280}, {60, 94}], name)
      assert 30_000_142 in ids
      assert length(ids) == 1
    end

    test "excludes non-intersecting leaves", %{tree_name: name} do
      leaves = [
        {30_000_142, [{100, 230}, {50, 84}]},
        {30_000_143, [{250, 380}, {100, 134}]}
      ]

      CacheRTree.insert(leaves, name)

      # Query that doesn't intersect any leaf
      {:ok, ids} = CacheRTree.query([{500, 600}, {200, 250}], name)
      assert ids == []
    end

    test "handles overlapping bounding boxes", %{tree_name: name} do
      # Insert overlapping systems
      leaves = [
        {30_000_142, [{100, 230}, {50, 84}]},
        # Overlaps with first
        {30_000_143, [{150, 280}, {60, 94}]}
      ]

      CacheRTree.insert(leaves, name)

      # Query that overlaps both
      {:ok, ids} = CacheRTree.query([{175, 200}, {65, 80}], name)
      assert 30_000_142 in ids
      assert 30_000_143 in ids
      assert length(ids) == 2
    end

    test "edge case: exact match", %{tree_name: name} do
      box = [{100, 230}, {50, 84}]
      CacheRTree.insert({30_000_142, box}, name)

      {:ok, ids} = CacheRTree.query(box, name)
      assert 30_000_142 in ids
    end

    test "edge case: contained box", %{tree_name: name} do
      # Insert larger box
      CacheRTree.insert({30_000_142, [{100, 300}, {50, 150}]}, name)

      # Query with smaller box inside
      {:ok, ids} = CacheRTree.query([{150, 250}, {75, 100}], name)
      assert 30_000_142 in ids
    end

    test "edge case: containing box", %{tree_name: name} do
      # Insert smaller box
      CacheRTree.insert({30_000_142, [{150, 250}, {75, 100}]}, name)

      # Query with larger box that contains it
      {:ok, ids} = CacheRTree.query([{100, 300}, {50, 150}], name)
      assert 30_000_142 in ids
    end

    test "edge case: adjacent boxes don't intersect", %{tree_name: name} do
      CacheRTree.insert({30_000_142, [{100, 230}, {50, 84}]}, name)

      # Adjacent box (touching but not overlapping)
      {:ok, ids} = CacheRTree.query([{230, 360}, {50, 84}], name)
      assert ids == []
    end

    test "handles negative coordinates", %{tree_name: name} do
      leaves = [
        {30_000_142, [{-200, -70}, {-100, -66}]},
        {30_000_143, [{-50, 80}, {-25, 9}]}
      ]

      CacheRTree.insert(leaves, name)

      {:ok, ids} = CacheRTree.query([{-150, -100}, {-90, -70}], name)
      assert 30_000_142 in ids
    end
  end

  describe "spatial grid" do
    test "correctly maps leaves to grid cells", %{tree_name: name} do
      # System node is 130x34, grid is 150x150
      # This should fit in one cell
      leaf = {30_000_142, [{10, 140}, {10, 44}]}
      CacheRTree.insert(leaf, name)

      # Query should find it
      {:ok, ids} = CacheRTree.query([{10, 140}, {10, 44}], name)
      assert 30_000_142 in ids
    end

    test "handles leaves spanning multiple cells", %{tree_name: name} do
      # Large box spanning 4 grid cells (150x150 each)
      large_box = [{0, 300}, {0, 300}]
      CacheRTree.insert({30_000_142, large_box}, name)

      # Should be queryable from any quadrant
      {:ok, ids1} = CacheRTree.query([{50, 100}, {50, 100}], name)
      assert 30_000_142 in ids1

      {:ok, ids2} = CacheRTree.query([{200, 250}, {50, 100}], name)
      assert 30_000_142 in ids2

      {:ok, ids3} = CacheRTree.query([{50, 100}, {200, 250}], name)
      assert 30_000_142 in ids3

      {:ok, ids4} = CacheRTree.query([{200, 250}, {200, 250}], name)
      assert 30_000_142 in ids4
    end

    test "maintains grid consistency on delete", %{tree_name: name} do
      # Insert leaf spanning multiple cells
      large_box = [{0, 300}, {0, 300}]
      CacheRTree.insert({30_000_142, large_box}, name)

      # Delete it
      CacheRTree.delete([30_000_142], name)

      # Should not be found in any cell
      {:ok, ids1} = CacheRTree.query([{50, 100}, {50, 100}], name)
      assert ids1 == []

      {:ok, ids2} = CacheRTree.query([{200, 250}, {200, 250}], name)
      assert ids2 == []
    end

    test "grid handles boundary conditions", %{tree_name: name} do
      # Boxes exactly on grid boundaries
      leaves = [
        # Cell (0,0)
        {30_000_142, [{0, 130}, {0, 34}]},
        # Cell (1,0)
        {30_000_143, [{150, 280}, {0, 34}]},
        # Cell (0,1)
        {30_000_144, [{0, 130}, {150, 184}]}
      ]

      CacheRTree.insert(leaves, name)

      # Each should be queryable
      {:ok, ids1} = CacheRTree.query([{0, 130}, {0, 34}], name)
      assert 30_000_142 in ids1

      {:ok, ids2} = CacheRTree.query([{150, 280}, {0, 34}], name)
      assert 30_000_143 in ids2

      {:ok, ids3} = CacheRTree.query([{0, 130}, {150, 184}], name)
      assert 30_000_144 in ids3
    end
  end

  describe "integration" do
    test "realistic map scenario with many systems", %{tree_name: name} do
      # Simulate 100 systems in a typical map layout
      systems =
        for i <- 1..100 do
          x = rem(i, 10) * 200
          y = div(i, 10) * 100
          {30_000_000 + i, [{x, x + 130}, {y, y + 34}]}
        end

      # Insert all systems
      assert {:ok, %{}} = CacheRTree.insert(systems, name)

      # Query for a specific position
      # System 11: x = 1*200=200, y = 1*100=100, box = [{200, 330}, {100, 134}]
      {:ok, ids} = CacheRTree.query([{200, 330}, {100, 134}], name)
      assert 30_000_011 in ids

      # Delete some systems
      to_delete = Enum.map(1..10, &(&1 + 30_000_000))
      assert {:ok, %{}} = CacheRTree.delete(to_delete, name)

      # Update some systems
      assert {:ok, %{}} = CacheRTree.update(30_000_050, [{1000, 1130}, {500, 534}], name)

      # Verify the update
      {:ok, ids_updated} = CacheRTree.query([{1000, 1130}, {500, 534}], name)
      assert 30_000_050 in ids_updated
    end

    test "handles rapid insert/delete cycles", %{tree_name: name} do
      # Simulate dynamic map updates
      for i <- 1..50 do
        system_id = 30_000_000 + i
        box = [{i * 10, i * 10 + 130}, {i * 5, i * 5 + 34}]

        # Insert
        CacheRTree.insert({system_id, box}, name)

        # Immediately query
        {:ok, ids} = CacheRTree.query(box, name)
        assert system_id in ids

        # Delete every other one
        if rem(i, 2) == 0 do
          CacheRTree.delete([system_id], name)
          {:ok, ids_after} = CacheRTree.query(box, name)
          assert system_id not in ids_after
        end
      end
    end

    test "stress test: position availability checking", %{tree_name: name} do
      # Insert systems in a grid pattern
      for x <- 0..9, y <- 0..9 do
        system_id = x * 10 + y + 30_000_000
        box = [{x * 200, x * 200 + 130}, {y * 100, y * 100 + 34}]
        CacheRTree.insert({system_id, box}, name)
      end

      # Check many positions for availability (simulating auto-positioning)
      test_positions = for x <- 0..20, y <- 0..20, do: {x * 100, y * 50}

      for {x, y} <- test_positions do
        box = [{x, x + 130}, {y, y + 34}]
        {:ok, _ids} = CacheRTree.query(box, name)
        # Not asserting anything, just verifying queries work
      end
    end
  end

  describe "self-healing after cache eviction" do
    # Simulates the Nebulex generational GC dropping the whole rtree: the
    # leaves/grid keys go missing (Cache.get returns nil) even though the map
    # itself is very much alive and has systems on it.
    #
    # Cleanup is registered via on_exit (rather than left as a trailing call
    # in each test body) so it still runs when an assertion fails partway
    # through.
    defp seed_map_with_systems(map_id, systems) do
      WandererApp.Map.new(%{
        id: map_id,
        name: "test map #{map_id}",
        scope: :none,
        owner_id: "owner_#{map_id}",
        acls: [],
        hubs: []
      })

      Enum.each(systems, fn system -> WandererApp.Map.add_system(map_id, system) end)

      ExUnit.Callbacks.on_exit(fn -> Cachex.del(:map_cache, map_id) end)
    end

    defp evict_rtree_cache(name) do
      WandererApp.Cache.delete("rtree:#{name}:leaves")
      WandererApp.Cache.delete("rtree:#{name}:grid")
    end

    defp init_and_register_tree(name) do
      CacheRTree.init_tree(name)
      ExUnit.Callbacks.on_exit(fn -> CacheRTree.clear_tree(name) end)
    end

    test "rebuilds from live map systems when the cache generation is lost" do
      map_id = "map_#{:rand.uniform(1_000_000)}"
      name = "rtree_#{map_id}"

      seed_map_with_systems(map_id, [
        %{solar_system_id: 31_000_016, visible: true, position_x: 1575, position_y: -1935},
        %{solar_system_id: 31_001_269, visible: true, position_x: 100, position_y: 100}
      ])

      init_and_register_tree(name)
      # Cache holds nothing useful yet for this map - GC wiped it before any
      # insert ever ran, which is exactly the production scenario.
      evict_rtree_cache(name)

      # The stale home system's bounding box should come back occupied,
      # rebuilt straight from WandererApp.Map.list_systems/1.
      {:ok, ids} =
        CacheRTree.query(
          WandererApp.Map.PositionCalculator.get_system_bounding_rect(%{
            position_x: 1575,
            position_y: -1935
          }),
          name
        )

      assert 31_000_016 in ids
    end

    test "skips invisible systems and systems without a position on rebuild" do
      map_id = "map_#{:rand.uniform(1_000_000)}"
      name = "rtree_#{map_id}"

      seed_map_with_systems(map_id, [
        %{solar_system_id: 31_000_020, visible: false, position_x: 500, position_y: 500},
        %{solar_system_id: 31_000_021, visible: true, position_x: nil, position_y: nil},
        %{solar_system_id: 31_000_022, visible: true, position_x: 500, position_y: 500}
      ])

      init_and_register_tree(name)
      evict_rtree_cache(name)

      {:ok, ids} =
        CacheRTree.query(
          WandererApp.Map.PositionCalculator.get_system_bounding_rect(%{
            position_x: 500,
            position_y: 500
          }),
          name
        )

      assert 31_000_022 in ids
      assert 31_000_020 not in ids
      assert 31_000_021 not in ids
    end

    test "rebuild happens once, later map changes do not trigger another rebuild" do
      map_id = "map_#{:rand.uniform(1_000_000)}"
      name = "rtree_#{map_id}"

      seed_map_with_systems(map_id, [
        %{solar_system_id: 31_000_030, visible: true, position_x: 0, position_y: 0}
      ])

      init_and_register_tree(name)
      evict_rtree_cache(name)

      # First call triggers the rebuild and writes both keys back.
      {:ok, _ids} = CacheRTree.query([{0, 130}, {0, 34}], name)

      assert is_map(WandererApp.Cache.get("rtree:#{name}:leaves"))
      assert is_map(WandererApp.Cache.get("rtree:#{name}:grid"))

      # Remove the system from the live map. If a query rebuilt from map
      # state on every call, the system would vanish from the rtree too -
      # instead the cached leaves/grid from the earlier rebuild must stay
      # authoritative until something explicitly deletes/updates them.
      WandererApp.Map.remove_system(map_id, 31_000_030)
      {:ok, ids} = CacheRTree.query([{0, 130}, {0, 34}], name)
      assert 31_000_030 in ids
    end

    test "a name without the rtree_ prefix still behaves as an empty tree after key loss" do
      map_id = "map_#{:rand.uniform(1_000_000)}"
      name = "not_a_production_tree_#{map_id}"

      seed_map_with_systems(map_id, [
        %{solar_system_id: 31_000_040, visible: true, position_x: 0, position_y: 0}
      ])

      init_and_register_tree(name)
      evict_rtree_cache(name)

      {:ok, ids} = CacheRTree.query([{0, 130}, {0, 34}], name)
      assert ids == []
    end

    test "unknown map_id in an rtree_-prefixed name falls back to an empty tree" do
      name = "rtree_does_not_exist_#{:rand.uniform(1_000_000)}"

      init_and_register_tree(name)
      evict_rtree_cache(name)

      {:ok, ids} = CacheRTree.query([{0, 130}, {0, 34}], name)
      assert ids == []
    end
  end

  describe "clear_tree/1" do
    test "removes all tree data from cache", %{tree_name: name} do
      # Insert some data
      CacheRTree.insert({30_000_142, [{100, 230}, {50, 84}]}, name)

      # Clear the tree
      assert :ok = CacheRTree.clear_tree(name)

      # Re-initialize
      CacheRTree.init_tree(name)

      # Should be empty
      {:ok, ids} = CacheRTree.query([{100, 230}, {50, 84}], name)
      assert ids == []
    end
  end
end
