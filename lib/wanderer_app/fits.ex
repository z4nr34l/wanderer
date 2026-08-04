defmodule WandererApp.Fits do
  @moduledoc """
  Turns a fit pasted from the game or Pyfa into the two numbers that matter when rolling a
  wormhole: what the ship weighs cold, and what it weighs with its prop mod running.

  Masses come from ESI rather than a table kept here, so the numbers follow the game.
  """

  require Logger

  # dogma attribute carried by prop mods - how much mass they add while running
  @mass_addition_attribute_id 796

  @type fit_masses :: %{
          ship_name: String.t(),
          prop_module: String.t() | nil,
          cold_mass: number(),
          hot_mass: number()
        }

  @doc """
  Reads an EFT block and works out the ship's cold and hot mass.
  """
  @spec masses_from_eft(String.t()) :: {:ok, fit_masses()} | {:error, term()}
  def masses_from_eft(text) when is_binary(text) do
    with {:ok, %{ship_name: ship_name, items: items}} <- parse_eft(text),
         {:ok, ids} <- resolve_type_ids([ship_name | items]),
         {:ok, ship_type_id} <- fetch_id(ids, ship_name),
         {:ok, ship} <- WandererApp.Esi.get_type_info(ship_type_id, []),
         cold_mass when is_number(cold_mass) <- Map.get(ship, "mass") do
      {prop_module, mass_addition} = heaviest_prop_module(items, ids)

      {:ok,
       %{
         ship_name: ship_name,
         prop_module: prop_module,
         cold_mass: cold_mass,
         hot_mass: cold_mass + mass_addition
       }}
    else
      nil -> {:error, :ship_mass_unknown}
      {:error, reason} -> {:error, reason}
      error -> {:error, error}
    end
  end

  def masses_from_eft(_text), do: {:error, :invalid_fit}

  @doc """
  Pulls the hull name and the fitted items out of an EFT block.

  The first line is `[Hull, Fit name]`; the rest are module names, optionally followed by a
  charge after a comma and a quantity after an `x`. Empty lines separate the slot sections.
  """
  @spec parse_eft(String.t()) :: {:ok, %{ship_name: String.t(), items: [String.t()]}} | {:error, term()}
  def parse_eft(text) when is_binary(text) do
    lines =
      text
      |> String.split(~r/\r?\n/)
      |> Enum.map(&String.trim/1)

    case lines do
      ["[" <> header | rest] ->
        ship_name =
          header
          |> String.trim_trailing("]")
          |> String.split(",")
          |> List.first()
          |> to_string()
          |> String.trim()

        if ship_name == "" do
          {:error, :ship_not_found}
        else
          {:ok, %{ship_name: ship_name, items: parse_items(rest)}}
        end

      _ ->
        {:error, :ship_not_found}
    end
  end

  def parse_eft(_text), do: {:error, :invalid_fit}

  defp parse_items(lines) do
    lines
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&item_name/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp item_name(line) do
    line
    # drop a trailing quantity, e.g. "Nanite Repair Paste x50"
    |> String.replace(~r/\s+x\d+$/, "")
    # drop a loaded charge, e.g. "Heavy Missile Launcher II, Scourge Fury"
    |> String.split(",")
    |> List.first()
    |> to_string()
    |> String.trim()
    # empty slots are written like "[Empty High slot]"
    |> case do
      "[" <> _ -> ""
      name -> name
    end
  end

  defp resolve_type_ids([]), do: {:ok, %{}}

  defp resolve_type_ids(names) do
    case WandererApp.Esi.post_universe_ids(names) do
      {:ok, %{"inventory_types" => types}} ->
        {:ok, Map.new(types, fn %{"name" => name, "id" => id} -> {name, id} end)}

      {:ok, _} ->
        {:error, :types_not_found}

      {:error, reason} ->
        Logger.warning("[Fits] could not resolve type ids: #{inspect(reason)}")
        {:error, :types_not_found}
    end
  end

  defp fetch_id(ids, name) do
    case Map.get(ids, name) do
      nil -> {:error, :ship_not_found}
      id -> {:ok, id}
    end
  end

  # A fit can hold more than one thing that adds mass; rolling uses the prop mod, which is the
  # heaviest of them.
  defp heaviest_prop_module(items, ids) do
    items
    |> Enum.map(fn name -> {name, Map.get(ids, name)} end)
    |> Enum.reject(fn {_name, id} -> is_nil(id) end)
    |> Enum.map(fn {name, id} -> {name, mass_addition(id)} end)
    |> Enum.filter(fn {_name, addition} -> addition > 0 end)
    |> Enum.max_by(fn {_name, addition} -> addition end, fn -> {nil, 0} end)
  end

  defp mass_addition(type_id) do
    case WandererApp.Esi.get_type_info(type_id, []) do
      {:ok, %{"dogma_attributes" => attributes}} when is_list(attributes) ->
        attributes
        |> Enum.find(fn %{"attribute_id" => id} -> id == @mass_addition_attribute_id end)
        |> case do
          %{"value" => value} when is_number(value) -> value
          _ -> 0
        end

      _ ->
        0
    end
  end
end
