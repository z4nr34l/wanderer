defmodule WandererApp.Character.ShipFit do
  @moduledoc """
  The mass of the ship a character is flying right now, read from EVE.

  A fitted module is an asset like any other: it sits at the ship's item id with a slot for its
  location flag. Reading those gives the real fit - rigs, plates, subsystems and prop mod - so
  rolling does not depend on anyone keeping a pasted fit up to date.

  Two things to know about the numbers. ESI caches a character's assets for an hour, so a refit
  during that hour still reads as the old ship. And the scope is optional: without
  `esi-assets.read_assets.v1` ESI answers 403 and the caller falls back to a saved fit.
  """

  require Logger

  # a slot rather than a hold - what is bolted to the hull
  @fitted_slot ~r/^(HiSlot|MedSlot|LoSlot|RigSlot|SubSystemSlot)\d+$/

  @page_size 1000
  # a wealthy character has a lot of assets; this is where we stop looking rather than walk
  # someone's whole hangar list
  @max_pages 20

  @ttl :timer.minutes(10)
  @miss_ttl :timer.minutes(1)

  @type fit :: %{
          ship_type_id: integer(),
          ship_name: String.t() | nil,
          prop_module: String.t() | nil,
          cold_mass: number(),
          hot_mass: number()
        }

  @assets_scope "esi-assets.read_assets.v1"

  @doc """
  Whether this instance asks EVE for asset access at all. Without it there is no fit to read, and
  telling someone to reconnect would not help them.
  """
  @spec enabled?() :: boolean()
  def enabled?, do: @assets_scope in WandererApp.Character.Scopes.required()

  @doc """
  The cold and hot mass of the character's current ship, or an error saying why not.
  """
  @spec for_character(map()) :: {:ok, fit()} | {:error, term()}
  def for_character(%{ship: ship_type_id, ship_item_id: ship_item_id} = character)
      when not is_nil(ship_type_id) and not is_nil(ship_item_id) do
    key = "character:#{character.id}:ship_fit:#{ship_item_id}"

    case WandererApp.Cache.lookup(key) do
      {:ok, cached} when not is_nil(cached) ->
        cached

      _ ->
        result = read(character)
        ttl = if match?({:ok, _}, result), do: @ttl, else: @miss_ttl

        WandererApp.Cache.insert(key, result, ttl: ttl)
        result
    end
  end

  def for_character(_character), do: {:error, :no_ship}

  defp read(%{ship: ship_type_id, ship_item_id: ship_item_id} = character) do
    case read_fitted_type_ids(character, ship_item_id) do
      {:ok, type_ids} ->
        case WandererApp.Fits.masses_from_type_ids(ship_type_id, type_ids) do
          {:ok, masses} -> {:ok, Map.put(masses, :ship_type_id, ship_type_id)}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  The type ids of everything fitted to the given ship, picked out of a character's assets.

  Anything in a hold rides along without changing the ship's mass, so only slots count.
  """
  @spec fitted_type_ids([map()], integer()) :: [integer()]
  def fitted_type_ids(assets, ship_item_id) when is_list(assets) do
    assets
    |> Enum.filter(&fitted_to?(&1, ship_item_id))
    |> Enum.map(&Map.get(&1, "type_id"))
    |> Enum.reject(&is_nil/1)
  end

  defp read_fitted_type_ids(character, ship_item_id) do
    opts = [access_token: character.access_token, character_id: character.id]

    case read_pages(character.eve_id, opts, 1, []) do
      {:ok, assets} -> {:ok, fitted_type_ids(assets, ship_item_id)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp read_pages(_eve_id, _opts, page, acc) when page > @max_pages do
    Logger.debug(fn -> "[ShipFit] stopped reading assets after #{@max_pages} pages" end)
    {:ok, acc}
  end

  defp read_pages(eve_id, opts, page, acc) do
    case WandererApp.Esi.get_character_assets(eve_id, Keyword.put(opts, :page, page)) do
      {:ok, assets} when is_list(assets) and length(assets) == @page_size ->
        read_pages(eve_id, opts, page + 1, acc ++ assets)

      {:ok, assets} when is_list(assets) ->
        {:ok, acc ++ assets}

      {:error, :forbidden} ->
        {:error, :no_scope}

      {:error, reason} ->
        {:error, reason}

      _ ->
        {:error, :assets_unavailable}
    end
  end

  defp fitted_to?(%{"location_id" => location_id, "location_flag" => flag}, ship_item_id),
    do: location_id == ship_item_id and Regex.match?(@fitted_slot, flag)

  defp fitted_to?(_asset, _ship_item_id), do: false
end
