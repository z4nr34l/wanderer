defmodule WandererApp.Map.Bridges do
  @moduledoc """
  The jump bridges a map counts on, and reading a pasted list of them.

  People copy their bridge list out of the game or out of whatever tool holds it, so the parser
  takes the shapes that copying produces rather than asking for one: an arrow, a dash, a comma, a
  tab, and the Ansiblex name that carries the two systems with the structure name behind it.

  Bridges work in both directions, which is why a pair is stored once, smallest system id first.
  """

  require Logger

  alias WandererApp.Api.MapBridge

  # "UALX-3 » 1DQ1-A - Ansiblex Jump Gate", and everything else a copy ends up looking like
  # longest first: an arrow that starts with the same characters as a shorter one must win
  @separators ["<->", "<=>", "»", ">>", "->", "=>", "—", "–", " - ", "|", ",", ";", "\t"]

  @type pair :: %{source: String.t(), target: String.t()}

  @doc """
  Reads a pasted list into system-name pairs, keeping the lines it could not read.
  """
  @spec parse(String.t()) :: %{pairs: [pair()], unreadable: [String.t()]}
  def parse(text) when is_binary(text) do
    text
    |> String.split(~r/\r?\n/)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))
    |> Enum.reduce(%{pairs: [], unreadable: []}, fn line, acc ->
      case parse_line(line) do
        {:ok, pair} -> %{acc | pairs: acc.pairs ++ [pair]}
        :error -> %{acc | unreadable: acc.unreadable ++ [line]}
      end
    end)
  end

  def parse(_text), do: %{pairs: [], unreadable: []}

  @doc """
  Splits one line into the two system names it names.
  """
  @spec parse_line(String.t()) :: {:ok, pair()} | :error
  def parse_line(line) when is_binary(line) do
    line
    |> strip_noise()
    |> split_on_separator()
    |> case do
      [source, target] ->
        source = clean_name(source)
        target = clean_name(target)

        if source != "" and target != "" and source != target do
          {:ok, %{source: source, target: target}}
        else
          :error
        end

      _ ->
        :error
    end
  end

  def parse_line(_line), do: :error

  @doc """
  The bridges of a map, nearest thing first - the list the settings tab shows.
  """
  @spec list(String.t()) :: [map()]
  def list(map_id) do
    case MapBridge.by_map(%{map_id: map_id}) do
      {:ok, bridges} -> bridges
      _ -> []
    end
  end

  @doc """
  The bridge pairs a route may use, as the route builder wants them.

  A dangerous bridge is left out when the route settings say to avoid those; with bridges turned
  off nothing comes back at all.
  """
  @spec route_pairs(String.t(), map()) :: [%{first: integer(), second: integer()}]
  def route_pairs(map_id, routes_settings) do
    if Map.get(routes_settings, :include_bridges, true) do
      avoid_dangerous = Map.get(routes_settings, :avoid_dangerous_bridges, false)

      map_id
      |> list()
      |> Enum.reject(&(avoid_dangerous and &1.dangerous))
      |> Enum.map(&%{first: &1.solar_system_source, second: &1.solar_system_target})
    else
      []
    end
  end

  @doc """
  Stores a pasted list, and says what came of each line.

  A pair already stored keeps its place and takes the dangerous flag of this import, so pasting a
  corrected list over an old one is a way to fix it.
  """
  @spec import(String.t(), String.t(), keyword()) ::
          {:ok, %{imported: non_neg_integer(), unknown: [String.t()], unreadable: [String.t()]}}
  def import(map_id, text, opts \\ []) do
    dangerous = Keyword.get(opts, :dangerous, false)
    %{pairs: pairs, unreadable: unreadable} = parse(text)

    {imported, unknown} =
      Enum.reduce(pairs, {0, []}, fn pair, {imported, unknown} ->
        case resolve(pair) do
          {:ok, source_id, target_id} ->
            case store(map_id, source_id, target_id, dangerous) do
              :ok -> {imported + 1, unknown}
              :error -> {imported, unknown ++ ["#{pair.source} - #{pair.target}"]}
            end

          {:error, name} ->
            {imported, unknown ++ [name]}
        end
      end)

    {:ok, %{imported: imported, unknown: Enum.uniq(unknown), unreadable: unreadable}}
  end

  @doc """
  Forgets one bridge.
  """
  @spec delete(String.t()) :: :ok | :error
  def delete(bridge_id) do
    with {:ok, bridge} <- MapBridge.by_id(bridge_id),
         :ok <- MapBridge.destroy(bridge) do
      :ok
    else
      _ -> :error
    end
  end

  @doc """
  Marks a bridge dangerous, or stops doing so.
  """
  @spec set_dangerous(String.t(), boolean()) :: :ok | :error
  def set_dangerous(bridge_id, dangerous) do
    with {:ok, bridge} <- MapBridge.by_id(bridge_id),
         {:ok, _updated} <- MapBridge.update_dangerous(bridge, %{dangerous: dangerous}) do
      :ok
    else
      _ -> :error
    end
  end

  defp store(map_id, source_id, target_id, dangerous) do
    # one row per pair, whichever way round it was pasted
    {first, second} = {min(source_id, target_id), max(source_id, target_id)}

    case MapBridge.new(%{
           map_id: map_id,
           solar_system_source: first,
           solar_system_target: second,
           dangerous: dangerous
         }) do
      {:ok, _bridge} ->
        :ok

      {:error, reason} ->
        Logger.warning(fn ->
          "[Bridges] could not store #{first}-#{second}: #{inspect(reason)}"
        end)

        :error
    end
  end

  defp resolve(%{source: source, target: target}) do
    with {:ok, source_id} <- system_id(source),
         {:ok, target_id} <- system_id(target) do
      {:ok, source_id, target_id}
    else
      {:error, name} -> {:error, name}
    end
  end

  defp system_id(name) do
    wanted = String.downcase(name)

    case WandererApp.Api.MapSolarSystem.find_by_name(%{name: name}) do
      {:ok, systems} ->
        systems
        |> Enum.find(&(String.downcase(&1.solar_system_name) == wanted))
        |> case do
          nil -> {:error, name}
          system -> {:ok, system.solar_system_id}
        end

      _ ->
        {:error, name}
    end
  end

  # the structure name sits behind the two systems, and a copy often brings brackets with it
  defp strip_noise(line) do
    line
    |> String.replace(~r/\s*-\s*Ansiblex Jump Gate.*$/iu, "")
    |> String.replace(~r/\s*\(.*?\)\s*/u, " ")
    |> String.trim()
  end

  defp split_on_separator(line) do
    Enum.find_value(@separators, [line], fn separator ->
      case String.split(line, separator, parts: 2) do
        [_one] -> nil
        parts -> parts
      end
    end)
  end

  defp clean_name(name) do
    name
    |> String.trim()
    |> String.trim_leading("-")
    |> String.trim_trailing("-")
    |> String.trim()
  end
end
