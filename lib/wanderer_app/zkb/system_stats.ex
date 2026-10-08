defmodule WandererApp.Zkb.SystemStats do
  @moduledoc """
  Who flies in a system, read from zKillboard.

  Sovereignty answers who owns null sec, and the faction on the sovereignty map answers which
  rats live there, but neither answers the question somebody asks on rolling out of a chain:
  whose space is this, who will I meet. Kills answer it, because the people who fly somewhere are
  the people who die there and the people who do the killing.

  zKillboard keeps two lists per system and they say different things. The recent one is what is
  happening now and is often empty - a quiet pocket of null sec can go a week without a loss. The
  all-time one is rich but can be years stale. Both are reported, and which one this is is part
  of the answer rather than a footnote, so nobody reads a long-dead renter alliance as the
  neighbours.

  Nothing here is on the path of drawing a map: it is asked for a system at a time, cached, and
  the whole thing shrugs and returns nothing if zKillboard is slow or unhappy.
  """

  require Logger

  @base "https://zkillboard.com/api/stats/solarSystemID"
  @cache_ttl :timer.hours(6)
  @failure_ttl :timer.minutes(10)
  @timeout :timer.seconds(20)
  @top 5

  @type group :: %{id: integer(), name: String.t(), ticker: String.t() | nil, kills: integer()}
  @type stats :: %{window: :recent | :all_time, alliances: [group()], corporations: [group()]}

  @doc """
  The alliances and corporations that fly in a system, most kills first.

  `window` says which question was answered: `:recent` for what is happening now, `:all_time`
  where there has been nothing recent to go on.
  """
  @spec who_flies_here(integer()) :: {:ok, stats()} | {:error, atom()}
  def who_flies_here(solar_system_id) when is_integer(solar_system_id) do
    key = "zkb:stats:#{solar_system_id}"

    case WandererApp.Cache.lookup(key) do
      {:ok, %{} = cached} ->
        {:ok, cached}

      {:ok, :unavailable} ->
        {:error, :unavailable}

      _ ->
        fetch_and_cache(solar_system_id, key)
    end
  end

  def who_flies_here(_solar_system_id), do: {:error, :invalid}

  defp fetch_and_cache(solar_system_id, key) do
    case fetch(solar_system_id) do
      {:ok, stats} ->
        WandererApp.Cache.insert(key, stats, ttl: @cache_ttl)
        {:ok, stats}

      {:error, reason} ->
        # a system nobody has ever died in is a real answer, and so is zKillboard being unhappy;
        # either way it is not worth asking again straight away
        WandererApp.Cache.insert(key, :unavailable, ttl: @failure_ttl)
        {:error, reason}
    end
  end

  defp fetch(solar_system_id) do
    url = "#{@base}/#{solar_system_id}/"

    case Req.get(url,
           headers: [{"user-agent", user_agent()}, {"accept", "application/json"}],
           retry: false,
           receive_timeout: @timeout
         ) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        read(body)

      {:ok, %{status: 429}} ->
        Logger.warning(fn -> "[Zkb] asked too often for #{solar_system_id}" end)
        {:error, :rate_limited}

      {:ok, %{status: status}} ->
        Logger.warning(fn -> "[Zkb] #{url} answered #{status}" end)
        {:error, :unreadable}

      {:error, reason} ->
        Logger.warning(fn -> "[Zkb] could not reach #{url}: #{inspect(reason)}" end)
        {:error, :unreachable}
    end
  end

  @doc false
  def read(body) do
    recent = %{
      alliances: from_top_lists(body, "alliance", :alliance),
      corporations: from_top_lists(body, "corporation", :corporation)
    }

    if recent.alliances == [] and recent.corporations == [] do
      all_time = %{
        alliances: from_all_time(body, "alliance", "allianceID", :alliance),
        corporations: from_all_time(body, "corporation", "corporationID", :corporation)
      }

      if all_time.alliances == [] and all_time.corporations == [] do
        {:error, :nothing_known}
      else
        {:ok, Map.put(all_time, :window, :all_time)}
      end
    else
      {:ok, Map.put(recent, :window, :recent)}
    end
  end

  # the recent lists carry the names themselves, so they cost nothing beyond the one call
  defp from_top_lists(body, type, kind) do
    body
    |> Map.get("topLists", [])
    |> Enum.find(%{}, &(Map.get(&1, "type") == type))
    |> Map.get("values", [])
    |> Enum.reject(&npc?(Map.get(&1, "id"), kind))
    |> Enum.take(@top)
    |> Enum.flat_map(fn entry ->
      case {Map.get(entry, "id"), Map.get(entry, "name")} do
        {id, name} when is_integer(id) and is_binary(name) ->
          [%{id: id, name: name, ticker: nil, kills: Map.get(entry, "kills", 0)}]

        _ ->
          []
      end
    end)
  end

  # the all-time lists carry ids alone, so the names are looked up - only the handful shown
  defp from_all_time(body, type, id_key, kind) do
    body
    |> Map.get("topAllTime", [])
    |> Enum.find(%{}, &(Map.get(&1, "type") == type))
    |> Map.get("data", [])
    |> Enum.reject(&npc?(Map.get(&1, id_key), kind))
    |> Enum.take(@top)
    |> Enum.flat_map(fn entry ->
      with id when is_integer(id) <- Map.get(entry, id_key),
           {:ok, %{name: name, ticker: ticker}} <- describe(kind, id) do
        [%{id: id, name: name, ticker: ticker, kills: Map.get(entry, "kills", 0)}]
      else
        _ -> []
      end
    end)
  end

  # The rats are the other question. EVE keeps its NPC corporations below two million and its
  # factions below one, while a player corporation or alliance - even one carrying an id from the
  # old days, as Goonswarm does - sits far above both.
  @doc false
  def npc?(id, :corporation) when is_integer(id), do: id < 2_000_000
  def npc?(id, :alliance) when is_integer(id), do: id < 1_000_000
  def npc?(_id, _kind), do: false

  defp describe(:alliance, id) do
    case WandererApp.Esi.get_alliance_info(id) do
      {:ok, %{"name" => name} = info} -> {:ok, %{name: name, ticker: info["ticker"]}}
      _ -> :error
    end
  end

  defp describe(:corporation, id) do
    case WandererApp.Esi.get_corporation_info(id) do
      {:ok, %{"name" => name} = info} -> {:ok, %{name: name, ticker: info["ticker"]}}
      _ -> :error
    end
  end

  # zKillboard asks to be told who is calling and how to reach them. What it is told is the
  # instance's own business, so it is configured rather than guessed.
  defp user_agent do
    Application.get_env(:wanderer_app, :zkb_user_agent) ||
      "wanderer-app/#{Application.spec(:wanderer_app, :vsn)} (+https://github.com/wanderer-industries/wanderer)"
  end
end
