defmodule WandererApp.Map.HomeRoutesNotifier do
  @moduledoc """
  Posts the routes from home to the chain to a map's Discord webhook.

  Scanning a chain is a burst of changes, and a message per change would be noise. The message
  goes out once the map has been quiet for ten minutes, which in practice is ten minutes after
  whoever was scanning stopped. A run that would say exactly what the last one said is dropped,
  so a chain that has not really moved does not get announced twice.
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
  def init(_opts), do: {:ok, %{timers: %{}, digests: %{}}}

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
  def handle_info({:quiet, map_id}, %{timers: timers, digests: digests} = state) do
    state = %{state | timers: Map.delete(timers, map_id)}
    notifier = self()

    Task.start(fn ->
      case announce(map_id, Map.get(digests, map_id)) do
        {:sent, digest} -> send(notifier, {:sent, map_id, digest})
        :skipped -> :ok
      end
    end)

    {:noreply, state}
  end

  @impl true
  def handle_info({:sent, map_id, digest}, %{digests: digests} = state),
    do: {:noreply, %{state | digests: Map.put(digests, map_id, digest)}}

  @impl true
  def handle_info(_message, state), do: {:noreply, state}

  defp announce(map_id, last_digest) do
    with {:ok, %{discord_webhook_url: url, home_solar_system_id: home_id}}
         when is_binary(url) and url != "" and is_integer(home_id) <-
           WandererApp.Api.Map.by_id(map_id),
         {:ok, entries} <- HomeRoutes.build(map_id, home_id),
         {:ok, home_name} <- system_name(home_id),
         message when is_binary(message) <- HomeRoutes.format_message(home_name, entries) do
      digest = :erlang.phash2(message)

      if digest == last_digest do
        :skipped
      else
        case post(url, message) do
          :ok -> {:sent, digest}
          :error -> :skipped
        end
      end
    else
      _ -> :skipped
    end
  end

  defp system_name(solar_system_id) do
    case WandererApp.CachedInfo.get_system_static_info(solar_system_id) do
      {:ok, %{solar_system_name: name}} -> {:ok, name}
      _ -> :error
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

        :error

      {:error, reason} ->
        Logger.warning(fn -> "[HomeRoutes] could not reach Discord: #{inspect(reason)}" end)
        :error
    end
  end

  defp quiet_period,
    do: Application.get_env(:wanderer_app, :home_routes_quiet_period, @quiet_period)
end
