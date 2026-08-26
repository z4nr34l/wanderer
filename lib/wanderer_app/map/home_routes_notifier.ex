defmodule WandererApp.Map.HomeRoutesNotifier do
  @moduledoc """
  Posts the way home from the hub to a map's Discord webhook.

  Scanning a chain is a burst of changes, and a message per change would be noise. The message
  goes out once the map has been quiet for ten minutes, which in practice is ten minutes after
  whoever was scanning stopped.

  Plenty of things nudge a map without changing the way home - housekeeping, a restart, a
  connection being touched - so what decides whether anything is posted is the message itself:
  it is kept with the map, and a run that would repeat it says nothing. Keeping it with the map
  rather than in memory is what stops a restart from announcing the same chain again.
  """

  use GenServer

  require Logger

  alias WandererApp.Map.HomeRoutes

  @quiet_period :timer.minutes(10)

  # a change to the shape of the chain - characters moving around it are not one
  @map_change_events [
    :add_system,
    :deleted_system,
    :system_metadata_changed,
    :system_renamed,
    :connection_added,
    :connection_removed,
    :connection_updated,
    :signature_added,
    :signature_removed,
    :signatures_updated
  ]

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc """
  Tells the notifier a map changed. Anything that is not a change of shape is ignored.
  """
  @spec map_changed(String.t(), atom()) :: :ok
  def map_changed(map_id, event_type) when is_binary(map_id) do
    if event_type in @map_change_events and not is_nil(Process.whereis(__MODULE__)) do
      GenServer.cast(__MODULE__, {:changed, map_id})
    end

    :ok
  end

  def map_changed(_map_id, _event_type), do: :ok

  @impl true
  def init(_opts), do: {:ok, %{timers: %{}}}

  @impl true
  def handle_cast({:changed, map_id}, %{timers: timers} = state) do
    case Map.get(timers, map_id) do
      nil -> :ok
      timer -> Process.cancel_timer(timer)
    end

    timer = Process.send_after(self(), {:quiet, map_id}, quiet_period())

    {:noreply, %{state | timers: Map.put(timers, map_id, timer)}}
  end

  @impl true
  def handle_info({:quiet, map_id}, %{timers: timers} = state) do
    Task.start(fn -> announce(map_id) end)

    {:noreply, %{state | timers: Map.delete(timers, map_id)}}
  end

  @impl true
  def handle_info(_message, state), do: {:noreply, state}

  @doc """
  Works out the routes and posts them now, saying what went wrong if it could not.

  This is what the button in the map's settings calls; the timed run goes through the same code
  and only adds the check for a message it has already sent.
  """
  @spec deliver(String.t()) :: {:ok, non_neg_integer()} | {:error, atom()}
  def deliver(map_id) when is_binary(map_id) do
    with {:ok, map, message} <- message_for(map_id),
         {:ok, url} <- webhook(map) do
      post_and_remember(map, url, message)
    end
  end

  # the timed run only speaks when it has something new to say
  defp announce(map_id) do
    with {:ok, map, message} <- message_for(map_id),
         {:ok, url} <- webhook(map) do
      digest = :erlang.phash2(message)

      if digest == map.discord_last_digest do
        Logger.info(fn ->
          "[HomeRoutes] #{map_id}: the way home reads the same as last time (#{digest}), saying nothing"
        end)

        :skipped
      else
        post_and_remember(map, url, message)
      end
    end
  end

  defp message_for(map_id) do
    with {:ok, map} <- map(map_id),
         {:ok, _url} <- webhook(map),
         {:ok, home_id} <- home_system(map),
         {:ok, hub_ids} <- hubs(map),
         {:ok, routes} <- HomeRoutes.build(map_id, hub_ids, home_id),
         {:ok, home_name} <- system_name(home_id, :home_system_unknown),
         message when is_binary(message) <- HomeRoutes.format_message(home_name, routes) do
      {:ok, map, message}
    else
      nil -> {:error, :no_routes}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :unknown}
    end
  end

  defp post_and_remember(map, url, message) do
    case post(url, message) do
      :ok ->
        digest = :erlang.phash2(message)
        remember(map, digest)

        Logger.info(fn ->
          "[HomeRoutes] #{map.id}: posted the way home, #{map.discord_last_digest} -> #{digest}"
        end)

        {:ok, digest}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp remember(map, digest) do
    case WandererApp.Api.Map.update_discord_digest(map, %{discord_last_digest: digest}) do
      {:ok, _map} ->
        :ok

      {:error, reason} ->
        Logger.warning(fn ->
          "[HomeRoutes] could not store the message digest: #{inspect(reason)}"
        end)

        :ok
    end
  end

  defp map(map_id) do
    case WandererApp.Api.Map.by_id(map_id) do
      {:ok, map} -> {:ok, map}
      _ -> {:error, :map_not_found}
    end
  end

  defp webhook(%{discord_webhook_url: url}) when is_binary(url) do
    case String.trim(url) do
      "" -> {:error, :no_webhook}
      trimmed -> {:ok, trimmed}
    end
  end

  defp webhook(_map), do: {:error, :no_webhook}

  defp home_system(%{home_solar_system_id: id}) when is_integer(id), do: {:ok, id}
  defp home_system(_map), do: {:error, :no_home_system}

  # the hubs are the ones the map already keeps for routes
  defp hubs(%{hubs: hubs}) when is_list(hubs) do
    case hubs |> Enum.map(&to_integer/1) |> Enum.reject(&is_nil/1) do
      [] -> {:error, :no_hubs}
      ids -> {:ok, ids}
    end
  end

  defp hubs(_map), do: {:error, :no_hubs}

  defp to_integer(value) when is_integer(value), do: value

  defp to_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, _rest} -> id
      :error -> nil
    end
  end

  defp to_integer(_value), do: nil

  defp system_name(solar_system_id, error) do
    case WandererApp.CachedInfo.get_system_static_info(solar_system_id) do
      {:ok, %{solar_system_name: name}} -> {:ok, name}
      _ -> {:error, error}
    end
  end

  defp post(url, message) do
    case Req.post(url,
           json: %{content: message},
           retry: false,
           receive_timeout: :timer.seconds(15)
         ) do
      {:ok, %{status: status}} when status in 200..299 ->
        :ok

      {:ok, %{status: status, body: body}} ->
        Logger.warning(fn ->
          "[HomeRoutes] Discord refused the message: #{status} #{inspect(body)}"
        end)

        {:error, :discord_refused}

      {:error, reason} ->
        Logger.warning(fn -> "[HomeRoutes] could not reach Discord: #{inspect(reason)}" end)
        {:error, :discord_unreachable}
    end
  end

  defp quiet_period,
    do: Application.get_env(:wanderer_app, :home_routes_quiet_period, @quiet_period)
end
