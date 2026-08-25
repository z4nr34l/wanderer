defmodule WandererApp.Map.HomeRoutes do
  @moduledoc """
  How far home is from the hubs the map already keeps.

  A chain hangs off k-space in several places at once, and the question worth answering from a
  hub is which of those mouths to fly to: how many gates away it is, what the route passes
  through, and how many holes are left after it. The hubs are the ones set on the map for
  routes, so nothing has to be configured twice.

  Gate jumps are counted from a hub to the mouth. The map's own connections are left out of that
  part on purpose - the reader has not entered the chain yet - and are then used on their own to
  count the holes between the mouth and home.
  """

  require Logger

  # EVE gives every J-space system an id in this range, Thera and the shattered ones included
  @j_space_id 31_000_000

  # what the game calls high sec once it has rounded the number
  @high_sec 0.45

  @limit 5

  @route_settings %{path_type: "shortest", avoid_wormholes: true}

  @type entry :: %{
          hub_name: String.t() | nil,
          solar_system_id: integer(),
          name: String.t(),
          jumps: non_neg_integer(),
          holes: non_neg_integer() | nil,
          security: :high | :low | :mixed
        }

  @doc """
  The best way home from each of the map's hubs, nearest first.
  """
  @spec build(String.t(), [integer()], integer(), pos_integer()) ::
          {:ok, [entry()]} | {:error, term()}
  def build(map_id, hub_ids, home_solar_system_id, limit \\ @limit)

  def build(map_id, hub_ids, home_solar_system_id, limit)
      when is_binary(map_id) and is_list(hub_ids) and hub_ids != [] and
             is_integer(home_solar_system_id) do
    # read from the database rather than the running map, so this answers the same whether or not
    # anyone has the map open
    with {:ok, systems} <- WandererApp.MapSystemRepo.get_visible_by_map(map_id),
         {:ok, connections} <- WandererApp.MapConnectionRepo.get_by_map(map_id) do
      case entrances(systems, connections) do
        [] ->
          {:ok, []}

        entrance_ids ->
          depths = hole_depths(connections, home_solar_system_id)

          entries =
            hub_ids
            |> Enum.flat_map(&best_route(map_id, &1, entrance_ids, depths))
            |> Enum.sort_by(&{&1.jumps, &1.holes || 99})
            |> Enum.take(limit)

          {:ok, entries}
      end
    end
  end

  def build(_map_id, [], _home, _limit), do: {:error, :no_hubs}
  def build(_map_id, _hubs, _home, _limit), do: {:error, :no_home_system}

  @doc """
  The k-space systems on the map that have a hole to J-space - the places you can get to by gate
  and then jump into the chain.
  """
  @spec entrances([map()], [map()]) :: [integer()]
  def entrances(systems, connections) do
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
  How many holes lie between home and every system the chain reaches, home itself being none.

  A system the chain does not reach from home is left out - a mouth on a piece of chain nobody
  has connected to home yet says nothing about how to get home.
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

  @doc """
  What a route flies through: high sec the whole way, never high sec, or a bit of both.
  """
  @spec security_label([number()]) :: :high | :low | :mixed
  def security_label([]), do: :mixed

  def security_label(securities) do
    cond do
      Enum.all?(securities, &(&1 >= @high_sec)) -> :high
      Enum.all?(securities, &(&1 < @high_sec)) -> :low
      true -> :mixed
    end
  end

  @doc """
  The Discord message for a set of routes, or nil when there is nothing worth saying.
  """
  @spec format_message(String.t(), [entry()]) :: String.t() | nil
  def format_message(_home_name, []), do: nil

  def format_message(home_name, entries) do
    lines = Enum.map(entries, &"#{&1.hub_name}: #{&1.jumps}J via #{&1.name}#{note(&1)}")

    Enum.join(["**Way home to #{home_name}**" | lines], "\n")
  end

  defp note(entry) do
    case Enum.reject([security_note(entry.security), holes_note(entry.holes)], &is_nil/1) do
      [] -> ""
      notes -> " (#{Enum.join(notes, ", ")})"
    end
  end

  defp security_note(:high), do: "high sec only"
  defp security_note(:low), do: "low/null only"
  defp security_note(:mixed), do: nil

  defp holes_note(nil), do: nil
  defp holes_note(1), do: "then 1 hole"
  defp holes_note(holes), do: "then #{holes} holes"

  # one line per hub: the mouth that is fewest gates away, and how many holes are left after it
  defp best_route(map_id, hub_id, entrance_ids, depths) do
    {:ok, %{routes: routes, systems_static_data: static_data}} =
      WandererApp.Map.Routes.find(
        map_id,
        Enum.map(entrance_ids, &to_string/1),
        to_string(hub_id),
        @route_settings,
        false
      )

    static_by_system =
      static_data
      |> Enum.reject(&is_nil/1)
      |> Map.new(&{&1.solar_system_id, &1})

    hub_name = hub_name(hub_id)

    routes
    |> Enum.filter(& &1.has_connection)
    |> Enum.map(&entry(&1, static_by_system, depths))
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(&{&1.jumps, &1.holes || 99})
    |> Enum.take(1)
    |> Enum.map(&Map.put(&1, :hub_name, hub_name))
  end

  defp hub_name(hub_id) do
    case WandererApp.CachedInfo.get_system_static_info(hub_id) do
      {:ok, %{solar_system_name: name}} -> name
      _ -> "#{hub_id}"
    end
  end

  defp entry(%{destination: destination, systems: systems}, static_by_system, depths) do
    case Map.get(static_by_system, destination) do
      nil ->
        nil

      %{solar_system_name: name} ->
        securities =
          systems
          |> Enum.map(&Map.get(static_by_system, &1))
          |> Enum.reject(&is_nil/1)
          |> Enum.map(&to_number(&1.security))
          |> Enum.reject(&is_nil/1)

        %{
          hub_name: nil,
          solar_system_id: destination,
          name: name,
          jumps: length(systems),
          holes: Map.get(depths, destination),
          security: security_label(securities)
        }
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
