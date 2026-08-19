defmodule WandererApp.Standings do
  @moduledoc """
  Turning ESI contact lists into alliance standings for the map.

  Standings can come from three places, and most people can only read one of them: a character
  always reads its own contacts, while the corporation and alliance lists need roles ESI enforces.
  Everything readable is merged, with the alliance overriding the corporation and the corporation
  overriding the character - the group's decision beats the personal one.
  """

  @source_order ["character", "corporation", "alliance"]

  @type source :: {String.t(), [map()]}

  @doc """
  Merges the contact lists that could be read into one standing per alliance.

  Only alliance contacts are kept: a standing towards a single character or corporation says
  nothing about who holds a system.
  """
  @spec merge([source()], (integer() -> {String.t(), String.t()} | nil)) :: [map()]
  def merge(read, resolve \\ &esi_alliance/1) do
    read
    |> Enum.sort_by(fn {source, _contacts} ->
      Enum.find_index(@source_order, &(&1 == source)) || 0
    end)
    |> Enum.flat_map(fn {_source, contacts} ->
      Enum.filter(contacts, &(&1["contact_type"] == "alliance"))
    end)
    |> Enum.reduce(%{}, fn contact, acc -> Map.put(acc, contact["contact_id"], contact) end)
    |> Map.values()
    |> Enum.map(&standing(&1, resolve))
    |> Enum.sort_by(& &1.standing)
  end

  @doc """
  Which lists actually answered, in the order they are applied.
  """
  @spec sources([source()]) :: [String.t()]
  def sources(read) do
    read
    |> Enum.map(&elem(&1, 0))
    |> Enum.uniq()
    |> Enum.sort_by(fn source -> Enum.find_index(@source_order, &(&1 == source)) || 0 end)
  end

  @doc """
  Adds the character's own alliance, which no contact list carries.

  Nobody sets a standing towards themselves, so without this a pilot sees their own space as
  neutral - the one alliance they are certain about.
  """
  @spec with_own_alliance([map()], String.t() | nil, String.t() | nil) :: [map()]
  def with_own_alliance(standings, ticker, name) when is_binary(ticker) and ticker != "" do
    own = %{alliance: ticker, name: name, standing: 10.0}

    others = Enum.reject(standings, &(String.downcase(&1.alliance) == String.downcase(ticker)))

    [own | others] |> Enum.sort_by(& &1.standing)
  end

  def with_own_alliance(standings, _ticker, _name), do: standings

  # the ticker is what shows on the map, so that is what an imported row matches on
  defp standing(%{"contact_id" => contact_id, "standing" => standing}, resolve) do
    case resolve.(contact_id) do
      {ticker, name} -> %{alliance: ticker, name: name, standing: standing}
      _ -> %{alliance: to_string(contact_id), name: nil, standing: standing}
    end
  end

  defp esi_alliance(alliance_id) do
    case WandererApp.Esi.get_alliance_info(alliance_id) do
      {:ok, %{"ticker" => ticker, "name" => name}} -> {ticker, name}
      _ -> nil
    end
  end
end
