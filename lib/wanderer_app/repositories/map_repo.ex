defmodule WandererApp.MapRepo do
  use WandererApp, :repository

  require Logger

  @default_map_options %{
    "layout" => "left_to_right",
    "store_custom_labels" => "false",
    "show_linked_signature_id" => "false",
    "show_linked_signature_id_temp_name" => "false",
    "show_temp_system_name" => "false",
    "restrict_offline_showing" => "false",
    "allowed_copy_for" => "admin_map",
    "allowed_paste_for" => "add_system"
  }

  @default_system_labels [
    %{"id" => "a", "name" => "A", "color" => "#2d803b"},
    %{"id" => "b", "name" => "B", "color" => "#3d94af"},
    %{"id" => "c", "name" => "C", "color" => "#3d94af"},
    %{"id" => "1", "name" => "1", "color" => "#563daf"},
    %{"id" => "2", "name" => "2", "color" => "#8f3daf"},
    %{"id" => "3", "name" => "3", "color" => "#3d65af"}
  ]

  def get(map_id, relationships \\ []) do
    map_id
    |> WandererApp.Api.Map.by_id()
    |> case do
      {:ok, map} ->
        map |> load_relationships(relationships)

      _ ->
        {:error, :not_found}
    end
  end

  def get_by_slug_with_permissions(map_slug, current_user) do
    map_slug
    |> WandererApp.Api.Map.get_map_by_slug!()
    |> Ash.load(
      acls: [
        :owner_id,
        members: [:role, :eve_character_id, :eve_corporation_id, :eve_alliance_id]
      ]
    )
    |> case do
      {:ok, map_with_acls} -> Ash.load(map_with_acls, :user_permissions, actor: current_user)
      error -> error
    end
  end

  @doc """
  Safely retrieves a map by slug, handling the case where multiple maps
  with the same slug exist (database integrity issue).

  When duplicates are detected, automatically triggers recovery to fix them
  and retries the query once.

  Returns:
  - `{:ok, map}` - Single map found
  - `{:error, :multiple_results}` - Multiple maps found (after recovery attempt)
  - `{:error, :not_found}` - No map found
  - `{:error, reason}` - Other error
  """
  def get_map_by_slug_safely(slug, retry_count \\ 0) do
    try do
      map = WandererApp.Api.Map.get_map_by_slug!(slug)
      {:ok, map}
    rescue
      error in Ash.Error.Invalid.MultipleResults ->
        handle_multiple_results(slug, error, retry_count)

      error in Ash.Error.Invalid ->
        # Check if this Invalid error contains a MultipleResults error
        case find_multiple_results_error(error) do
          {:ok, multiple_results_error} ->
            handle_multiple_results(slug, multiple_results_error, retry_count)

          :error ->
            # Check if this is a no results error
            if is_no_results_error?(error) do
              Logger.debug("Map not found with slug: #{slug}")
              {:error, :not_found}
            else
              # Some other Invalid error
              Logger.error("Error retrieving map by slug",
                slug: slug,
                error: inspect(error)
              )

              {:error, :unknown_error}
            end
        end

      _error in Ash.Error.Query.NotFound ->
        Logger.debug("Map not found with slug: #{slug}")
        {:error, :not_found}

      error ->
        Logger.error("Error retrieving map by slug",
          slug: slug,
          error: inspect(error)
        )

        {:error, :unknown_error}
    end
  end

  # Helper function to handle multiple results errors with automatic recovery
  defp handle_multiple_results(slug, error, retry_count) do
    count = Map.get(error, :count, 2)

    Logger.error("Multiple maps found with slug '#{slug}' - triggering automatic recovery",
      slug: slug,
      count: count,
      retry_count: retry_count,
      error: inspect(error)
    )

    # Emit telemetry for monitoring
    :telemetry.execute(
      [:wanderer_app, :map, :duplicate_slug_detected],
      %{count: count, retry_count: retry_count},
      %{slug: slug, operation: :get_by_slug}
    )

    # Attempt automatic recovery if this is the first try
    if retry_count == 0 do
      case WandererApp.Map.SlugRecovery.recover_duplicate_slug(slug) do
        {:ok, recovery_result} ->
          Logger.info("Successfully recovered duplicate slug '#{slug}', retrying query",
            slug: slug,
            fixed_count: recovery_result.fixed_count
          )

          # Retry the query once after recovery
          get_map_by_slug_safely(slug, retry_count + 1)

        {:error, reason} ->
          Logger.error("Failed to recover duplicate slug '#{slug}'",
            slug: slug,
            error: inspect(reason)
          )

          {:error, :multiple_results}
      end
    else
      # Already retried once, give up
      Logger.error(
        "Multiple maps still found with slug '#{slug}' after recovery attempt",
        slug: slug,
        count: count
      )

      {:error, :multiple_results}
    end
  end

  # Helper function to check if an Ash.Error.Invalid contains a MultipleResults error
  defp find_multiple_results_error(%Ash.Error.Invalid{errors: errors}) do
    errors
    |> Enum.find_value(:error, fn
      %Ash.Error.Invalid.MultipleResults{} = mr_error -> {:ok, mr_error}
      _ -> false
    end)
  end

  # Helper function to check if an error indicates no results were found
  defp is_no_results_error?(%Ash.Error.Invalid{errors: errors}) do
    # If errors list is empty, it's likely a no results error
    Enum.empty?(errors)
  end

  defp is_no_results_error?(_), do: false

  def load_relationships(map, []), do: {:ok, map}

  def load_relationships(map, relationships), do: map |> Ash.load(relationships)

  def update_hubs(map_id, hubs) do
    map_id
    |> WandererApp.Api.Map.by_id()
    |> case do
      {:ok, map} ->
        map |> WandererApp.Api.Map.update_hubs(%{hubs: hubs})

      _ ->
        {:error, :map_not_found}
    end
  end

  def get_system_labels(map_id) do
    case get(map_id) do
      {:ok, map} -> {:ok, system_labels_to_form_data(map)}
      error -> error
    end
  end

  def update_system_labels(map_id, labels) do
    with {:ok, normalized_labels} <- normalize_system_labels(labels),
         {:ok, map} <- get(map_id),
         {:ok, updated_map} <-
           WandererApp.Api.Map.update_system_labels(map, %{
             system_labels: Jason.encode!(normalized_labels)
           }) do
      {:ok, updated_map, normalized_labels}
    end
  end

  def system_labels_to_form_data(%{system_labels: labels}) when is_binary(labels) do
    case Jason.decode(labels) do
      {:ok, decoded} ->
        case normalize_system_labels(decoded) do
          {:ok, normalized} -> normalized
          _ -> @default_system_labels
        end

      _ ->
        @default_system_labels
    end
  end

  def system_labels_to_form_data(_), do: @default_system_labels

  def default_system_labels, do: @default_system_labels

  def normalize_system_labels(labels) when is_list(labels) and labels != [] and length(labels) <= 64 do
    with {:ok, normalized} <- normalize_label_entries(labels),
         true <- unique_label_ids?(normalized) do
      {:ok, normalized}
    else
      _ -> {:error, :invalid_system_labels}
    end
  end

  def normalize_system_labels(_), do: {:error, :invalid_system_labels}

  defp normalize_label_entries(labels) do
    Enum.reduce_while(labels, {:ok, []}, fn label, {:ok, acc} ->
      case normalize_label(label) do
        {:ok, normalized} -> {:cont, {:ok, [normalized | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, normalized} -> {:ok, Enum.reverse(normalized)}
      error -> error
    end
  end

  defp normalize_label(%{"id" => id, "name" => name, "color" => color})
       when is_binary(id) and is_binary(name) and is_binary(color) do
    id = String.trim(id)
    name = String.trim(name)

    if id != "" and name != "" and String.length(id) <= 32 and String.length(name) <= 64 and
         Regex.match?(~r/^#[0-9a-fA-F]{6}$/, color) do
      {:ok, %{"id" => id, "name" => name, "color" => String.downcase(color)}}
    else
      {:error, :invalid_system_labels}
    end
  end

  defp normalize_label(_), do: {:error, :invalid_system_labels}

  defp unique_label_ids?(labels) do
    ids = Enum.map(labels, & &1["id"])
    length(ids) == length(Enum.uniq(ids))
  end

  def update_options(map, options),
    do:
      map
      |> WandererApp.Api.Map.update_options(%{options: Jason.encode!(options)})

  def options_to_form_data(%{options: options} = _map_options) when not is_nil(options),
    do: {:ok, @default_map_options |> Map.merge(Jason.decode!(options))}

  def options_to_form_data(_), do: {:ok, @default_map_options}

  def options_to_form_data!(options) do
    {:ok, data} = options_to_form_data(options)
    data
  end
end
