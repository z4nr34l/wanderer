defmodule WandererApp.Zkb.SystemStats do
  @moduledoc """
  Who has been seen in a system lately, read from the kills in it.

  Out in null sec the neighbours are whoever holds the sovereignty, and the region says whose
  part of space a system sits in even where nobody holds it outright. A wormhole has neither.
  The only thing that can answer who is around in a hole is who has been shooting in it, and
  only recently: a fight two months ago says nothing about who is in the chain today, and the
  fleets that pass through a null sec neighbour say nothing about who lives there.

  So the window is short and fixed - the last two days - and the question is asked for wormholes
  alone. Nothing here is on the path of drawing a map: it is asked for one system at a time, as
  somebody looks at it, cached, and it shrugs if zKillboard is slow or unhappy.

  NPC corporations are dropped. The rats are a different question, and nobody calls them the
  neighbours.
  """

  require Logger

  @base "https://zkillboard.com/api/kills/solarSystemID"
  @window_seconds 172_800
  @cache_ttl :timer.hours(1)
  @failure_ttl :timer.minutes(10)
  @timeout :timer.seconds(20)
  @top 5

  @type group :: %{id: integer(), name: String.t(), ticker: String.t() | nil, kills: integer()}
  @type stats :: %{alliances: [group()], corporations: [group()]}

  @doc """
  The alliances and corporations seen in a system over the last two days, most seen first.
  """
  @spec who_flies_here(integer()) :: {:ok, stats()} | {:error, atom()}
  def who_flies_here(solar_system_id) when is_integer(solar_system_id) do
    key = "zkb:seen:#{solar_system_id}"

    case WandererApp.Cache.lookup(key) do
      {:ok, %{} = cached} -> {:ok, cached}
      {:ok, :unavailable} -> {:error, :unavailable}
      _ -> fetch_and_cache(solar_system_id, key)
    end
  end

  def who_flies_here(_solar_system_id), do: {:error, :invalid}

  defp fetch_and_cache(solar_system_id, key) do
    case fetch(solar_system_id) do
      {:ok, stats} ->
        WandererApp.Cache.insert(key, stats, ttl: @cache_ttl)
        {:ok, stats}

      {:error, reason} ->
        # a quiet hole is a real answer and so is zKillboard being unhappy; either way it is not
        # worth asking again straight away
        WandererApp.Cache.insert(key, :unavailable, ttl: @failure_ttl)
        {:error, reason}
    end
  end

  defp fetch(solar_system_id) do
    url = "#{@base}/#{solar_system_id}/pastSeconds/#{@window_seconds}/"

    case Req.get(url,
           headers: [{"user-agent", user_agent()}, {"accept", "application/json"}],
           retry: false,
           receive_timeout: @timeout
         ) do
      {:ok, %{status: 200, body: killmails}} when is_list(killmails) ->
        {:ok, tally(killmails)}

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
  def tally(killmails) do
    %{
      alliances: count(killmails, "alliance_id", :alliance),
      corporations: count(killmails, "corporation_id", :corporation)
    }
  end

  defp count(killmails, key, kind) do
    killmails
    |> counts(key, kind)
    |> Enum.flat_map(fn {id, kills} ->
      case describe(kind, id) do
        {:ok, %{name: name, ticker: ticker}} ->
          [%{id: id, name: name, ticker: ticker, kills: kills}]

        _ ->
          []
      end
    end)
  end

  @doc """
  How many of the kills each group was in, most first, before anybody's name is looked up.

  One kill counts once for anybody who was in it, however many ships they brought: a fleet of
  thirty is one group being there, not thirty.
  """
  @spec counts([map()], String.t(), :alliance | :corporation) :: [{integer(), integer()}]
  def counts(killmails, key, kind) do
    killmails
    |> Enum.flat_map(&involved(&1, key))
    |> Enum.reject(&npc?(&1, kind))
    |> Enum.frequencies()
    |> Enum.sort_by(fn {id, kills} -> {-kills, id} end)
    |> Enum.take(@top)
  end

  defp involved(killmail, key) do
    victim = killmail |> Map.get("victim", %{}) |> Map.get(key)

    attackers =
      killmail
      |> Map.get("attackers", [])
      |> Enum.map(&Map.get(&1, key))

    [victim | attackers]
    |> Enum.filter(&is_integer/1)
    |> Enum.uniq()
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
