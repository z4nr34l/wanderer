defmodule WandererApp.Discord.RoleRefresher do
  @moduledoc """
  Keeps the rest of the application honest about Discord roles.

  `WandererApp.Discord.Roles` already bounds how stale an answer can be, but only for code that
  asks. Plenty of things here do not ask again until something tells them to: a live view holds
  the permissions it worked out at mount, and a running map holds its own idea of who may be on
  it. Left alone, a role taken away in Discord would be honoured until one of those happened to
  refresh.

  So this walks the access lists that actually name a Discord role, refreshes the role sets of the
  people they could apply to, and when a set has changed says so on exactly the channels an edit
  to the access list would have used. Nothing here decides anything; it only makes the rest of the
  system re-ask, which is what turns the cache lifetime into a real revocation window.

  Only guilds named by an access list and only people who have linked a Discord account are ever
  looked up, so the work is proportional to the feature actually being used and is nothing at all
  when it is not.
  """

  use GenServer

  require Logger

  alias WandererApp.Discord.Roles

  @interval :timer.seconds(60)

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    schedule()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:refresh, state) do
    state =
      if WandererApp.Discord.Config.roles_enabled?() do
        refresh(state)
      else
        state
      end

    schedule()
    {:noreply, state}
  end

  @impl true
  def handle_info(_message, state), do: {:noreply, state}

  @doc """
  Runs one pass. Exposed so a test can drive it without waiting a minute.
  """
  @spec refresh(map()) :: map()
  def refresh(state) do
    case guild_ids() do
      [] ->
        state

      guild_ids ->
        linked_users()
        |> Enum.reduce(state, fn user, acc ->
          Enum.reduce(guild_ids, acc, fn guild_id, acc ->
            refresh_one(acc, user, guild_id)
          end)
        end)
    end
  end

  defp refresh_one(state, %{id: user_id, discord_user_id: discord_user_id}, guild_id) do
    Roles.forget(discord_user_id)

    case Roles.for_user(discord_user_id, guild_id) do
      {:ok, roles} ->
        case Map.get(state, {discord_user_id, guild_id}) do
          ^roles ->
            state

          _ ->
            announce(user_id)
            Map.put(state, {discord_user_id, guild_id}, roles)
        end

      :error ->
        # we do not know any more, so neither should anything holding the old answer
        case Map.pop(state, {discord_user_id, guild_id}) do
          {nil, state} ->
            state

          {_previous, state} ->
            announce(user_id)
            state
        end
    end
  end

  defp announce(user_id) do
    case WandererApp.Api.Character.active_by_user(%{user_id: user_id}) do
      {:ok, characters} ->
        Enum.each(characters, fn character ->
          Phoenix.PubSub.broadcast(
            WandererApp.PubSub,
            "character:#{character.eve_id}",
            :update_permissions
          )
        end)

      _ ->
        :ok
    end
  end

  defp guild_ids do
    case Ash.read(WandererApp.Api.AccessList, load: [:members]) do
      {:ok, acls} ->
        acls
        |> Enum.filter(fn acl ->
          is_binary(acl.discord_guild_id) and
            Enum.any?(acl.members, &is_binary(&1.discord_role_id))
        end)
        |> Enum.map(& &1.discord_guild_id)
        |> Enum.uniq()

      {:error, error} ->
        Logger.warning("[Discord] could not read access lists: #{inspect(error)}")
        []
    end
  end

  defp linked_users do
    case Ash.read(WandererApp.Api.User) do
      {:ok, users} -> Enum.filter(users, &is_binary(&1.discord_user_id))
      _ -> []
    end
  end

  defp schedule, do: Process.send_after(self(), :refresh, interval())

  defp interval,
    do: Application.get_env(:wanderer_app, :discord_role_refresh_interval, @interval)
end
