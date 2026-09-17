defmodule WandererApp.DiscordRoleAclTest do
  @moduledoc """
  A Discord role access list end to end, over real records and the real roles cache.

  The unit tests say what a role member is worth once the roles are known. This says the rest:
  that a stored access list actually reaches the permission check with its guild and role intact,
  and, more importantly, that access follows the link. Unlinking a Discord account has to take
  away what the link was granting straight away rather than at the end of the cache lifetime, and
  that is exactly the path a cache makes easy to get wrong.
  """

  use WandererApp.IntegrationCase, async: false

  import WandererAppWeb.Factory

  alias WandererApp.Discord.Roles
  alias WandererApp.Permissions

  @guild "700000000000000001"
  @role "800000000000000001"
  @discord_user "900000000000000001"

  @view_system 1
  @track_character 64

  setup do
    previous_client = Application.get_env(:wanderer_app, :discord_http_client)
    previous_config = Application.get_env(:wanderer_app, WandererApp.Discord)

    Application.put_env(:wanderer_app, :discord_http_client, __MODULE__.FakeDiscord)

    Application.put_env(:wanderer_app, WandererApp.Discord,
      bot_token: "bot-token",
      client_id: "client-id",
      client_secret: "client-secret"
    )

    on_exit(fn ->
      restore(:discord_http_client, previous_client)
      restore(WandererApp.Discord, previous_config)
      :persistent_term.erase({__MODULE__, :roles})
    end)

    user = create_user(%{name: "Discord ACL", hash: "discord_acl_#{:rand.uniform(1_000_000)}"})

    character =
      create_character(%{
        eve_id: "#{4_200_000_000 + :rand.uniform(100_000)}",
        name: "Discord ACL Character",
        user_id: user.id
      })

    owner_character = create_character(%{name: "Discord ACL Owner"})

    acl = create_access_list(owner_character.id, %{})

    {:ok, acl} =
      WandererApp.Api.AccessList.update(acl, %{discord_guild_id: @guild})

    create_access_list_member(acl.id, %{
      name: "Scouts",
      eve_character_id: nil,
      discord_role_id: @role,
      role: :member
    })

    {:ok, acl} = Ash.load(acl, [:members])

    holds([@role])
    Roles.forget(@discord_user)

    %{user: user, character: character, acl: acl}
  end

  defp link!(user) do
    {:ok, user} =
      WandererApp.Api.User.link_discord(user, %{
        discord_user_id: @discord_user,
        discord_username: "someone"
      })

    WandererApp.Discord.Link.revoke_derived_access(user.id, @discord_user)

    user
  end

  defp access(character, acl) do
    [mask] = Permissions.check_characters_access([character], [acl])
    mask
  end

  test "an unlinked account gets nothing from a Discord role member", %{
    character: character,
    acl: acl
  } do
    refute Permissions.check_permission(access(character, acl), @view_system)
  end

  test "a linked account holding the role gets what the role grants", %{
    user: user,
    character: character,
    acl: acl
  } do
    link!(user)

    mask = access(character, acl)

    assert Permissions.check_permission(mask, @view_system)
    assert Permissions.check_permission(mask, @track_character)
  end

  test "a linked account not holding the role gets nothing", %{
    user: user,
    character: character,
    acl: acl
  } do
    link!(user)
    holds([])
    Roles.forget(@discord_user)

    refute Permissions.check_permission(access(character, acl), @view_system)
  end

  test "unlinking takes the access away at once, not when the cache happens to expire", %{
    user: user,
    character: character,
    acl: acl
  } do
    user = link!(user)

    # warm the cache, so the stale answer is there to be got wrong
    assert Permissions.check_permission(access(character, acl), @view_system)

    assert {:ok, _} = WandererApp.Discord.Link.unlink(user.id)

    refute Permissions.check_permission(access(character, acl), @view_system)
  end

  test "an unreachable Discord grants nothing rather than the last known answer", %{
    user: user,
    character: character,
    acl: acl
  } do
    link!(user)
    assert Permissions.check_permission(access(character, acl), @view_system)

    holds(:unreachable)
    Roles.forget(@discord_user)

    refute Permissions.check_permission(access(character, acl), @view_system)
  end

  test "a character member of the same list is unaffected by any of it", %{
    character: character,
    acl: acl
  } do
    create_access_list_member(acl.id, %{
      name: "By character",
      eve_character_id: character.eve_id,
      role: :member
    })

    {:ok, acl} = Ash.load(acl, [:members], reuse_values?: false)

    holds(:unreachable)

    mask = access(character, acl)

    assert Permissions.check_permission(mask, @view_system)
    assert Permissions.check_permission(mask, @track_character)
  end

  defp holds(value), do: :persistent_term.put({__MODULE__, :roles}, value)

  defp restore(key, nil), do: Application.delete_env(:wanderer_app, key)
  defp restore(key, value), do: Application.put_env(:wanderer_app, key, value)

  defmodule FakeDiscord do
    @moduledoc false

    def get(_url, _opts) do
      case :persistent_term.get({WandererApp.DiscordRoleAclTest, :roles}, []) do
        :unreachable -> {:error, :econnrefused}
        roles -> {:ok, %{status: 200, body: %{"roles" => roles}}}
      end
    end
  end
end
