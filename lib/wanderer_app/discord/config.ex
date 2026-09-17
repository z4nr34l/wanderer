defmodule WandererApp.Discord.Config do
  @moduledoc """
  Reads the Discord application credentials.

  Nothing here is stored in the database. The values come from the environment, by the names
  `WANDERER_DISCORD_CLIENT_ID`, `WANDERER_DISCORD_CLIENT_SECRET` and
  `WANDERER_DISCORD_BOT_TOKEN`, and are wired in `config/runtime.exs`.

  Two separate capabilities are configured here and they are deliberately separate:

    * the OAuth application (client id and secret) is what lets a person prove to us that they
      control a Discord account. It is all the account linking feature needs.

    * the bot token is what lets us ask a guild which roles one of its members holds. Without a
      bot in the guild we cannot answer that question at all, so Discord role permissions stay
      switched off rather than guessing.
  """

  @api_base "https://discord.com/api/v10"

  @spec api_base() :: String.t()
  def api_base, do: Application.get_env(:wanderer_app, :discord_api_base, @api_base)

  @spec client_id() :: String.t() | nil
  def client_id, do: get(:client_id)

  @spec client_secret() :: String.t() | nil
  def client_secret, do: get(:client_secret)

  @spec bot_token() :: String.t() | nil
  def bot_token, do: get(:bot_token)

  @doc """
  Whether a person can link a Discord account at all.
  """
  @spec linking_enabled?() :: boolean()
  def linking_enabled?, do: present?(client_id()) and present?(client_secret())

  @doc """
  Whether we can read guild roles. Role based permissions are inert without this.
  """
  @spec roles_enabled?() :: boolean()
  def roles_enabled?, do: present?(bot_token())

  @spec redirect_uri() :: String.t()
  def redirect_uri do
    case get(:redirect_uri) do
      uri when is_binary(uri) and uri != "" -> uri
      _ -> "#{WandererApp.Env.base_url()}/characters/discord/callback"
    end
  end

  defp get(key) do
    :wanderer_app
    |> Application.get_env(WandererApp.Discord, [])
    |> Keyword.get(key)
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_value), do: false
end
