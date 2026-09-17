defmodule WandererApp.Permissions.DiscordAclTest do
  @moduledoc """
  What a Discord role member of an access list is worth.

  A Discord role is a group, in the same sense a corporation or an alliance is a group here, so
  most of this is checking it behaves like one: it can let people in, it can block them, it is
  worth nothing on a list that does not say which server it came from, and it never quietly takes
  away what a character, corporation or alliance member had already granted.
  """

  use ExUnit.Case, async: true

  alias WandererApp.Permissions

  @guild "guild-1"
  @role "role-1"

  @view_system 1
  @track_character 64
  @admin_map 16_384

  defp character(attrs \\ %{}) do
    Map.merge(
      %{
        id: "character-1",
        eve_id: "90000001",
        user_id: "user-1",
        corporation_id: 1_000_001,
        alliance_id: 2_000_001
      },
      attrs
    )
  end

  defp acl(members, attrs \\ %{}) do
    Map.merge(
      %{id: "acl-1", owner_id: "somebody-else", discord_guild_id: nil, members: members},
      attrs
    )
    |> Map.put(:members, members)
  end

  defp member(attrs) do
    Map.merge(
      %{
        eve_character_id: nil,
        eve_corporation_id: nil,
        eve_alliance_id: nil,
        discord_role_id: nil,
        role: :viewer
      },
      attrs
    )
  end

  defp holds(roles), do: %{@guild => MapSet.new(roles)}

  describe "a Discord role member" do
    test "grants its role to somebody who holds it" do
      acls = [
        acl([member(%{discord_role_id: @role, role: :member})], %{discord_guild_id: @guild})
      ]

      [mask] = Permissions.check_characters_access([character()], acls, holds([@role]))

      assert Permissions.check_permission(mask, @view_system)
      assert Permissions.check_permission(mask, @track_character)
    end

    test "grants nothing to somebody who does not hold it" do
      acls = [
        acl([member(%{discord_role_id: @role, role: :member})], %{discord_guild_id: @guild})
      ]

      assert Permissions.check_characters_access([character()], acls, holds(["other-role"])) == [
               0
             ]
    end

    test "grants nothing when we could not find out what they hold" do
      acls = [
        acl([member(%{discord_role_id: @role, role: :member})], %{discord_guild_id: @guild})
      ]

      # an unreachable Discord leaves the guild out of the map entirely
      assert Permissions.check_characters_access([character()], acls, %{}) == [0]
    end

    test "grants nothing when the access list does not say which server the role is on" do
      acls = [acl([member(%{discord_role_id: @role, role: :member})])]

      assert Permissions.check_characters_access([character()], acls, holds([@role])) == [0]
    end

    test "can block, and the block beats a grant from another access list" do
      granting = acl([member(%{eve_alliance_id: "2000001", role: :member})], %{id: "acl-2"})

      blocking =
        acl([member(%{discord_role_id: @role, role: :blocked})], %{discord_guild_id: @guild})

      [granted] = Permissions.check_characters_access([character()], [granting], holds([@role]))
      assert Permissions.check_permission(granted, @track_character)

      [blocked] =
        Permissions.check_characters_access([character()], [granting, blocking], holds([@role]))

      assert blocked == 0
    end
  end

  describe "alongside the existing member kinds" do
    test "adds to what a corporation member already granted" do
      acls = [
        acl(
          [
            member(%{eve_corporation_id: "1000001", role: :viewer}),
            member(%{discord_role_id: @role, role: :member})
          ],
          %{discord_guild_id: @guild}
        )
      ]

      [with_role] = Permissions.check_characters_access([character()], acls, holds([@role]))
      [without_role] = Permissions.check_characters_access([character()], acls, holds([]))

      assert Permissions.check_permission(with_role, @track_character)
      assert Permissions.check_permission(without_role, @view_system)
      refute Permissions.check_permission(without_role, @track_character)
    end

    test "an unreachable Discord never takes away what a corporation member granted" do
      acls = [
        acl(
          [
            member(%{eve_corporation_id: "1000001", role: :member}),
            member(%{discord_role_id: @role, role: :viewer})
          ],
          %{discord_guild_id: @guild}
        )
      ]

      [mask] = Permissions.check_characters_access([character()], acls, %{})

      assert Permissions.check_permission(mask, @track_character)
    end

    test "is worth exactly the role it was given, which is why admin is refused upstream" do
      # this function honours whatever role is stored, so nothing here stops an admin grant. The
      # thing that stops it is the access list interface, which refuses admin and manager for a
      # Discord role exactly as it does for a corporation or an alliance. This is only here to be
      # explicit that the restriction lives there and not in the mask arithmetic.
      acls = [
        acl([member(%{discord_role_id: @role, role: :admin})], %{discord_guild_id: @guild})
      ]

      [mask] = Permissions.check_characters_access([character()], acls, holds([@role]))

      assert Permissions.check_permission(mask, @admin_map)
    end
  end

  describe "the existing member kinds on their own" do
    test "a character member is unaffected by any of this" do
      acls = [acl([member(%{eve_character_id: "90000001", role: :member})])]

      [mask] = Permissions.check_characters_access([character()], acls, %{})

      assert Permissions.check_permission(mask, @track_character)
    end

    test "an alliance member is unaffected by any of this" do
      acls = [acl([member(%{eve_alliance_id: "2000001", role: :viewer})])]

      [mask] = Permissions.check_characters_access([character()], acls, %{})

      assert Permissions.check_permission(mask, @view_system)
      refute Permissions.check_permission(mask, @track_character)
    end

    test "a character grant still beats a group block" do
      acls = [
        acl(
          [
            member(%{eve_character_id: "90000001", role: :member}),
            member(%{discord_role_id: @role, role: :blocked})
          ],
          %{discord_guild_id: @guild}
        )
      ]

      [mask] = Permissions.check_characters_access([character()], acls, holds([@role]))

      assert Permissions.check_permission(mask, @track_character)
    end
  end
end
