defmodule WandererApp.Discord.Roles do
  @moduledoc """
  Which roles a linked person holds in a guild.

  Roles are the one part of this feature that is not ours to keep. They live in Discord, they
  change there, and a map that trusts a stale copy of them is a map that keeps letting somebody
  in after the corp has shown them the door. So the only thing stored here is a short lived
  answer, and the length of that life is the security property of the whole feature:

    **an access list stops honouring a Discord role at most 60 seconds after it is taken away in
    Discord.**

  That number is the cache lifetime below and nothing extends it. There is no refresh on read, no
  keeping a stale answer alive because the next fetch failed, and no background job that renews an
  entry without going to Discord. An entry either came from Discord within the last minute or it
  is not used.

  When Discord cannot be reached we fail closed: the answer is `:error`, and an access list member
  that names a Discord role contributes nothing. Failing open would turn a Discord outage into a
  permission escalation and, worse, would make the window above unbounded, which is the one thing
  the design is built to prevent. The cost of failing closed is bounded, because Discord roles are
  additive here: everything a character, corporation or alliance member grants is untouched by a
  Discord outage.

  Errors are remembered briefly, under their own key, so an outage is not amplified into a request
  storm. That key is deliberately separate from the success key, so a remembered failure can never
  be mistaken for "this person holds no roles".

  Reading roles needs a bot in the guild, because we hold no Discord token for the person. Without
  `WANDERER_DISCORD_BOT_TOKEN` this returns `:error` for everything and role members stay inert.
  """

  require Logger

  alias WandererApp.Discord.Config

  # how long a good answer is trusted; this is the revocation window
  @ttl :timer.seconds(60)
  # how long a bad answer is remembered, purely to spare Discord during an outage
  @error_ttl :timer.seconds(15)

  @doc """
  The role ids a user holds in a guild, as a MapSet.

  `{:ok, roles}` means Discord was asked within the cache lifetime and this is its answer, which
  may legitimately be empty. `:error` means we do not know, and callers must treat that as
  granting nothing.
  """
  @spec for_user(String.t() | nil, String.t() | nil) :: {:ok, MapSet.t()} | :error
  def for_user(nil, _guild_id), do: :error
  def for_user(_user_id, nil), do: :error

  def for_user(user_id, guild_id) when is_binary(user_id) and is_binary(guild_id) do
    cond do
      not Config.roles_enabled?() ->
        :error

      not is_nil(WandererApp.Cache.get(error_key(user_id, guild_id))) ->
        :error

      true ->
        case WandererApp.Cache.get(key(user_id, guild_id)) do
          nil -> fetch_and_cache(user_id, guild_id)
          roles -> {:ok, roles}
        end
    end
  end

  @doc """
  Whether a user holds a role. Never true when we could not find out.
  """
  @spec has_role?(String.t() | nil, String.t() | nil, String.t()) :: boolean()
  def has_role?(user_id, guild_id, role_id) do
    case for_user(user_id, guild_id) do
      {:ok, roles} -> MapSet.member?(roles, role_id)
      :error -> false
    end
  end

  @doc """
  Throws away everything remembered about a user, in every guild.

  Used when a link is made or removed, so access follows the link immediately rather than after
  the cache lifetime.
  """
  @spec forget(String.t()) :: :ok
  def forget(user_id) when is_binary(user_id) do
    # every key carries a generation, so bumping it orphans everything remembered about this
    # person in one step, whichever guilds they had been looked up in
    WandererApp.Cache.put(generation_key(user_id), System.unique_integer([:positive, :monotonic]))
    :ok
  end

  defp fetch_and_cache(user_id, guild_id) do
    case fetch(user_id, guild_id) do
      {:ok, roles} ->
        WandererApp.Cache.put(key(user_id, guild_id), roles, ttl: ttl())
        {:ok, roles}

      :error ->
        WandererApp.Cache.put(error_key(user_id, guild_id), true, ttl: @error_ttl)
        :error
    end
  end

  defp fetch(user_id, guild_id) do
    url = "#{Config.api_base()}/guilds/#{guild_id}/members/#{user_id}"

    case client().get(url,
           headers: [{"authorization", "Bot #{Config.bot_token()}"}],
           retry: false,
           receive_timeout: :timer.seconds(10)
         ) do
      {:ok, %{status: status, body: %{"roles" => roles}}} when status in 200..299 ->
        {:ok, roles |> Enum.map(&to_string/1) |> MapSet.new()}

      # not a member of the guild any more, which is a real answer and not a failure
      {:ok, %{status: 404}} ->
        {:ok, MapSet.new()}

      {:ok, %{status: status}} ->
        Logger.warning("[Discord] guild member lookup refused with status #{status}")
        :error

      {:error, reason} ->
        Logger.warning("[Discord] could not reach Discord: #{inspect(reason)}")
        :error
    end
  end

  defp key(user_id, guild_id),
    do: "discord_roles:#{user_id}:#{generation(user_id)}:#{guild_id}"

  defp error_key(user_id, guild_id),
    do: "discord_roles_error:#{user_id}:#{generation(user_id)}:#{guild_id}"

  defp generation_key(user_id), do: "discord_roles_generation:#{user_id}"

  defp generation(user_id), do: WandererApp.Cache.get(generation_key(user_id)) || 0

  defp ttl, do: Application.get_env(:wanderer_app, :discord_roles_ttl, @ttl)

  defp client, do: Application.get_env(:wanderer_app, :discord_http_client, Req)
end
