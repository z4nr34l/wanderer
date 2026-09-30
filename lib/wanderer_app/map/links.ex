defmodule WandererApp.Map.Links do
  @moduledoc """
  The maps linked to this one, and where the two of them overlap.

  Chains meet more often than at a home system. When a system somebody scans into is already on
  another map - the group next door, an ally on another instance - the useful thing on offer is
  that map itself, so the two chains can be read as one.

  What may be offered depends on how the other map got here:

  - a map on this instance the person may already open is offered whole, because they could open
    it themselves anyway;
  - a map reached by token is offered whole only when its owner has said so. Until then a token
    buys the way into the home and nothing else, which is what it has always bought.
  """

  require Logger

  alias WandererAppWeb.MapEventHandler

  @type link :: %{
          link_id: String.t(),
          map_id: String.t() | nil,
          share_id: String.t() | nil,
          map_name: String.t(),
          map_slug: String.t() | nil,
          remote?: boolean()
        }

  @doc """
  The linked maps that can be read whole, and which of this map's systems each one also has.

  `overlaps` is keyed by solar system id so the client can ask "is this system on somebody else's
  map?" without a round trip for every system it draws.
  """
  @spec known(map() | nil, String.t()) :: %{
          links: [link()],
          overlaps: %{String.t() => [String.t()]}
        }
  def known(current_user, map_id) when is_binary(map_id) do
    links = readable(current_user, map_id) ++ shared(map_id)
    ours = solar_system_ids(map_id)

    overlaps =
      links
      |> Enum.reduce(%{}, fn {link, their_ids}, acc ->
        ours
        |> MapSet.intersection(their_ids)
        |> Enum.reduce(acc, fn solar_system_id, acc ->
          Map.update(acc, to_string(solar_system_id), [link.link_id], &[link.link_id | &1])
        end)
      end)

    %{links: Enum.map(links, &elem(&1, 0)), overlaps: overlaps}
  end

  def known(_current_user, _map_id), do: %{links: [], overlaps: %{}}

  @doc """
  A linked map, in the shape the map itself is drawn from.
  """
  @spec preview(map() | nil, String.t(), String.t()) :: {:ok, map()} | {:error, atom()}
  def preview(current_user, map_id, "map:" <> linked_map_id) do
    if Enum.any?(readable(current_user, map_id), fn {link, _ids} ->
         link.map_id == linked_map_id
       end) do
      {:ok, whole(linked_map_id)}
    else
      {:error, :no_such_map}
    end
  end

  def preview(_current_user, map_id, "share:" <> share_id) do
    # the share has to be one this map was given, and the far side has to be sharing itself whole
    if Enum.any?(WandererApp.Map.HomeShares.list(map_id), &(&1.id == share_id)) do
      case WandererApp.Map.HomeShares.payload(share_id) do
        {:ok, %{"map" => %{"systems" => _} = whole}} -> {:ok, whole}
        {:ok, _payload} -> {:error, :not_shared}
        error -> error
      end
    else
      {:error, :no_such_map}
    end
  end

  def preview(_current_user, _map_id, _link_id), do: {:error, :no_such_map}

  @doc """
  Everything a map holds, in the shape the map itself is drawn from.
  """
  @spec whole(String.t()) :: %{String.t() => list()}
  def whole(map_id) do
    with {:ok, systems} <- WandererApp.MapSystemRepo.get_visible_by_map(map_id),
         {:ok, connections} <- WandererApp.MapConnectionRepo.get_by_map(map_id) do
      %{
        "systems" => Enum.map(systems, &MapEventHandler.map_ui_system/1),
        "connections" => Enum.map(connections, &MapEventHandler.map_ui_connection/1)
      }
    else
      _ -> %{"systems" => [], "connections" => []}
    end
  end

  # maps on this instance the person may already open
  defp readable(nil, _map_id), do: []

  defp readable(current_user, map_id) do
    case WandererApp.Maps.get_available_maps(current_user) do
      {:ok, maps} ->
        maps
        |> Enum.reject(&(&1.id == map_id))
        |> Enum.map(fn map ->
          {%{
             link_id: "map:" <> map.id,
             map_id: map.id,
             share_id: nil,
             map_name: map.name,
             map_slug: map.slug,
             remote?: false
           }, solar_system_ids(map.id)}
        end)

      _ ->
        []
    end
  end

  # maps reached by token, and only the ones whose owner shares them whole
  defp shared(map_id) do
    map_id
    |> WandererApp.Map.HomeShares.list()
    |> Enum.flat_map(fn share ->
      case WandererApp.Map.HomeShares.payload(share.id) do
        {:ok, %{"map" => %{"systems" => systems}}} when is_list(systems) ->
          [
            {%{
               link_id: "share:" <> share.id,
               map_id: nil,
               share_id: share.id,
               map_name: share.label,
               map_slug: share.slug,
               remote?: share.remote?
             }, MapSet.new(systems, &to_solar_system_id(&1["id"]))}
          ]

        _ ->
          []
      end
    end)
  end

  defp solar_system_ids(map_id) do
    case WandererApp.MapSystemRepo.get_visible_by_map(map_id) do
      {:ok, systems} -> MapSet.new(systems, & &1.solar_system_id)
      _ -> MapSet.new()
    end
  end

  defp to_solar_system_id(value) when is_integer(value), do: value

  defp to_solar_system_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, _rest} -> id
      :error -> nil
    end
  end

  defp to_solar_system_id(_value), do: nil
end
