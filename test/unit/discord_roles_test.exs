defmodule WandererApp.Discord.RolesTest do
  @moduledoc """
  How fresh a Discord role has to be before it is allowed to grant anything.

  The window between a role being taken away in Discord and access going with it is the security
  property of this feature, so what is pinned down here is that nothing quietly widens it: an
  answer is trusted for the cache lifetime and no longer, a failure is never mistaken for "holds
  no roles", and an unreachable Discord grants nothing rather than everything.
  """

  use ExUnit.Case, async: false

  alias WandererApp.Discord.Roles

  @user "discord-user-1"
  @guild "guild-1"
  @role "role-1"

  setup do
    previous_client = Application.get_env(:wanderer_app, :discord_http_client)
    previous_config = Application.get_env(:wanderer_app, WandererApp.Discord)
    previous_ttl = Application.get_env(:wanderer_app, :discord_roles_ttl)

    Application.put_env(:wanderer_app, :discord_http_client, __MODULE__.FakeDiscord)
    Application.put_env(:wanderer_app, WandererApp.Discord, bot_token: "bot-token")

    on_exit(fn ->
      restore(:discord_http_client, previous_client)
      restore(WandererApp.Discord, previous_config)
      restore(:discord_roles_ttl, previous_ttl)
      :persistent_term.erase({__MODULE__, :response})
      :persistent_term.erase({__MODULE__, :calls})
    end)

    # each test starts from a clean slate rather than inheriting another test's cached answer
    Roles.forget(@user)
    calls(0)

    :ok
  end

  describe "without a bot token" do
    test "nothing is known, so nothing is granted" do
      Application.put_env(:wanderer_app, WandererApp.Discord, [])
      respond({:ok, %{status: 200, body: %{"roles" => [@role]}}})

      assert Roles.for_user(@user, @guild) == :error
      refute Roles.has_role?(@user, @guild, @role)
    end
  end

  describe "asking Discord" do
    test "reports the roles it comes back with" do
      respond({:ok, %{status: 200, body: %{"roles" => [@role, "role-2"]}}})

      assert {:ok, roles} = Roles.for_user(@user, @guild)
      assert MapSet.equal?(roles, MapSet.new([@role, "role-2"]))
      assert Roles.has_role?(@user, @guild, @role)
    end

    test "treats someone who left the guild as holding no roles, not as a failure" do
      respond({:ok, %{status: 404, body: %{}}})

      assert {:ok, roles} = Roles.for_user(@user, @guild)
      assert MapSet.size(roles) == 0
    end

    test "is not asked again inside the cache lifetime" do
      respond({:ok, %{status: 200, body: %{"roles" => [@role]}}})

      assert {:ok, _} = Roles.for_user(@user, @guild)
      assert {:ok, _} = Roles.for_user(@user, @guild)

      assert call_count() == 1
    end

    test "is asked again once the cache lifetime is up, which is the revocation window" do
      Application.put_env(:wanderer_app, :discord_roles_ttl, 30)
      respond({:ok, %{status: 200, body: %{"roles" => [@role]}}})

      assert Roles.has_role?(@user, @guild, @role)

      # the role is taken away in Discord
      respond({:ok, %{status: 200, body: %{"roles" => []}}})

      # and is still honoured, but only until the answer expires
      assert Roles.has_role?(@user, @guild, @role)
      Process.sleep(60)
      refute Roles.has_role?(@user, @guild, @role)
    end
  end

  describe "when Discord cannot be reached" do
    test "we fail closed rather than keeping the last answer alive" do
      respond({:ok, %{status: 200, body: %{"roles" => [@role]}}})
      assert Roles.has_role?(@user, @guild, @role)

      Application.put_env(:wanderer_app, :discord_roles_ttl, 30)
      Roles.forget(@user)
      respond({:error, :econnrefused})

      assert Roles.for_user(@user, @guild) == :error
      refute Roles.has_role?(@user, @guild, @role)
    end

    test "a refusal is not mistaken for holding no roles" do
      respond({:ok, %{status: 500, body: %{}}})

      assert Roles.for_user(@user, @guild) == :error
    end

    test "the failure is remembered briefly, so an outage is not amplified" do
      respond({:error, :econnrefused})

      assert Roles.for_user(@user, @guild) == :error
      assert Roles.for_user(@user, @guild) == :error

      assert call_count() == 1
    end
  end

  describe "forgetting a person" do
    test "drops what was remembered, in every guild" do
      respond({:ok, %{status: 200, body: %{"roles" => [@role]}}})
      assert Roles.has_role?(@user, @guild, @role)

      Roles.forget(@user)
      respond({:ok, %{status: 200, body: %{"roles" => []}}})

      refute Roles.has_role?(@user, @guild, @role)
    end

    test "drops a remembered failure too" do
      respond({:error, :econnrefused})
      assert Roles.for_user(@user, @guild) == :error

      Roles.forget(@user)
      respond({:ok, %{status: 200, body: %{"roles" => [@role]}}})

      assert Roles.has_role?(@user, @guild, @role)
    end
  end

  test "nothing is known about somebody with no link" do
    assert Roles.for_user(nil, @guild) == :error
  end

  test "nothing is known when the access list names no guild" do
    assert Roles.for_user(@user, nil) == :error
  end

  defp restore(key, nil), do: Application.delete_env(:wanderer_app, key)
  defp restore(key, value), do: Application.put_env(:wanderer_app, key, value)

  defp respond(value), do: :persistent_term.put({__MODULE__, :response}, value)

  defp calls(count), do: :persistent_term.put({__MODULE__, :calls}, count)

  defp call_count, do: :persistent_term.get({__MODULE__, :calls}, 0)

  defmodule FakeDiscord do
    @moduledoc false

    def get(_url, _opts) do
      key = {WandererApp.Discord.RolesTest, :calls}
      :persistent_term.put(key, :persistent_term.get(key, 0) + 1)

      :persistent_term.get({WandererApp.Discord.RolesTest, :response})
    end
  end
end
