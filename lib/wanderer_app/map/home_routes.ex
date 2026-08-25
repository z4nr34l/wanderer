defmodule WandererApp.Map.HomeRoutes do
  @moduledoc """
  How far the chain is from home.

  A chain hangs off k-space in several places at once, and which of those mouths is worth flying
  to is a question of gate jumps from the staging system. This works those out: for every k-space
  system on the map that has a hole to J-space, the shortest gate route from home, sorted, with a
  note on what the route flies through.

  Only gates count. The map's own connections are left out on purpose - the answer is meant for
  someone sitting at home who has not entered the chain yet.
  """

  require Logger

  # EVE gives every J-space system an id in this range, Thera and the shattered ones included
  @j_space_id 31_000_000

  # what the game calls high sec once it has rounded the number
  @high_sec 0.45

  @limit 5

  @route_settings %{path_type: "shortest", avoid_wormholes: true}

  @type entry :: %{
          solar_system_id: integer(),
          name: String.t(),
          jumps: non_neg_integer(),
          security: :high | :low | :mixed
        }

  @doc """
  The shortest routes from home to the mouths of the chain, nearest first.
  """
  @spec build(String.t(), integer(), pos_integer()) :: {:ok, [entry()]} | {:error, term()}
  def build(map_id, home_solar_system_id, limit \\ @limit)

  def build(map_id, home_solar_system_id, limit)
      when is_binary(map_id) and is_integer(home_solar_system_id) do
    # read from the database rather than the running map, so this answers the same whether or not
    # anyone has the map open
    with {:ok, systems} <- WandererApp.MapSystemRepo.get_visible_by_map(map_id),
         {:ok, connections} <- WandererApp.MapConnectionRepo.get_by_map(map_id) do
      case entrances(systems, connections) do
        [] ->
          {:ok, []}

        entrance_ids ->
          {:ok, routes(map_id, home_solar_system_id, entrance_ids, limit)}
      end
    end
  end

  def build(_map_id, _home_solar_system_id, _limit), do: {:error, :no_home_system}

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
    lines =
      entries
      |> Enum.map(fn entry ->
        "#{entry.jumps}J via #{entry.name}#{security_note(entry.security)}"
      end)

    Enum.join(["**Chain from #{home_name}**" | lines], "\n")
  end

  defp security_note(:high), do: " (high sec only)"
  defp security_note(:low), do: " (low/null only)"
  defp security_note(:mixed), do: ""

  defp routes(map_id, home_solar_system_id, entrance_ids, limit) do
    hubs = Enum.map(entrance_ids, &to_string/1)

    {:ok, %{routes: routes, systems_static_data: static_data}} =
      WandererApp.Map.Routes.find(
        map_id,
        hubs,
        to_string(home_solar_system_id),
        @route_settings,
        false
      )

    security_by_system =
      static_data
      |> Enum.reject(&is_nil/1)
      |> Map.new(&{&1.solar_system_id, &1})

    routes
    |> Enum.filter(& &1.has_connection)
    |> Enum.map(&entry(&1, security_by_system))
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(& &1.jumps)
    |> Enum.take(limit)
  end

  defp entry(%{destination: destination, systems: systems}, security_by_system) do
    case Map.get(security_by_system, destination) do
      nil ->
        nil

      %{solar_system_name: name} ->
        securities =
          systems
          |> Enum.map(&Map.get(security_by_system, &1))
          |> Enum.reject(&is_nil/1)
          |> Enum.map(& &1.security)
          |> Enum.map(&to_number/1)
          |> Enum.reject(&is_nil/1)

        %{
          solar_system_id: destination,
          name: name,
          jumps: length(systems),
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
