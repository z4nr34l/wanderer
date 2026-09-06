defmodule WandererApp.Map.CacheRTree do
  @moduledoc """
  Cache-based spatial index implementing DDRT behavior.

  Provides R-tree-like spatial indexing using grid-based storage in Nebulex cache.
  No GenServer processes required - all operations are functional and cache-based.

  ## Storage Structure

  Data is stored in the cache with the following keys:
  - `"rtree:<name>:leaves"` - Map of solar_system_id => {id, bounding_box}
  - `"rtree:<name>:grid"` - Map of {grid_x, grid_y} => [solar_system_id, ...]
  - `"rtree:<name>:config"` - Tree configuration

  ## Spatial Grid

  Uses 150x150 pixel grid cells for O(1) spatial queries. Each system node
  (130x34 pixels) typically overlaps 1-2 grid cells, providing fast collision
  detection without the overhead of GenServer-based tree traversal.
  """

  @behaviour WandererApp.Test.DDRT

  require Logger

  alias WandererApp.Cache

  # Grid cell size in pixels
  @grid_size 150

  # Type definitions matching DDRT behavior
  @type id :: number() | String.t()
  @type coord_range :: {number(), number()}
  @type bounding_box :: list(coord_range())
  @type leaf :: {id(), bounding_box()}

  # ============================================================================
  # Public API - DDRT Behavior Implementation
  # ============================================================================

  @doc """
  Insert one or more leaves into the spatial index.

  ## Parameters
  - `leaf_or_leaves` - Single `{id, bounding_box}` tuple or list of tuples
  - `name` - Name of the R-tree instance

  ## Examples

      iex> CacheRTree.insert({30000142, [{100, 230}, {50, 84}]}, "rtree_map_123")
      {:ok, %{}}

      iex> CacheRTree.insert([
      ...>   {30000142, [{100, 230}, {50, 84}]},
      ...>   {30000143, [{250, 380}, {100, 134}]}
      ...> ], "rtree_map_123")
      {:ok, %{}}
  """
  @impl true
  def insert(leaf_or_leaves, name) do
    leaves = normalize_leaves(leaf_or_leaves)

    # Update leaves storage
    current_leaves = get_leaves(name)

    new_leaves =
      Enum.reduce(leaves, current_leaves, fn {id, box}, acc ->
        Map.put(acc, id, {id, box})
      end)

    put_leaves(name, new_leaves)

    # Update spatial grid
    current_grid = get_grid(name)

    new_grid =
      Enum.reduce(leaves, current_grid, fn leaf, grid ->
        add_to_grid(grid, leaf)
      end)

    put_grid(name, new_grid)

    # Match DRTree return format
    {:ok, %{}}
  end

  @doc """
  Delete one or more leaves from the spatial index.

  ## Parameters
  - `id_or_ids` - Single ID or list of IDs to remove
  - `name` - Name of the R-tree instance

  ## Examples

      iex> CacheRTree.delete([30000142], "rtree_map_123")
      {:ok, %{}}

      iex> CacheRTree.delete([30000142, 30000143], "rtree_map_123")
      {:ok, %{}}
  """
  @impl true
  def delete(id_or_ids, name) do
    ids = normalize_ids(id_or_ids)

    current_leaves = get_leaves(name)
    current_grid = get_grid(name)

    # Remove from leaves and track bounding boxes for grid cleanup
    {new_leaves, removed} =
      Enum.reduce(ids, {current_leaves, []}, fn id, {leaves, removed} ->
        case Map.pop(leaves, id) do
          {nil, leaves} -> {leaves, removed}
          {{^id, box}, leaves} -> {leaves, [{id, box} | removed]}
        end
      end)

    # Update grid
    new_grid =
      Enum.reduce(removed, current_grid, fn {id, box}, grid ->
        remove_from_grid(grid, id, box)
      end)

    put_leaves(name, new_leaves)
    put_grid(name, new_grid)

    {:ok, %{}}
  end

  @doc """
  Update a leaf's bounding box.

  ## Parameters
  - `id` - ID of the leaf to update
  - `box_or_tuple` - Either a new `bounding_box` or `{old_box, new_box}` tuple
  - `name` - Name of the R-tree instance

  ## Examples

      iex> CacheRTree.update(30000142, [{150, 280}, {200, 234}], "rtree_map_123")
      {:ok, %{}}

      iex> CacheRTree.update(30000142, {[{100, 230}, {50, 84}], [{150, 280}, {200, 234}]}, "rtree_map_123")
      {:ok, %{}}
  """
  @impl true
  def update(id, box_or_tuple, name) do
    {old_box, new_box} =
      case box_or_tuple do
        {old, new} ->
          {old, new}

        box ->
          # Need to look up old box
          leaves = get_leaves(name)

          case Map.get(leaves, id) do
            {^id, old} -> {old, box}
            # Will be handled as new insert
            nil -> {nil, box}
          end
      end

    # Delete old, insert new
    if old_box, do: delete([id], name)
    insert({id, new_box}, name)
  end

  @doc """
  Query for all leaves intersecting a bounding box.

  Uses grid-based spatial indexing for O(1) average case performance.

  ## Parameters
  - `bounding_box` - Query bounding box `[{x_min, x_max}, {y_min, y_max}]`
  - `name` - Name of the R-tree instance

  ## Returns
  - `{:ok, [id()]}` - List of IDs intersecting the query box
  - `{:error, term()}` - Error if query fails

  ## Examples

      iex> CacheRTree.query([{200, 330}, {90, 124}], "rtree_map_123")
      {:ok, [30000143]}

      iex> CacheRTree.query([{0, 50}, {0, 50}], "rtree_map_123")
      {:ok, []}
  """
  @impl true
  def query(bounding_box, name) do
    # Get candidate IDs from grid cells
    grid = get_grid(name)
    grid_cells = get_grid_cells(bounding_box)

    candidate_ids =
      grid_cells
      |> Enum.flat_map(fn cell -> Map.get(grid, cell, []) end)
      |> Enum.uniq()

    # Precise intersection test
    leaves = get_leaves(name)

    matching_ids =
      Enum.filter(candidate_ids, fn id ->
        case Map.get(leaves, id) do
          {^id, leaf_box} -> boxes_intersect?(bounding_box, leaf_box)
          nil -> false
        end
      end)

    {:ok, matching_ids}
  rescue
    error -> {:error, error}
  end

  # ============================================================================
  # Initialization and Management
  # ============================================================================

  @doc """
  Initialize an empty R-tree in the cache.

  ## Parameters
  - `name` - Name for this R-tree instance
  - `config` - Optional configuration map (width, verbose, etc.)

  ## Examples

      iex> CacheRTree.init_tree("rtree_map_123")
      :ok

      iex> CacheRTree.init_tree("rtree_map_456", %{width: 150, verbose: false})
      :ok
  """
  @impl true
  def init_tree(name, config \\ %{}) do
    Cache.put(cache_key(name, :leaves), %{})
    Cache.put(cache_key(name, :grid), %{})
    Cache.put(cache_key(name, :config), Map.merge(default_config(), config))
    :ok
  end

  @doc """
  Clear all data for an R-tree from the cache.

  Should be called when a map is shut down to free memory.

  ## Parameters
  - `name` - Name of the R-tree instance to clear

  ## Examples

      iex> CacheRTree.clear_tree("rtree_map_123")
      :ok
  """
  def clear_tree(name) do
    Cache.delete(cache_key(name, :leaves))
    Cache.delete(cache_key(name, :grid))
    Cache.delete(cache_key(name, :config))
    :ok
  end

  # ============================================================================
  # Private Helper Functions
  # ============================================================================

  # Cache access helpers
  defp cache_key(name, suffix), do: "rtree:#{name}:#{suffix}"

  defp get_leaves(name) do
    case Cache.get(cache_key(name, :leaves)) do
      nil ->
        rebuild_from_map(name)
        Cache.get(cache_key(name, :leaves)) || %{}

      leaves ->
        leaves
    end
  end

  defp put_leaves(name, leaves) do
    Cache.put(cache_key(name, :leaves), leaves)
  end

  defp get_grid(name) do
    case Cache.get(cache_key(name, :grid)) do
      nil ->
        rebuild_from_map(name)
        Cache.get(cache_key(name, :grid)) || %{}

      grid ->
        grid
    end
  end

  defp put_grid(name, grid) do
    Cache.put(cache_key(name, :grid), grid)
  end

  # The Nebulex Local adapter is generational: every gc_interval a new
  # generation is created and the oldest one is dropped, so a map that sees
  # no rtree read/write for a couple of gc_intervals loses its leaves/grid
  # keys entirely (Cache.get returns nil, not an error). Left alone, that nil
  # is read as "empty tree" and the next placement lands on top of whatever
  # is already there. Rebuild once from the live map state instead of
  # quietly serving an empty tree out from under a map that is not actually
  # empty.
  #
  # A tree can also come up missing right after an intentional clear_tree/1
  # (map stop, zombie cleanup). Rebuilding here anyway is harmless: the map
  # restart path always calls init_tree/2 before anything else touches the
  # rtree, so this only ever fires for a map that is genuinely still live.
  #
  # Only production tree names ("rtree_<map_id>") can be rebuilt from live
  # state. Anything else (including the arbitrary names tests use, or a
  # map_id that is not loaded in Cachex) falls back to an empty tree exactly
  # like before. insert/delete/update used to be infallible and this runs
  # inside the map server GenServer, so any unexpected failure here (rather
  # than the expected "not found" tuples) must degrade to "no rebuild"
  # instead of crashing the caller.
  defp rebuild_from_map(name) do
    with {:ok, map_id} <- extract_map_id(name),
         {:ok, _map} <- WandererApp.Map.get_map(map_id),
         {:ok, systems} <- WandererApp.Map.list_systems(map_id) do
      placeable = Enum.filter(systems, &placeable?/1)

      Logger.warning(
        "[CacheRTree] rtree for map #{map_id} missing from cache, rebuilding from #{length(placeable)} visible systems"
      )

      {leaves, grid} =
        Enum.reduce(placeable, {%{}, %{}}, fn system, {leaves_acc, grid_acc} ->
          leaf =
            {system.solar_system_id,
             WandererApp.Map.PositionCalculator.get_system_bounding_rect(system)}

          {Map.put(leaves_acc, system.solar_system_id, leaf), add_to_grid(grid_acc, leaf)}
        end)

      put_leaves(name, leaves)
      put_grid(name, grid)
    else
      _ -> :ok
    end
  rescue
    error ->
      Logger.warning(
        "[CacheRTree] rebuild failed for #{name}, falling back to empty tree: #{inspect(error)}"
      )

      :ok
  end

  defp extract_map_id("rtree_" <> map_id) when map_id != "", do: {:ok, map_id}
  defp extract_map_id(_name), do: :error

  # Invisible systems have no business blocking a slot, and systems without
  # a position cannot produce a meaningful bounding box. rtree membership is
  # expected to track visibility 1:1 because every delete path removes a
  # system from map state and from the rtree together.
  defp placeable?(%{visible: true, position_x: x, position_y: y}),
    do: not is_nil(x) and not is_nil(y)

  defp placeable?(_system), do: false

  defp default_config do
    %{
      width: 150,
      grid_size: @grid_size,
      verbose: false
    }
  end

  # Grid operations
  defp add_to_grid(grid, {id, bounding_box}) do
    grid_cells = get_grid_cells(bounding_box)

    Enum.reduce(grid_cells, grid, fn cell, acc ->
      Map.update(acc, cell, [id], fn existing_ids ->
        if id in existing_ids do
          existing_ids
        else
          [id | existing_ids]
        end
      end)
    end)
  end

  defp remove_from_grid(grid, id, bounding_box) do
    grid_cells = get_grid_cells(bounding_box)

    Enum.reduce(grid_cells, grid, fn cell, acc ->
      Map.update(acc, cell, [], fn existing_ids ->
        List.delete(existing_ids, id)
      end)
    end)
  end

  # Calculate which grid cells a bounding box overlaps
  defp get_grid_cells(bounding_box) do
    [{x_min, x_max}, {y_min, y_max}] = bounding_box

    # Calculate cell coordinates using integer division
    # Handles negative coordinates correctly
    cell_x_min = div_floor(x_min, @grid_size)
    cell_x_max = div_floor(x_max, @grid_size)
    cell_y_min = div_floor(y_min, @grid_size)
    cell_y_max = div_floor(y_max, @grid_size)

    # Generate all overlapping cells
    for x <- cell_x_min..cell_x_max,
        y <- cell_y_min..cell_y_max do
      {x, y}
    end
  end

  # Floor division that works correctly with negative numbers
  defp div_floor(a, b) when a >= 0, do: div(a, b)

  defp div_floor(a, b) when a < 0 do
    case rem(a, b) do
      0 -> div(a, b)
      _ -> div(a, b) - 1
    end
  end

  # Check if two bounding boxes intersect
  defp boxes_intersect?(box1, box2) do
    [{x1_min, x1_max}, {y1_min, y1_max}] = box1
    [{x2_min, x2_max}, {y2_min, y2_max}] = box2

    # Boxes intersect if they overlap on both axes (strict intersection - not just touching)
    x_overlap = x1_min < x2_max and x2_min < x1_max
    y_overlap = y1_min < y2_max and y2_min < y1_max

    x_overlap and y_overlap
  end

  # Input normalization
  defp normalize_leaves(leaf) when is_tuple(leaf), do: [leaf]
  defp normalize_leaves(leaves) when is_list(leaves), do: leaves

  defp normalize_ids(id) when is_number(id) or is_binary(id), do: [id]
  defp normalize_ids(ids) when is_list(ids), do: ids
end
