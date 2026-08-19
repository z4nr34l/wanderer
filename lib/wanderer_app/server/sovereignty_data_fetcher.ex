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

  @doc """
  Who holds the given system, or nil for anywhere without alliance sovereignty.
  """
  @spec get_sovereignty(integer() | nil) :: map() | nil
  def get_sovereignty(nil), do: nil

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
          Logger.debug(fn -> "#{__MODULE__} holds sovereignty for #{map_size(sovereignty)} systems" end)
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

        {:ok, build_sovereignty(held, alliances(held))}

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
