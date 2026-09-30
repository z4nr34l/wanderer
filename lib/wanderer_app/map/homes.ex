defmodule WandererApp.Map.Homes do
  @moduledoc """
  The home systems other maps have declared, and the ways into them.

  Chains meet. A system somebody scans into is, now and then, where another group lives - and the
  useful thing to know about it is how one gets in: which k-space systems have a hole into that
  chain, what kind of space they sit in, and how many holes lie behind them.

  Only maps the person may already see are considered, so this says nothing they could not have
  found by opening those maps themselves.
  """

  require Logger

  # EVE gives every J-space system an id in this range, Thera and the shattered ones included
  @j_space_id 31_000_000

  # what the game calls high sec once it has rounded the number
  @high_sec 0.45

  @type home :: %{
          map_id: String.t(),
          map_name: String.t(),
          map_slug: String.t(),
          solar_system_id: integer()
        }

  @type way_in :: %{
          solar_system_id: integer(),
          name: String.t(),
          class: :high | :low | :null,
          security: number() | nil,
          holes: non_neg_integer()
        }

  @doc """
  The homes declared on the maps this person may see, other than the map they are looking at.
  """
  @spec known(map(), String.t() | nil) :: [home()]
  def known(current_user, except_map_id \\ nil) do
    case WandererApp.Maps.get_available_maps(current_user) do
      {:ok, maps} ->
        maps
        |> Enum.reject(&(&1.id == except_map_id))
        |> Enum.filter(&is_integer(&1.home_solar_system_id))
        |> Enum.map(
          &%{
            map_id: &1.id,
            map_name: &1.name,
            map_slug: &1.slug,
            solar_system_id: &1.home_solar_system_id
          }
        )

      _ ->
        []
    end
  end

  @doc """
  The ways into a home: every k-space system on that map with a hole into the chain that reaches
  it, nearest first.
  """
  @spec ways_in(String.t(), integer()) :: [way_in()]
  def ways_in(map_id, home_solar_system_id)
      when is_binary(map_id) and is_integer(home_solar_system_id) do
    with {:ok, systems} <- WandererApp.MapSystemRepo.get_visible_by_map(map_id),
         {:ok, connections} <- WandererApp.MapConnectionRepo.get_by_map(map_id) do
      depths = hole_depths(connections, home_solar_system_id)

      systems
      |> mouths(connections)
      |> Enum.filter(&Map.has_key?(depths, &1))
      |> Enum.map(&describe(&1, Map.get(depths, &1)))
      |> Enum.reject(&is_nil/1)
      |> Enum.sort_by(&{&1.holes, &1.name})
    else
      _ -> []
    end
  end

  def ways_in(_map_id, _home), do: []

  @doc """
  The k-space systems on a map that have a hole into J-space - the places a chain can be entered
  from. Whether a given one leads to the home is a separate question, answered by the depths.
  """
  @spec mouths([map()], [map()]) :: [integer()]
  def mouths(systems, connections) do
    on_map =
      systems
      |> Enum.filter(&Map.get(&1, :visible, true))
      |> MapSet.new(& &1.solar_system_id)

    connections
    |> Enum.flat_map(fn %{solar_system_source: source, solar_system_target: target} ->
      cond do
        j_space?(source) and k_space?(target) -> [target]
        k_space?(source) and j_space?(target) -> [source]
        true -> []
      end
    end)
    |> Enum.filter(&MapSet.member?(on_map, &1))
    |> Enum.uniq()
  end

  @doc """
  How many holes lie between the home and every system its chain reaches, home itself being none.
  """
  @spec hole_depths([map()], integer()) :: %{integer() => non_neg_integer()}
  def hole_depths(connections, home_solar_system_id) do
    neighbours =
      Enum.reduce(connections, %{}, fn %{
                                         solar_system_source: source,
                                         solar_system_target: target
                                       },
                                       acc ->
        acc
        |> Map.update(source, [target], &[target | &1])
        |> Map.update(target, [source], &[source | &1])
      end)

    walk(neighbours, [home_solar_system_id], %{home_solar_system_id => 0}, 1)
  end

  @doc """
  Which kind of space a security number belongs to.
  """
  @spec class(number() | nil) :: :high | :low | :null
  def class(security) when is_number(security) do
    cond do
      security >= @high_sec -> :high
      security > 0.0 -> :low
      true -> :null
    end
  end

  def class(_security), do: :null

  defp walk(_neighbours, [], depths, _depth), do: depths

  defp walk(neighbours, frontier, depths, depth) do
    next =
      frontier
      |> Enum.flat_map(&Map.get(neighbours, &1, []))
      |> Enum.uniq()
      |> Enum.reject(&Map.has_key?(depths, &1))

    depths = Enum.reduce(next, depths, &Map.put(&2, &1, depth))

    walk(neighbours, next, depths, depth + 1)
  end

  defp describe(solar_system_id, holes) do
    case WandererApp.CachedInfo.get_system_static_info(solar_system_id) do
      {:ok, %{solar_system_name: name} = info} ->
        security = to_number(Map.get(info, :security))

        %{
          solar_system_id: solar_system_id,
          name: name,
          class: class(security),
          security: security,
          holes: holes
        }

      _ ->
        nil
    end
  end

  defp to_number(value) when is_number(value), do: value

  defp to_number(value) when is_binary(value) do
    case Float.parse(value) do
      {number, _rest} -> number
      :error -> nil
    end
  end

  defp to_number(_value), do: nil

  defp j_space?(solar_system_id), do: solar_system_id >= @j_space_id

  defp k_space?(solar_system_id), do: solar_system_id < @j_space_id
end
