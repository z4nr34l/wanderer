defmodule WandererApp.Server.SovereigntyDataFetcher do
  @moduledoc """
  Keeps a picture of who holds null sec.

  ESI publishes sovereignty for every system in one document, so this pulls the lot on a timer
  rather than asking per system, and resolves the holding alliances to names and tickers once per
  refresh. Only alliance held systems are kept - the faction entries in the same document are
  empire space, which the map already colours by security.
  """
  use GenServer

  require Logger

  @name :sovereignty_data_fetcher

  # ESI caches the sovereignty map for an hour, so asking more often just returns the same body
  @refresh_timeout :timer.hours(1)
  @retry_timeout :timer.minutes(5)
  @alliance_lookup_concurrency 8

  # Which alliance most of a region belongs to. A system of its own says who holds that system;
  # this says whose part of space it sits in, which is the question somebody asks on arriving
  # somewhere they do not know. Held apart from the per system map so that nothing asking "who
  # holds this system" can read a region and think it has an answer.
  @regions :sovereignty_regions
  @regions_ttl :timer.hours(6)

  @doc """
  Who holds the given system, or nil for anywhere without alliance sovereignty.
  """
  @spec get_sovereignty(integer() | nil) :: map() | nil
  def get_sovereignty(nil), do: nil

  @doc """
  Whose part of space a region is: the alliance holding most of its null sec, with how much.

  A region is rarely one alliance's - Delve carries seven - so the share is part of the answer
  and a region nobody dominates has no answer at all.
  """
  @spec get_region_sovereignty(integer() | nil) :: map() | nil
  def get_region_sovereignty(nil), do: nil

  def get_region_sovereignty(region_id) do
    case WandererApp.Cache.get(@regions) do
      nil -> nil
      regions -> Map.get(regions, region_id)
    end
  end

  def get_sovereignty(solar_system_id) do
    case WandererApp.Cache.get(@name) do
      nil -> nil
      sovereignty -> Map.get(sovereignty, solar_system_id)
    end
  end

  def start_link(opts \\ []) do
    GenServer.start(__MODULE__, opts, name: @name)
  end

  @impl true
  def init(_opts) do
    Logger.info("#{__MODULE__} started")

    {:ok, %{task_ref: nil}, {:continue, :start}}
  end

  @impl true
  def handle_continue(:start, state) do
    Process.send_after(self(), :refresh_data, :timer.seconds(5))

    {:noreply, state}
  end

  @impl true
  def handle_info(:refresh_data, %{task_ref: nil} = state) do
    task = Task.async(fn -> load_data() end)

    {:noreply, %{state | task_ref: task.ref}}
  end

  @impl true
  def handle_info(:refresh_data, state) do
    Logger.debug("#{__MODULE__} skipping refresh, previous task still running")
    Process.send_after(self(), :refresh_data, @refresh_timeout)

    {:noreply, state}
  end

  @impl true
  def handle_info({ref, result}, %{task_ref: ref} = state) do
    Process.demonitor(ref, [:flush])

    next =
      case result do
        {:ok, sovereignty} ->
          WandererApp.Cache.insert(@name, sovereignty)

          Logger.debug(fn ->
            "#{__MODULE__} holds sovereignty for #{map_size(sovereignty)} systems"
          end)

          @refresh_timeout

        {:error, reason} ->
          Logger.warning("#{__MODULE__} failed to load sovereignty: #{inspect(reason)}")
          @retry_timeout
      end

    Process.send_after(self(), :refresh_data, next)

    {:noreply, %{state | task_ref: nil}}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, %{task_ref: ref} = state) do
    Logger.error("#{__MODULE__} task crashed: #{inspect(reason)}")
    Process.send_after(self(), :refresh_data, @retry_timeout)

    {:noreply, %{state | task_ref: nil}}
  end

  @impl true
  def handle_info(_action, state), do: {:noreply, state}

  defp load_data do
    case WandererApp.Esi.get_sovereignty_map() do
      {:ok, entries} when is_list(entries) ->
        held = Enum.filter(entries, &is_integer(&1["alliance_id"]))
        by_system = build_sovereignty(held, alliances(held))

        WandererApp.Cache.insert(@regions, build_regions(by_system), ttl: @regions_ttl)

        {:ok, by_system}

      {:ok, other} ->
        {:error, {:unexpected_body, other}}

      {:error, reason} ->
        {:error, reason}

      error ->
        {:error, error}
    end
  end

  defp build_sovereignty(held, alliances) do
    held
    |> Enum.flat_map(fn %{"system_id" => solar_system_id, "alliance_id" => alliance_id} ->
      case Map.get(alliances, alliance_id) do
        nil ->
          []

        alliance ->
          [{solar_system_id, Map.put(alliance, :alliance_id, alliance_id)}]
      end
    end)
    |> Map.new()
  end

  # Counted over the null sec of a region only: the high sec a region may also carry belongs to
  # an empire, not to anybody who could hold sovereignty, and counting it would only dilute the
  # share. A plurality is enough to name whose space it is - half of Delve belongs to nobody in
  # particular - but a region with no clear largest holder is left unanswered.
  defp build_regions(by_system) do
    case WandererApp.Api.MapSolarSystem.read() do
      {:ok, systems} ->
        region_of = Map.new(systems, &{&1.solar_system_id, &1.region_id})

        totals =
          systems
          |> Enum.filter(&null_sec?/1)
          |> Enum.frequencies_by(& &1.region_id)

        by_system
        |> Enum.flat_map(fn {solar_system_id, alliance} ->
          case Map.get(region_of, solar_system_id) do
            nil -> []
            region_id -> [{region_id, alliance}]
          end
        end)
        |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
        |> Enum.flat_map(fn {region_id, alliances} ->
          case dominant(alliances) do
            nil ->
              []

            {alliance, held} ->
              [
                {region_id,
                 alliance
                 |> Map.put(:held, held)
                 |> Map.put(:total, Map.get(totals, region_id, held))}
              ]
          end
        end)
        |> Map.new()

      _ ->
        %{}
    end
  end

  defp dominant(alliances) do
    alliances
    |> Enum.frequencies_by(& &1.alliance_id)
    |> Enum.sort_by(&elem(&1, 1), :desc)
    |> case do
      [{alliance_id, held} | rest] ->
        if match?([{_, ^held} | _], rest) do
          # two alliances tied for the largest share: neither is whose space it is
          nil
        else
          {Enum.find(alliances, &(&1.alliance_id == alliance_id)), held}
        end

      [] ->
        nil
    end
  end

  defp null_sec?(%{solar_system_id: solar_system_id, security: security}) do
    solar_system_id < 31_000_000 and
      case security do
        value when is_number(value) -> value <= 0.0
        value when is_binary(value) -> match?({parsed, _} when parsed <= 0.0, Float.parse(value))
        _ -> false
      end
  end

  defp null_sec?(_system), do: false

  # One lookup per alliance rather than per system - a few dozen holders cover all of null sec,
  # and an alliance that will not resolve simply drops out rather than holding up the rest.
  defp alliances(held) do
    held
    |> Enum.map(& &1["alliance_id"])
    |> Enum.uniq()
    |> Task.async_stream(&alliance_info/1,
      max_concurrency: @alliance_lookup_concurrency,
      timeout: :timer.seconds(30),
      on_timeout: :kill_task
    )
    |> Enum.flat_map(fn
      {:ok, {alliance_id, info}} -> [{alliance_id, info}]
      _ -> []
    end)
    |> Map.new()
  end

  defp alliance_info(alliance_id) do
    case WandererApp.Esi.get_alliance_info(alliance_id) do
      {:ok, %{"name" => name, "ticker" => ticker}} ->
        {alliance_id, %{alliance_name: name, alliance_ticker: ticker}}

      _ ->
        {alliance_id, nil}
    end
  end
end
