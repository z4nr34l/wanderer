defmodule WandererApp.Discord.Link do
  @moduledoc """
  Linking and unlinking a Discord account to a Wanderer account.

  The integrity of the link rests on both halves being proved in the same request:

    * the Wanderer half is proved because the routes that reach here sit behind the authenticated
      pipeline, so the person is already signed in with EVE SSO as this user;

    * the Discord half is proved because the only way to produce the authorization code is to
      complete Discord's own consent screen while signed in as that Discord account;

    * the two halves are tied together by a single use state value which is minted for one user,
      kept out of the URL of anything we render, and expires in ten minutes. A state minted for
      one user cannot be redeemed by another, so a link cannot be handed to someone else.

  Nothing about this lets a person claim a character. Characters are only ever attached to an
  account by EVE SSO, and this feature does not touch that.
  """

  require Logger

  alias WandererApp.Discord.OAuth

  @state_ttl :timer.minutes(10)

  @doc """
  Starts a link. Returns the URL to send the person to.
  """
  @spec start(String.t()) :: {:ok, String.t()} | {:error, atom()}
  def start(user_id) when is_binary(user_id) do
    if WandererApp.Discord.Config.linking_enabled?() do
      state = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

      WandererApp.Cache.put(state_key(state), user_id, ttl: @state_ttl)

      {:ok, OAuth.authorize_url(state)}
    else
      {:error, :discord_not_configured}
    end
  end

  @doc """
  Completes a link. The state has to be one we minted for this very user, and it is spent
  whether or not the rest succeeds so a code cannot be replayed.
  """
  @spec complete(String.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, atom()}
  def complete(user_id, code, state)
      when is_binary(user_id) and is_binary(code) and is_binary(state) do
    with {:ok, ^user_id} <- take_state(state),
         {:ok, %{id: discord_user_id, username: username}} <- OAuth.identity(code),
         :ok <- ensure_unclaimed(discord_user_id, user_id),
         {:ok, user} <- WandererApp.Api.User.by_id(user_id),
         {:ok, user} <-
           WandererApp.Api.User.link_discord(user, %{
             discord_user_id: discord_user_id,
             discord_username: username
           }) do
      # a fresh link can only grant access, but the caches that hold the old answer have to go
      revoke_derived_access(user_id, discord_user_id)

      {:ok, user}
    else
      {:ok, _other_user_id} -> {:error, :state_mismatch}
      {:error, reason} when is_atom(reason) -> {:error, reason}
      error -> {:error, normalise(error)}
    end
  end

  @doc """
  Removes a link, and with it every permission the link was granting.

  The order matters. The row goes first, so anything that reads the database after this point
  already sees an unlinked account, and only then are the caches that could still be answering
  from the old link thrown away.
  """
  @spec unlink(String.t()) :: {:ok, map()} | {:error, atom()}
  def unlink(user_id) when is_binary(user_id) do
    case WandererApp.Api.User.by_id(user_id) do
      {:ok, %{discord_user_id: discord_user_id} = user} ->
        case WandererApp.Api.User.unlink_discord(user) do
          {:ok, user} ->
            revoke_derived_access(user_id, discord_user_id)
            {:ok, user}

          error ->
            {:error, normalise(error)}
        end

      _ ->
        {:error, :user_not_found}
    end
  end

  @doc """
  Throws away everything that could still be answering from a link this user used to have.

  Called on link, on unlink, and by anything that deletes an account.
  """
  @spec revoke_derived_access(String.t(), String.t() | nil) :: :ok
  def revoke_derived_access(user_id, discord_user_id) when is_binary(user_id) do
    if is_binary(discord_user_id), do: WandererApp.Discord.Roles.forget(discord_user_id)

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

    :ok
  end

  defp take_state(state) do
    case WandererApp.Cache.take(state_key(state)) do
      nil -> {:error, :invalid_state}
      user_id -> {:ok, user_id}
    end
  end

  defp ensure_unclaimed(discord_user_id, user_id) do
    case WandererApp.Api.User.by_discord_user_id(discord_user_id) do
      {:ok, %{id: ^user_id}} -> :ok
      {:ok, _other} -> {:error, :discord_account_already_linked}
      _ -> :ok
    end
  end

  defp state_key(state), do: "discord_link_state:#{state}"

  defp normalise({:error, reason}) when is_atom(reason), do: reason

  defp normalise(error) do
    Logger.warning("[Discord] link failed: #{inspect(error)}")
    :link_failed
  end
end
