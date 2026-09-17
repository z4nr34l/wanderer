defmodule WandererAppWeb.DiscordLinkController do
  @moduledoc """
  The redirect leg of linking a Discord account.

  This is a plain controller rather than a second Ueberauth provider on purpose. Ueberauth here
  is the sign in path: it creates sessions and characters. Linking never does either, it only
  attaches an identity to an account that is already signed in, so it stays out of that code and
  out of the way of upstream merges.
  """

  use WandererAppWeb, :controller

  require Logger

  alias WandererApp.Discord.Link

  def link(%{assigns: %{current_user: %{id: user_id}}} = conn, _params) do
    case Link.start(user_id) do
      {:ok, url} ->
        redirect(conn, external: url)

      {:error, reason} ->
        conn
        |> put_flash(:error, message(reason))
        |> redirect(to: ~p"/characters")
    end
  end

  def callback(%{assigns: %{current_user: %{id: user_id}}} = conn, %{
        "code" => code,
        "state" => state
      }) do
    case Link.complete(user_id, code, state) do
      {:ok, user} ->
        conn
        |> put_flash(:info, "Discord account #{user.discord_username} linked")
        |> redirect(to: ~p"/characters")

      {:error, reason} ->
        Logger.warning("[Discord] link rejected for user #{user_id}: #{reason}")

        conn
        |> put_flash(:error, message(reason))
        |> redirect(to: ~p"/characters")
    end
  end

  # Discord sends `error` instead of `code` when the person declines, and anything else is a
  # malformed callback. Neither is worth an exception.
  def callback(conn, _params) do
    conn
    |> put_flash(:error, "Discord linking was cancelled")
    |> redirect(to: ~p"/characters")
  end

  defp message(:discord_not_configured),
    do: "Discord linking is not configured on this server"

  defp message(:discord_account_already_linked),
    do: "That Discord account is already linked to another Wanderer account"

  defp message(:invalid_state),
    do: "That linking request expired, please try again"

  defp message(:state_mismatch),
    do: "That linking request belongs to a different account"

  defp message(:discord_unreachable),
    do: "Discord could not be reached, please try again"

  defp message(_reason), do: "Could not link the Discord account"
end
