defmodule WandererApp.Map.Ansiblex do
  @moduledoc """
  Who may fly an Ansiblex Jump Bridge, as the game now decides it.

  Until the Cradle of War update of 2026-09-22 a gate's access list could let anybody through, so
  a bridge drawn on a map was a road for whoever could see it. That is over: CCP removed the
  ability for access lists to grant a bridge to pilots outside the owning alliance, and restricted
  a jump to capsuleers in the alliance holding sovereignty over the system the jump starts from.
  A coalition partner's gate is simply not a road any more.

      "Removed the ability for Access Control Lists (ACLs) to grant Ansiblex Jump Bridge access to
      pilots outside the owning alliance."
      - Patch Notes, Version 24.01, build 2026-09-22.1

  Nothing in ESI says whether a given character may use a given gate: there is no access-list
  endpoint, and a structure's own record is readable only by somebody already on its list. What is
  public is who holds sovereignty over a system, which this reads from the sovereignty map already
  kept for the map's colouring. So a bridge counts as a road only where both of its ends sit in
  sovereignty held by the pilot's own alliance.

  Both ends, rather than the one a jump starts from, because the route graph is undirected and a
  pair that is flyable one way only would otherwise be offered in both. In a real network that
  costs nothing - a bridge is built as a pair of gates inside one alliance's space - and it never
  offers a jump that cannot be flown.
  """

  @doc """
  Whether a pilot in `alliance_id` may fly a bridge between these two systems.

  Without an alliance there is nothing to check against, and a pilot in no alliance may fly no
  Ansiblex at all, so the answer is the same either way: no.
  """
  @spec usable?(integer() | nil, integer() | nil, integer() | nil) :: boolean()
  def usable?(_source, _target, nil), do: false

  def usable?(source, target, alliance_id)
      when is_integer(source) and is_integer(target) and is_integer(alliance_id) do
    holder(source) == alliance_id and holder(target) == alliance_id
  end

  def usable?(_source, _target, _alliance_id), do: false

  @doc """
  The alliance holding sovereignty over a system, or nil where nobody does.
  """
  @spec holder(integer() | nil) :: integer() | nil
  def holder(solar_system_id) do
    case WandererApp.Server.SovereigntyDataFetcher.get_sovereignty(solar_system_id) do
      %{alliance_id: alliance_id} when is_integer(alliance_id) -> alliance_id
      _ -> nil
    end
  end
end
