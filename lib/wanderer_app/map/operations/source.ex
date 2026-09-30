defmodule WandererApp.Map.Operations.Source do
  @moduledoc """
  Reads another map's export document straight from the map it belongs to.

  `WandererApp.Map.Operations.Transfer` can already replay a document into a map; the only thing
  standing between two maps was the file somebody had to carry between them. A map hands its
  contents out over `GET /api/maps/:slug/export` against its own API key, so with that key a map
  can be read directly - from another deployment, or from a map next door on this one.

  What comes back is the same document a download would have produced, and it is replayed by the
  same code, so nothing here needs to know what a version 1 document looked like.
  """

  require Logger

  @timeout :timer.seconds(30)

  @type source :: %{base_url: binary(), slug: binary(), token: binary()}

  @doc """
  Fetches the export document of the map named by `slug`.

  An empty `base_url` means a map on this instance, which is read without going over the network.
  """
  @spec fetch(source()) :: {:ok, map()} | {:error, atom()}
  def fetch(%{slug: slug, token: token} = source)
      when is_binary(slug) and is_binary(token) and slug != "" and token != "" do
    case normalise_base_url(Map.get(source, :base_url)) do
      {:ok, ""} -> read_local(slug, token)
      {:ok, base_url} -> read_remote(base_url, slug, token)
      error -> error
    end
  end

  def fetch(_source), do: {:error, :invalid}

  @doc """
  Turns a failure from `fetch/1` into something worth showing somebody.
  """
  @spec message(atom()) :: binary()
  def message(:forbidden), do: "That key is not the one that map answers to."
  def message(:no_such_map), do: "No map with that slug over there."
  def message(:unreachable), do: "Could not reach that instance."
  def message(:unreadable), do: "That instance answered with something that is not a map."
  def message(:invalid), do: "A slug and an API key are needed."
  def message(_reason), do: "Could not read that map."

  # A map on this instance is read through the same key its API would have checked, so sharing a
  # map with somebody next door costs them no more than sharing it across the wire would.
  defp read_local(slug, token) do
    case WandererApp.Api.Map.get_map_by_slug(slug) do
      {:ok, %{public_api_key: key, id: map_id}} when is_binary(key) and key != "" ->
        if Plug.Crypto.secure_compare(key, token) do
          WandererApp.Map.Operations.Transfer.export(map_id)
        else
          {:error, :forbidden}
        end

      {:ok, _map} ->
        {:error, :forbidden}

      _ ->
        {:error, :no_such_map}
    end
  end

  defp read_remote(base_url, slug, token) do
    url = "#{base_url}/api/maps/#{URI.encode(slug)}/export"

    case Req.get(url,
           headers: [{"authorization", "Bearer #{token}"}],
           retry: false,
           receive_timeout: @timeout
         ) do
      {:ok, %{status: 200, body: %{"data" => %{"version" => _} = document}}} ->
        {:ok, document}

      {:ok, %{status: 200, body: %{"version" => _} = document}} ->
        {:ok, document}

      {:ok, %{status: 200}} ->
        {:error, :unreadable}

      {:ok, %{status: status}} when status in [401, 403] ->
        {:error, :forbidden}

      {:ok, %{status: 404}} ->
        {:error, :no_such_map}

      {:ok, %{status: status}} ->
        Logger.warning(fn -> "[Source] #{url} answered #{status}" end)
        {:error, :unreadable}

      {:error, reason} ->
        Logger.warning(fn -> "[Source] could not reach #{url}: #{inspect(reason)}" end)
        {:error, :unreachable}
    end
  end

  # somebody pasting an address types what is on their screen, which is a whole URL as often as
  # it is a host
  defp normalise_base_url(nil), do: {:ok, ""}
  defp normalise_base_url(""), do: {:ok, ""}

  defp normalise_base_url(base_url) when is_binary(base_url) do
    trimmed = base_url |> String.trim() |> String.trim_trailing("/")

    cond do
      trimmed == "" ->
        {:ok, ""}

      String.starts_with?(trimmed, ["http://", "https://"]) ->
        {:ok, trimmed}

      String.contains?(trimmed, "://") ->
        {:error, :invalid}

      true ->
        {:ok, "https://" <> trimmed}
    end
  end

  defp normalise_base_url(_base_url), do: {:error, :invalid}
end
