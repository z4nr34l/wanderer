defmodule WandererApp.Server.SystemKillsFetcher do
  @moduledoc """
  NPC kills per system - the last hour, and the last day.

  This is what Dotlan's ratting numbers come from: ESI's system kills, which only ever covers the
  hour CCP last published. The day is put together an hour at a time and kept in the database, so
  a restart picks up where it left off instead of starting the day over at every deploy.

  It answers whether anybody lives somewhere and is ratting there now, which the region's
  sovereignty cannot: a region can be an alliance's on paper and empty in practice. It says
  nothing about who - that is the sovereignty's job.

  Each hour is named by the time CCP published it rather than the time it was read, so reading the
  same hour twice - a restart, a retry - replaces it instead of counting it twice.
  """

  use GenServer

  require Logger

  @name :system_kills_fetcher
  @cache :system_kills_day
  @url "https://esi.evetech.net/universe/system_kills/"
  @refresh :timer.minutes(10)
  @retry :timer.minutes(5)
  @timeout :timer.seconds(30)
  @day_seconds 24 * 60 * 60

  @type kills :: %{
          last_hour: non_neg_integer(),
          last_day: non_neg_integer(),
          hours: non_neg_integer()
        }

  @doc """
  NPC kills in a system: the last hour CCP published, the last day, and how many hours that day
  actually covers - fewer than twenty four only in the first day after this was switched on.

  A system ESI leaves out had nothing die in it, which is an answer of zero rather than none.
  """
  @spec npc_kills(integer() | nil) :: kills() | nil
  def npc_kills(nil), do: nil

  def npc_kills(solar_system_id) when is_integer(solar_system_id) do
    case WandererApp.Cache.get(@cache) do
      %{hours: [_ | _] = hours} ->
        key = Integer.to_string(solar_system_id)
        [latest | _] = hours

        %{
          last_hour: Map.get(latest.npc_kills, key, 0),
          last_day: Enum.reduce(hours, 0, &(Map.get(&1.npc_kills, key, 0) + &2)),
          hours: length(hours)
        }

      _ ->
        nil
    end
  end

  def npc_kills(_solar_system_id), do: nil

  def start_link(opts \\ []) do
    GenServer.start(__MODULE__, opts, name: @name)
  end

  @impl true
  def init(_opts) do
    Logger.info("#{__MODULE__} started")
    {:ok, %{}, {:continue, :start}}
  end

  @impl true
  def handle_continue(:start, state) do
    # what was kept before a restart is the day so far, before anything new is asked for
    remember_day()
    send(self(), :refresh)
    {:noreply, state}
  end

  @impl true
  def handle_info(:refresh, state) do
    case read_hour() do
      {:ok, hour, kills} ->
        keep_hour(hour, kills)
        Process.send_after(self(), :refresh, @refresh)

      {:error, reason} ->
        Logger.warning(fn -> "[SystemKills] could not read the hour: #{inspect(reason)}" end)
        Process.send_after(self(), :refresh, @retry)
    end

    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  # ESI's own client keeps the body and drops the headers, and the header is the point here: it is
  # what says which hour this is. Read directly for that reason alone.
  defp read_hour do
    case Req.get(@url,
           headers: [{"user-agent", "Wanderer/#{WandererApp.Env.vsn()}"}],
           retry: false,
           receive_timeout: @timeout
         ) do
      {:ok, %{status: 200, body: body, headers: headers}} when is_list(body) ->
        with {:ok, hour} <- published_at(headers) do
          {:ok, hour, npc_by_system(body)}
        end

      {:ok, %{status: status}} ->
        {:error, {:status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp published_at(headers) do
    with [value | _] <- Map.get(headers, "last-modified"),
         {:ok, parsed} <- Timex.parse(value, "{RFC1123}") do
      {:ok, parsed |> DateTime.truncate(:second)}
    else
      _ -> {:error, :no_last_modified}
    end
  end

  # only where something died, keyed as the database will hand it back
  @doc false
  def npc_by_system(body) do
    body
    |> Enum.flat_map(fn
      %{"system_id" => system_id, "npc_kills" => kills} when is_integer(kills) and kills > 0 ->
        [{Integer.to_string(system_id), kills}]

      _ ->
        []
    end)
    |> Map.new()
  end

  defp keep_hour(hour, kills) do
    case WandererApp.Api.SystemKillsHour.record(%{hour: hour, npc_kills: kills}) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning(fn -> "[SystemKills] could not keep #{hour}: #{inspect(reason)}" end)
    end

    forget_before(DateTime.add(DateTime.utc_now(), -@day_seconds - 3600, :second))
    remember_day()
  end

  # a day and an hour is kept, so the oldest hour of the day is never the one being trimmed away
  defp forget_before(cutoff) do
    case WandererApp.Api.SystemKillsHour.before(cutoff) do
      {:ok, stale} -> Enum.each(stale, &WandererApp.Api.SystemKillsHour.destroy/1)
      _ -> :ok
    end
  end

  defp remember_day do
    since = DateTime.add(DateTime.utc_now(), -@day_seconds, :second)

    case WandererApp.Api.SystemKillsHour.since(since) do
      {:ok, hours} ->
        hours = Enum.sort_by(hours, & &1.hour, {:desc, DateTime})
        WandererApp.Cache.insert(@cache, %{hours: hours})

      _ ->
        :ok
    end
  end
end
