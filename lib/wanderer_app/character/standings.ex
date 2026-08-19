defmodule WandererApp.Character.Standings do
  @moduledoc """
  What a character thinks of the alliances holding null sec.

  Read from EVE rather than kept in settings: a character's contacts already say who is blue, and
  two characters in different alliances disagree by design. Nothing here is stored beyond a short
  cache, so there is no copy to drift.
  """

  require Logger

  alias WandererApp.Standings

  # contacts change rarely, and switching character should not mean waiting on ESI every time
  @ttl :timer.minutes(30)

  # a read that came back with nothing is usually a token or a role problem rather than an empty
  # contact list, and holding onto that for half an hour means fixing the token appears to do
  # nothing
  @empty_ttl :timer.minutes(1)

  @doc """
  The character's standings towards alliances, most hostile first.

  Its own contacts are the floor; the corporation and alliance lists are layered over them where
  ESI allows, since the group's position beats the personal one.
  """
  @spec for_character(map()) :: [map()]
  def for_character(%{id: id, access_token: access_token} = character)
      when not is_nil(access_token) do
    case WandererApp.Cache.lookup("character:#{id}:standings") do
      {:ok, standings} when is_list(standings) ->
        standings

      _ ->
        standings = read(character)
        ttl = if standings == [], do: @empty_ttl, else: @ttl

        WandererApp.Cache.insert("character:#{id}:standings", standings, ttl: ttl)
        standings
    end
  end

  def for_character(_character), do: []

  defp read(character) do
    lists = contact_lists(character)

    if lists == [] do
      Logger.debug(fn -> "[Standings] no contact list readable for character #{character.id}" end)
    end

    # own alliance first: a contact list never mentions the alliance you are in
    lists
    |> Standings.merge()
    |> Standings.with_own_alliance(character.alliance_ticker, character.alliance_name)
  end

  defp contact_lists(character) do
    opts = [access_token: character.access_token, character_id: character.id]

    [
      {"character", fn -> WandererApp.Esi.get_character_contacts(character.eve_id, opts) end},
      {"corporation",
       fn ->
         character.corporation_id &&
           WandererApp.Esi.get_corporation_contacts(character.corporation_id, opts)
       end},
      {"alliance",
       fn ->
         character.alliance_id &&
           WandererApp.Esi.get_alliance_contacts(character.alliance_id, opts)
       end}
    ]
    |> Enum.flat_map(fn {name, fetch} ->
      case fetch.() do
        {:ok, contacts} when is_list(contacts) -> [{name, contacts}]
        _ -> []
      end
    end)
  end
end
