defmodule WandererApp.Discord.LinkTest do
  @moduledoc """
  Linking a Discord account to a Wanderer account.

  What is being pinned down here is mostly what must not happen: a link that someone else started
  cannot be finished by you, a code cannot be spent twice, and a Discord account that already
  belongs to somebody cannot be taken over.
  """

  use WandererApp.DataCase, async: false

  alias WandererApp.Discord.Link

  @discord_id "1234567890"

  setup do
    previous_client = Application.get_env(:wanderer_app, :discord_http_client)
    previous_config = Application.get_env(:wanderer_app, WandererApp.Discord)

    Application.put_env(:wanderer_app, :discord_http_client, __MODULE__.FakeDiscord)

    Application.put_env(:wanderer_app, WandererApp.Discord,
      client_id: "client-id",
      client_secret: "client-secret",
      redirect_uri: "http://localhost/characters/discord/callback"
    )

    on_exit(fn ->
      restore(:discord_http_client, previous_client)
      restore(WandererApp.Discord, previous_config)
      :persistent_term.erase({__MODULE__, :identity})
    end)

    identity(%{"id" => @discord_id, "username" => "someone", "global_name" => "Someone"})

    %{user: WandererAppWeb.Factory.create_user(), other: WandererAppWeb.Factory.create_user()}
  end

  describe "starting a link" do
    test "is refused when the server has no Discord application configured", %{user: user} do
      Application.put_env(:wanderer_app, WandererApp.Discord, [])

      assert {:error, :discord_not_configured} = Link.start(user.id)
    end

    test "hands back an authorize url carrying a state we minted", %{user: user} do
      assert {:ok, url} = Link.start(user.id)

      assert %URI{host: "discord.com"} = URI.parse(url)

      state = state_from(url)
      assert WandererApp.Cache.get("discord_link_state:#{state}") == user.id
    end
  end

  describe "completing a link" do
    test "stores the Discord identity on the account that started it", %{user: user} do
      {:ok, url} = Link.start(user.id)

      assert {:ok, linked} = Link.complete(user.id, "code", state_from(url))

      assert linked.discord_user_id == @discord_id
      assert linked.discord_username == "Someone"
      refute is_nil(linked.discord_linked_at)
    end

    test "refuses a state that was minted for somebody else", %{user: user, other: other} do
      {:ok, url} = Link.start(other.id)

      assert {:error, :state_mismatch} = Link.complete(user.id, "code", state_from(url))

      assert {:ok, reloaded} = WandererApp.Api.User.by_id(user.id)
      assert is_nil(reloaded.discord_user_id)
    end

    test "refuses a state we never minted", %{user: user} do
      assert {:error, :invalid_state} = Link.complete(user.id, "code", "made-up-state")
    end

    test "spends the state, so the same callback cannot be replayed", %{user: user} do
      {:ok, url} = Link.start(user.id)
      state = state_from(url)

      assert {:ok, _linked} = Link.complete(user.id, "code", state)
      assert {:error, :invalid_state} = Link.complete(user.id, "code", state)
    end

    test "refuses a Discord account that already belongs to somebody else", %{
      user: user,
      other: other
    } do
      {:ok, url} = Link.start(other.id)
      assert {:ok, _} = Link.complete(other.id, "code", state_from(url))

      {:ok, url} = Link.start(user.id)

      assert {:error, :discord_account_already_linked} =
               Link.complete(user.id, "code", state_from(url))

      assert {:ok, reloaded} = WandererApp.Api.User.by_id(user.id)
      assert is_nil(reloaded.discord_user_id)
    end

    test "relinking the same Discord account to the same person is allowed", %{user: user} do
      {:ok, url} = Link.start(user.id)
      assert {:ok, _} = Link.complete(user.id, "code", state_from(url))

      {:ok, url} = Link.start(user.id)
      assert {:ok, _} = Link.complete(user.id, "code", state_from(url))
    end

    test "leaves the account alone when Discord cannot be reached", %{user: user} do
      identity(:unreachable)

      {:ok, url} = Link.start(user.id)

      assert {:error, :discord_unreachable} = Link.complete(user.id, "code", state_from(url))

      assert {:ok, reloaded} = WandererApp.Api.User.by_id(user.id)
      assert is_nil(reloaded.discord_user_id)
    end
  end

  describe "unlinking" do
    test "clears every trace of the link", %{user: user} do
      {:ok, url} = Link.start(user.id)
      assert {:ok, _} = Link.complete(user.id, "code", state_from(url))

      assert {:ok, unlinked} = Link.unlink(user.id)

      assert is_nil(unlinked.discord_user_id)
      assert is_nil(unlinked.discord_username)
      assert is_nil(unlinked.discord_linked_at)
    end

    test "frees the Discord account for somebody else to claim", %{user: user, other: other} do
      {:ok, url} = Link.start(user.id)
      assert {:ok, _} = Link.complete(user.id, "code", state_from(url))
      assert {:ok, _} = Link.unlink(user.id)

      {:ok, url} = Link.start(other.id)
      assert {:ok, linked} = Link.complete(other.id, "code", state_from(url))
      assert linked.discord_user_id == @discord_id
    end

    test "is harmless on an account that was never linked", %{user: user} do
      assert {:ok, unlinked} = Link.unlink(user.id)
      assert is_nil(unlinked.discord_user_id)
    end
  end

  defp restore(key, nil), do: Application.delete_env(:wanderer_app, key)
  defp restore(key, value), do: Application.put_env(:wanderer_app, key, value)

  defp state_from(url) do
    url
    |> URI.parse()
    |> Map.get(:query)
    |> URI.decode_query()
    |> Map.fetch!("state")
  end

  defp identity(value), do: :persistent_term.put({__MODULE__, :identity}, value)

  defmodule FakeDiscord do
    @moduledoc false

    def post(_url, _opts) do
      case :persistent_term.get({WandererApp.Discord.LinkTest, :identity}, nil) do
        :unreachable -> {:error, :econnrefused}
        _ -> {:ok, %{status: 200, body: %{"access_token" => "token"}}}
      end
    end

    def get(_url, _opts) do
      case :persistent_term.get({WandererApp.Discord.LinkTest, :identity}, nil) do
        :unreachable -> {:error, :econnrefused}
        body -> {:ok, %{status: 200, body: body}}
      end
    end
  end
end
