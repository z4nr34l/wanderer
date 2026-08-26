defmodule WandererApp.Map.HomeRoutes do
  @moduledoc """
  How far home is from each of the map's hubs.

  This is the same question the routes widget answers, asked the same way: the route runs from a
  hub to home over gates and over the map's own connections, so the number is the whole trip,
  chain included. What the message adds is where you leave k-space - the last system before the
  chain, which is the one you have to fly to.
  """

  require Logger

  # EVE gives every J-space system an id in this range, Thera and the shattered ones included
  @j_space_id 31_000_000

  # what the game calls high sec once it has rounded the number
  @high_sec 0.45

  @limit 5

  @type entry :: %{
          hub_name: String.t(),
          entrance_name: String.t(),
          jumps: non_neg_integer(),
          security: :high | :low | :mixed
        }

  @doc """
  The way home from each hub, nearest first: the whole trip in jumps, and the system the chain
  is entered from.
  """
  @spec build(String.t(), [integer()], integer(), keyword()) ::
          {:ok, [entry()]} | {:error, term()}
  def build(map_id, hub_ids, home_solar_system_id, opts \\ [])

  def build(map_id, hub_ids, home_solar_system_id, opts)
      when is_binary(map_id) and is_list(hub_ids) and hub_ids != [] and
             is_integer(home_solar_system_id) do
    limit = Keyword.get(opts, :limit, @limit)
    route_settings = %{include_thera: Keyword.get(opts, :include_thera, true)}

    hubs =
      hub_ids
      |> Enum.reject(&(&1 == home_solar_system_id))
      |> Enum.map(&to_string/1)

    case hubs do
      [] ->
        {:ok, []}

      hubs ->
        {:ok, %{routes: routes, systems_static_data: static_data}} =
          WandererApp.Map.Routes.find(
            map_id,
            hubs,
            to_string(home_solar_system_id),
            route_settings,
            false
          )

        static_by_system =
          static_data
          |> Enum.reject(&is_nil/1)
          |> Map.new(&{&1.solar_system_id, &1})

        entries =
          routes
          |> Enum.filter(& &1.has_connection)
          |> Enum.map(&entry(&1, static_by_system))
          |> Enum.reject(&is_nil/1)
          # ties settled by name, so two runs of the same chain read the same way round
          |> Enum.sort_by(&{&1.jumps, &1.hub_name})
          |> Enum.take(limit)

        {:ok, entries}
    end
  end

  def build(_map_id, [], _home, _opts), do: {:error, :no_hubs}
  def build(_map_id, _hubs, _home, _opts), do: {:error, :no_home_system}

  @doc """
  Splits a route that starts inside the chain into the system the chain is entered from and the
  k-space leg that leads to it.

  The systems come in the order the route builder gives them, which starts at home, so the first
  k-space system in the list is the last one before the chain on the way in.
  """
  @spec split_at_chain([integer()]) :: {integer(), [integer()]} | :error
  def split_at_chain(systems) do
    case Enum.find_index(systems, &k_space?/1) do
      nil -> :error
      index -> {Enum.at(systems, index), Enum.drop(systems, index)}
    end
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
      Enum.map(
        entries,
        &"#{&1.hub_name}: #{&1.jumps}J via #{&1.entrance_name}#{security_note(&1.security)}"
      )

    Enum.join(["**Way home to #{home_name}**" | lines], "\n")
  end

  defp security_note(:high), do: " (high sec only)"
  defp security_note(:low), do: " (low/null only)"
  defp security_note(:mixed), do: ""

  defp entry(%{destination: hub_id, systems: systems}, static_by_system) do
    with {entrance_id, k_space_leg} <- split_at_chain(systems),
         %{solar_system_name: entrance_name} <- Map.get(static_by_system, entrance_id) do
      securities =
        k_space_leg
        |> Enum.map(&Map.get(static_by_system, &1))
        |> Enum.reject(&is_nil/1)
        |> Enum.map(&to_number(&1.security))
        |> Enum.reject(&is_nil/1)

      %{
        hub_name: system_name(hub_id, static_by_system),
        entrance_name: entrance_name,
        jumps: length(systems),
        security: security_label(securities)
      }
    else
      _ -> nil
    end
  end

  defp system_name(solar_system_id, static_by_system) do
    case Map.get(static_by_system, solar_system_id) do
      %{solar_system_name: name} ->
        name

      _ ->
        case WandererApp.CachedInfo.get_system_static_info(solar_system_id) do
          {:ok, %{solar_system_name: name}} -> name
          _ -> "#{solar_system_id}"
        end
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

  defp k_space?(solar_system_id), do: solar_system_id < @j_space_id
end
