defmodule WandererAppWeb.DiscordLinkControllerTest do
  @moduledoc """
  The redirect legs of Discord linking.

  Half of what makes a link trustworthy is that these routes are unreachable unless you are
  already signed in as the account being linked, so that is what is checked here.
  """

  use WandererAppWeb.ConnCase, async: false

  describe "without a session" do
    test "starting a link goes nowhere", %{conn: conn} do
      conn = get(conn, ~p"/characters/discord/link")

      assert redirected_to(conn) == ~p"/characters"
    end

    test "the callback goes nowhere, even with a code in hand", %{conn: conn} do
      conn = get(conn, ~p"/characters/discord/callback?code=stolen&state=stolen")

      assert redirected_to(conn) == ~p"/characters"
    end
  end
end
