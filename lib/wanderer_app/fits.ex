defmodule WandererApp.Fits do
  @moduledoc """
  What a ship weighs cold, and what it weighs with its prop mod running - the two numbers that
  matter when rolling a wormhole.

  Masses come from ESI rather than a table kept here, so the numbers follow the game. Everything
  the game counts is counted here too: plates and other flat additions, the mass a T3 cruiser's
  subsystems carry, and percentage modifiers such as a Higgs Anchor rig - which doubles the ship,
  prop mod included.
  """

  # dogma attribute carried by prop mods and plates - how much mass they add
  @mass_addition_attribute_id 796
  # dogma attribute carried by the Higgs Anchor rigs - a percentage change of the whole ship
  @mass_percentage_attribute_id 1131
  # the ship's own mass, which is what a T3 subsystem brings with it
  @mass_attribute_id 4

  @propulsion_module_group_id 46
  @subsystem_category_id 32

  @type mass_part :: %{
          name: String.t() | nil,
          addition: number(),
          percentage: number(),
          own_mass: number(),
          propulsion?: boolean()
        }

  @type fit_masses :: %{
          ship_name: String.t() | nil,
          prop_module: String.t() | nil,
          cold_mass: number(),
          hot_mass: number()
        }

  @doc """
  The same two numbers for a hull and a set of fitted type ids, which is what reading a live ship
  gives us - assets carry type ids rather than names.
  """
  @spec masses_from_type_ids(integer(), [integer()]) :: {:ok, fit_masses()} | {:error, term()}
  def masses_from_type_ids(hull_type_id, item_type_ids) when is_list(item_type_ids) do
    with {:ok, ship} <- WandererApp.Esi.get_type_info(hull_type_id, []),
         hull_mass when is_number(hull_mass) <- Map.get(ship, "mass") do
      parts = Enum.map(item_type_ids, &mass_part/1)

      {:ok,
       hull_mass
       |> compute_masses(parts)
       |> Map.put(:ship_name, Map.get(ship, "name"))}
    else
      nil -> {:error, :ship_mass_unknown}
      {:error, reason} -> {:error, reason}
      error -> {:error, error}
    end
  end

  @doc """
  Folds a hull mass and everything fitted to it into the cold and hot numbers.

  The game applies flat additions first and percentage modifiers after, so a Higgs Anchor doubles
  the prop mod's contribution as well as the hull's.
  """
  @spec compute_masses(number(), [mass_part()]) :: %{
          prop_module: String.t() | nil,
          cold_mass: number(),
          hot_mass: number()
        }
  def compute_masses(hull_mass, parts) do
    {props, rest} = Enum.split_with(parts, & &1.propulsion?)

    base =
      hull_mass +
        Enum.sum(Enum.map(rest, &(&1.addition + &1.own_mass)))

    multiplier =
      Enum.reduce(parts, 1.0, fn part, acc -> acc * (1 + part.percentage / 100) end)

    {prop_module, prop_addition} =
      props
      |> Enum.map(&{&1.name, &1.addition})
      |> Enum.max_by(fn {_name, addition} -> addition end, fn -> {nil, 0} end)

    %{
      prop_module: prop_module,
      cold_mass: round(base * multiplier),
      hot_mass: round((base + prop_addition) * multiplier)
    }
  end

  defp mass_part(type_id) do
    case WandererApp.Esi.get_type_info(type_id, []) do
      {:ok, %{} = info} ->
        attributes = attributes(info)
        group_id = Map.get(info, "group_id")

        %{
          name: Map.get(info, "name"),
          addition: Map.get(attributes, @mass_addition_attribute_id, 0),
          percentage: Map.get(attributes, @mass_percentage_attribute_id, 0),
          own_mass: subsystem_mass(group_id, attributes),
          propulsion?: group_id == @propulsion_module_group_id
        }

      _ ->
        %{name: nil, addition: 0, percentage: 0, own_mass: 0, propulsion?: false}
    end
  end

  defp attributes(%{"dogma_attributes" => attributes}) when is_list(attributes) do
    Map.new(attributes, fn %{"attribute_id" => id, "value" => value} -> {id, value} end)
  end

  defp attributes(_info), do: %{}

  # A T3 cruiser's hull mass does not include its subsystems - they each bring their own.
  defp subsystem_mass(group_id, attributes) do
    if subsystem?(group_id) do
      Map.get(attributes, @mass_attribute_id, 0)
    else
      0
    end
  end

  defp subsystem?(nil), do: false

  defp subsystem?(group_id) do
    case WandererApp.Esi.get_group_info(group_id, []) do
      {:ok, %{"category_id" => @subsystem_category_id}} -> true
      _ -> false
    end
  end
end
