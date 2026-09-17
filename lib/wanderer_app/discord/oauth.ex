defmodule WandererApp.Discord.OAuth do
  @moduledoc """
  The Discord side of account linking.

  Only the authorization code exchange and the identity lookup live here. The access token that
  comes back is used once, to ask Discord who the person is, and is then dropped. We never store
  a Discord user token, so there is no refresh to keep alive and no user credential of ours to
  leak. Roles are read with the bot token instead, which is what keeps them current.
  """

  require Logger

  alias WandererApp.Discord.Config

  @scope "identify"

  @doc """
  The URL to send someone to so they can approve the link.
  """
  @spec authorize_url(String.t()) :: String.t()
  def authorize_url(state) when is_binary(state) do
    query =
      URI.encode_query(%{
        "client_id" => Config.client_id(),
        "redirect_uri" => Config.redirect_uri(),
        "response_type" => "code",
        "scope" => @scope,
        "state" => state,
        # always ask, so a shared browser cannot silently link whoever logged in last
        "prompt" => "consent"
      })

    "https://discord.com/oauth2/authorize?" <> query
  end

  @doc """
  Turns an authorization code into the Discord identity that approved it.
  """
  @spec identity(String.t()) ::
          {:ok, %{id: String.t(), username: String.t()}} | {:error, atom()}
  def identity(code) when is_binary(code) do
    with {:ok, token} <- exchange(code),
         {:ok, user} <- me(token) do
      {:ok, user}
    end
  end

  defp exchange(code) do
    client_id = Config.client_id()
    client_secret = Config.client_secret()

    case client().post("#{Config.api_base()}/oauth2/token",
           form: %{
             "grant_type" => "authorization_code",
             "code" => code,
             "redirect_uri" => Config.redirect_uri()
           },
           auth: {:basic, "#{client_id}:#{client_secret}"},
           retry: false,
           receive_timeout: :timer.seconds(15)
         ) do
      {:ok, %{status: status, body: %{"access_token" => token}}} when status in 200..299 ->
        {:ok, token}

      {:ok, %{status: status}} ->
        # the body carries the code back to Discord, so it is not logged
        Logger.warning("[Discord] token exchange refused with status #{status}")
        {:error, :token_exchange_failed}

      {:error, reason} ->
        Logger.warning("[Discord] could not reach Discord: #{inspect(reason)}")
        {:error, :discord_unreachable}
    end
  end

  defp me(token) do
    case client().get("#{Config.api_base()}/users/@me",
           headers: [{"authorization", "Bearer #{token}"}],
           retry: false,
           receive_timeout: :timer.seconds(15)
         ) do
      {:ok, %{status: status, body: %{"id" => id} = body}} when status in 200..299 ->
        {:ok, %{id: to_string(id), username: username(body)}}

      {:ok, %{status: status}} ->
        Logger.warning("[Discord] identity lookup refused with status #{status}")
        {:error, :identity_lookup_failed}

      {:error, reason} ->
        Logger.warning("[Discord] could not reach Discord: #{inspect(reason)}")
        {:error, :discord_unreachable}
    end
  end

  defp username(%{"global_name" => name}) when is_binary(name) and name != "", do: name
  defp username(%{"username" => name}) when is_binary(name), do: name
  defp username(_body), do: "unknown"

  defp client, do: Application.get_env(:wanderer_app, :discord_http_client, Req)
end
