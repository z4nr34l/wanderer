defmodule WandererApp.Map.Operations.Transfer do
  @moduledoc """
  Export and import of map contents as a portable document.

  Unlike `WandererApp.Map.Operations.Duplication`, which copies a map inside one instance by
  writing records directly, transfer produces a plain data structure that can be stored in a file
  and replayed into any map - including on another deployment. Imports go through the map server
  so that connected clients see the systems appear as they are added.

  Only map contents are transferred: systems, connections and (optionally) signatures. Access
  lists, subscriptions and per user settings are deliberately left out - they reference accounts
  and characters that do not exist on the importing side.

  Systems that are no longer on the map travel too. Taking a system off a map only hides it, and
  what somebody wrote about it - the notes, the tags, the signatures - is often the most valuable
  part of a chain's history. Those arrive on the far side hidden as well, so an import never puts
  a system back on the map that nobody asked for.
  """

  require Logger

  alias WandererApp.Api.MapSystemComment
  alias WandererApp.Api.MapSystemSignature
  alias WandererApp.Api.MapSystemStructure
  alias WandererApp.Map.Server

  @export_version 2

  # Version 1 knew nothing about hidden systems; everything it carries was on the map.
  @supported_versions [1, 2]

  @type stats :: %{
          systems: non_neg_integer(),
          hidden_systems: non_neg_integer(),
          connections: non_neg_integer(),
          signatures: non_neg_integer(),
          comments: non_neg_integer(),
          structures: non_neg_integer()
        }

  @doc """
  Builds the export document for a map.

  Options:
  - `:include_signatures` - include system signatures (default: true)
  """
  @spec export(binary(), keyword()) :: {:ok, map()} | {:error, term()}
  def export(map_id, opts \\ []) do
    include_signatures = Keyword.get(opts, :include_signatures, true)

    with {:ok, map} <- WandererApp.MapRepo.get(map_id),
         {:ok, systems} <- WandererApp.MapSystemRepo.get_all_by_map(map_id),
         {:ok, connections} <- WandererApp.MapConnectionRepo.get_by_map(map_id) do
      {:ok,
       %{
         "version" => @export_version,
         "exported_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
         "map" => %{
           "name" => map.name,
           "slug" => map.slug,
           "description" => map.description,
           # what the label ids on the systems mean; without these an imported map shows them
           # as raw grey ids
           "system_labels" => WandererApp.MapRepo.system_labels_to_form_data(map)
         },
         "systems" => Enum.map(systems, &export_system/1),
         "connections" => Enum.map(connections, &export_connection/1),
         "signatures" => export_signatures(systems, include_signatures),
         "comments" => export_comments(systems),
         "structures" => export_structures(systems)
       }}
    end
  end

  @doc """
  Replays an export document into an existing map.

  Systems already present on the target map keep their position and attributes - an import adds
  what is missing instead of overwriting the map, so it is safe to run against a live chain.

  Options:
  - `:include_signatures` - import system signatures (default: true)
  """
  @spec import(binary(), map(), binary(), binary() | nil, keyword()) ::
          {:ok, stats()} | {:error, term()}
  def import(map_id, data, user_id, character_id, opts \\ [])

  def import(map_id, %{"version" => version} = data, user_id, character_id, opts)
      when version in @supported_versions do
    include_signatures = Keyword.get(opts, :include_signatures, true)

    systems = Map.get(data, "systems", [])
    connections = Map.get(data, "connections", [])
    signatures = if include_signatures, do: Map.get(data, "signatures", []), else: []

    present = present_solar_system_ids(map_id)

    counts =
      systems
      |> Enum.filter(&is_map/1)
      |> Enum.map(&import_system(map_id, &1, user_id, character_id, present))
      |> Enum.frequencies()

    imported_systems = Map.get(counts, :added, 0)
    imported_hidden = Map.get(counts, :added_hidden, 0)

    imported_connections = import_connections(map_id, connections, user_id, character_id)
    imported_signatures = import_signatures(map_id, signatures, character_id)
    imported_comments = import_comments(map_id, Map.get(data, "comments", []), character_id)
    imported_structures = import_structures(map_id, Map.get(data, "structures", []), character_id)
    merge_system_labels(map_id, get_in(data, ["map", "system_labels"]))

    Logger.info(
      "Imported #{imported_systems} systems, #{imported_hidden} off-map systems, " <>
        "#{imported_connections} connections, #{imported_signatures} signatures into map #{map_id}"
    )

    {:ok,
     %{
       systems: imported_systems,
       hidden_systems: imported_hidden,
       connections: imported_connections,
       signatures: imported_signatures,
       comments: imported_comments,
       structures: imported_structures
     }}
  end

  def import(_map_id, %{"version" => version}, _user_id, _character_id, _opts),
    do: {:error, {:unsupported_version, version}}

  def import(_map_id, _data, _user_id, _character_id, _opts), do: {:error, :invalid_document}

  # -- export helpers ------------------------------------------------------------------------

  defp export_system(system) do
    %{
      "solar_system_id" => system.solar_system_id,
      "position" => %{"x" => system.position_x, "y" => system.position_y},
      "name" => system.name,
      "custom_name" => system.custom_name,
      "description" => system.description,
      "labels" => system.labels,
      "status" => system.status,
      "tag" => system.tag,
      "temporary_name" => system.temporary_name,
      "locked" => system.locked,
      "linked_sig_eve_id" => system.linked_sig_eve_id,
      "visible" => system.visible
    }
  end

  defp export_connection(connection) do
    %{
      "source" => connection.solar_system_source,
      "target" => connection.solar_system_target,
      "type" => connection.type,
      "mass_status" => connection.mass_status,
      "time_status" => connection.time_status,
      "ship_size_type" => connection.ship_size_type,
      "wormhole_type" => connection.wormhole_type,
      "locked" => connection.locked,
      "dangerous" => connection.dangerous,
      "bubbled" => connection.bubbled,
      "custom_info" => connection.custom_info
    }
  end

  defp export_signatures(_systems, false), do: []

  defp export_signatures(systems, true) do
    solar_system_ids = Map.new(systems, &{&1.id, &1.solar_system_id})

    case MapSystemSignature.by_system_ids(Map.keys(solar_system_ids)) do
      {:ok, signatures} ->
        signatures
        |> Enum.reject(& &1.deleted)
        |> Enum.map(&export_signature(&1, Map.fetch!(solar_system_ids, &1.system_id)))

      {:error, _} ->
        []
    end
  end

  defp export_signature(signature, solar_system_id) do
    %{
      "solar_system_id" => solar_system_id,
      "eve_id" => signature.eve_id,
      "name" => signature.name,
      "temporary_name" => signature.temporary_name,
      "description" => signature.description,
      "kind" => signature.kind,
      "group" => signature.group,
      "type" => signature.type,
      "custom_info" => signature.custom_info,
      "linked_system_id" => signature.linked_system_id
    }
  end

  # Comments and structures are where a chain's intel really lives - what somebody saw in a
  # system, whose POS is where, when a timer runs out. Both are keyed by system, so they follow
  # whichever systems the document carries.
  defp export_comments(systems) do
    solar_system_ids = Map.new(systems, &{&1.id, &1.solar_system_id})

    case MapSystemComment.by_system_ids(Map.keys(solar_system_ids)) do
      {:ok, comments} ->
        Enum.map(comments, fn comment ->
          %{
            "solar_system_id" => Map.fetch!(solar_system_ids, comment.system_id),
            "text" => comment.text
          }
        end)

      {:error, _} ->
        []
    end
  end

  defp export_structures(systems) do
    solar_system_ids = Map.new(systems, &{&1.id, &1.solar_system_id})

    case MapSystemStructure.by_system_ids(Map.keys(solar_system_ids)) do
      {:ok, structures} ->
        Enum.map(structures, fn structure ->
          %{
            "solar_system_id" => Map.fetch!(solar_system_ids, structure.system_id),
            "solar_system_name" => structure.solar_system_name,
            "structure_type_id" => structure.structure_type_id,
            "structure_type" => structure.structure_type,
            "name" => structure.name,
            "notes" => structure.notes,
            "owner_name" => structure.owner_name,
            "owner_ticker" => structure.owner_ticker,
            "owner_id" => structure.owner_id,
            "status" => structure.status,
            "end_time" => structure.end_time
          }
        end)

      {:error, _} ->
        []
    end
  end

  # -- import helpers ------------------------------------------------------------------------

  # Taking a system off a map only sets `visible: false`, so "on the map" and "in the database"
  # are two different questions and the import needs both answers: what is on the map decides
  # whether attributes may be overwritten, what is in the database decides whether a row is new.
  defp present_solar_system_ids(map_id) do
    all =
      case WandererApp.MapSystemRepo.get_all_by_map(map_id) do
        {:ok, systems} -> MapSet.new(systems, & &1.solar_system_id)
        _ -> MapSet.new()
      end

    visible =
      case WandererApp.MapSystemRepo.get_visible_by_map(map_id) do
        {:ok, systems} -> MapSet.new(systems, & &1.solar_system_id)
        _ -> MapSet.new()
      end

    %{all: all, visible: visible}
  end

  # Version 1 documents only ever carried systems that were on the map.
  defp wanted_on_map?(system), do: Map.get(system, "visible", true) != false

  defp import_system(map_id, system, user_id, character_id, present) do
    case parse_solar_system_id(system["solar_system_id"]) do
      {:ok, solar_system_id} ->
        cond do
          MapSet.member?(present.visible, solar_system_id) ->
            # a system already on the map keeps what it has, but takes what it is missing:
            # somebody importing a chain wants the notes and the colours that come with it
            add_to_map(map_id, solar_system_id, system, user_id, character_id, fn ->
              fill_missing_system_attributes(map_id, solar_system_id, system)
              :present
            end)

          wanted_on_map?(system) ->
            add_to_map(map_id, solar_system_id, system, user_id, character_id, fn ->
              # off the map until now, so nothing here is worth keeping over the document -
              # except that showing it again wipes some fields, which are put back in full
              restore_system_attributes(map_id, solar_system_id, system, present)
              :added
            end)

          true ->
            import_hidden_system(map_id, solar_system_id, system, present)
        end

      error ->
        Logger.warning("[Transfer] skipped system #{inspect(system)}: #{inspect(error)}")
        :skipped
    end
  end

  defp add_to_map(map_id, solar_system_id, system, user_id, character_id, then_fun) do
    case Server.add_system(
           map_id,
           %{solar_system_id: solar_system_id, coordinates: position(system["position"])},
           user_id,
           character_id
         ) do
      :ok ->
        then_fun.()

      error ->
        Logger.warning("[Transfer] skipped system #{inspect(system)}: #{inspect(error)}")
        :skipped
    end
  end

  # A system the document leaves off the map is written straight to the database. Going through
  # the map server would show it to everybody on the map, which is the one thing the exporting
  # side said not to do.
  defp import_hidden_system(map_id, solar_system_id, system, present) do
    if MapSet.member?(present.all, solar_system_id) do
      fill_missing_system_attributes(map_id, solar_system_id, system)
      :present
    else
      create_hidden_system(map_id, solar_system_id, system)
    end
  end

  defp create_hidden_system(map_id, solar_system_id, system) do
    with {:ok, static} <- WandererApp.CachedInfo.get_system_static_info(solar_system_id),
         %{"x" => x, "y" => y} <- position(system["position"]) || %{"x" => 0, "y" => 0},
         {:ok, _created} <-
           WandererApp.MapSystemRepo.create(%{
             map_id: map_id,
             solar_system_id: solar_system_id,
             name: static.solar_system_name,
             position_x: x,
             position_y: y,
             visible: false
           }) do
      fill_missing_system_attributes(map_id, solar_system_id, system)
      :added_hidden
    else
      error ->
        Logger.warning("[Transfer] skipped off-map system #{solar_system_id}: #{inspect(error)}")

        :skipped
    end
  end

  @system_attributes [
    {"custom_name", :custom_name, :update_system_custom_name, :update_custom_name},
    {"description", :description, :update_system_description, :update_description},
    {"labels", :labels, :update_system_labels, :update_labels},
    {"status", :status, :update_system_status, :update_status},
    {"tag", :tag, :update_system_tag, :update_tag},
    {"temporary_name", :temporary_name, :update_system_temporary_name, :update_temporary_name},
    {"locked", :locked, :update_system_locked, :update_locked},
    {"linked_sig_eve_id", :linked_sig_eve_id, :update_system_linked_sig_eve_id,
     :update_linked_sig_eve_id}
  ]

  # Putting a system back on the map clears these, so the document has to say them again.
  @cleared_when_shown [:labels, :tag, :temporary_name, :linked_sig_eve_id]

  defp apply_system_attributes(map_id, solar_system_id, system) do
    Enum.each(@system_attributes, &apply_attribute(map_id, solar_system_id, system, &1))
  end

  # A system that was on this map before, only hidden, may carry a note somebody here wrote. That
  # note outranks the document, but the fields showing the system again has just wiped do not.
  defp restore_system_attributes(map_id, solar_system_id, system, present) do
    if MapSet.member?(present.all, solar_system_id) do
      Enum.each(@system_attributes, fn {_key, attribute, _fun, _repo_fun} = definition ->
        if attribute in @cleared_when_shown do
          apply_attribute(map_id, solar_system_id, system, definition)
        end
      end)

      fill_missing_system_attributes(map_id, solar_system_id, system)
    else
      apply_system_attributes(map_id, solar_system_id, system)
    end
  end

  defp fill_missing_system_attributes(map_id, solar_system_id, system) do
    case WandererApp.MapSystemRepo.get_by_map_and_solar_system_id(map_id, solar_system_id) do
      {:ok, current} when not is_nil(current) ->
        Enum.each(@system_attributes, fn {_key, attribute, _fun, _repo_fun} = definition ->
          if blank?(Map.get(current, attribute)) do
            apply_attribute(map_id, solar_system_id, system, definition, current)
          end
        end)

      _ ->
        apply_system_attributes(map_id, solar_system_id, system)
    end
  end

  defp apply_attribute(map_id, solar_system_id, system, definition, current \\ nil)

  defp apply_attribute(map_id, solar_system_id, system, {key, attribute, fun, repo_fun}, current) do
    case Map.get(system, key) do
      value when value in [nil, "", false] ->
        :ok

      value ->
        # a system nobody can see is not worth telling the map about
        if is_map(current) and current.visible == false do
          apply(WandererApp.MapSystemRepo, repo_fun, [current, %{attribute => value}])
        else
          apply(Server, fun, [map_id, %{:solar_system_id => solar_system_id, attribute => value}])
        end
    end
  end

  # status 0 is "nothing said about this system", which an import is free to fill in
  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(0), do: true
  defp blank?(false), do: true
  defp blank?([]), do: true
  defp blank?("[]"), do: true
  defp blank?(_value), do: false

  defp import_connections(map_id, connections, user_id, character_id) do
    existing_pairs = existing_connection_pairs(map_id)

    paste_payload =
      connections
      |> Enum.filter(&is_map/1)
      |> Enum.flat_map(fn connection ->
        with {:ok, source} <- parse_solar_system_id(connection["source"]),
             {:ok, target} <- parse_solar_system_id(connection["target"]) do
          [
            connection
            |> Map.take([
              "type",
              "mass_status",
              "time_status",
              "ship_size_type",
              "wormhole_type",
              "locked",
              "dangerous",
              "bubbled",
              "custom_info"
            ])
            |> Map.merge(%{"source" => to_string(source), "target" => to_string(target)})
          ]
        else
          _ -> []
        end
      end)

    Server.paste_connections(map_id, paste_payload, user_id, character_id)

    # the payload is everything the document had; only the pairs the map did not already carry
    # are new, and a document may well name the same pair twice
    paste_payload
    |> Enum.map(&connection_pair(&1["source"], &1["target"]))
    |> Enum.uniq()
    |> Enum.count(&(not MapSet.member?(existing_pairs, &1)))
  end

  defp existing_connection_pairs(map_id) do
    case WandererApp.MapConnectionRepo.get_by_map(map_id) do
      {:ok, connections} ->
        MapSet.new(connections, &connection_pair(&1.solar_system_source, &1.solar_system_target))

      _ ->
        MapSet.new()
    end
  end

  # a connection is the same connection whichever end the document names first
  defp connection_pair(source, target) do
    [to_string(source), to_string(target)] |> Enum.sort() |> List.to_tuple()
  end

  defp import_signatures(map_id, signatures, character_id) do
    character_eve_id = importing_character_eve_id(character_id)

    signatures
    |> Enum.filter(&is_map/1)
    |> Enum.group_by(& &1["solar_system_id"])
    |> Enum.reduce(0, fn {solar_system_id, system_signatures}, acc ->
      with {:ok, parsed_id} <- parse_solar_system_id(solar_system_id),
           {:ok, system} when not is_nil(system) <-
             WandererApp.MapSystemRepo.get_by_map_and_solar_system_id(map_id, parsed_id) do
        acc + create_signatures(system.id, system_signatures, character_eve_id)
      else
        _ -> acc
      end
    end)
  end

  # `create` upserts on (system_id, eve_id), so a signature the target already has comes back
  # {:ok, _} without anything having been added. Only the ones that were not there are new.
  defp create_signatures(system_id, signatures, character_eve_id) do
    existing_eve_ids = existing_signature_eve_ids(system_id, signatures)

    Enum.count(signatures, fn signature ->
      attrs =
        signature
        |> Map.take([
          "eve_id",
          "name",
          "temporary_name",
          "description",
          "kind",
          "group",
          "type",
          "custom_info",
          "linked_system_id"
        ])
        |> Map.new(fn {key, value} -> {String.to_existing_atom(key), value} end)
        |> Map.put(:system_id, system_id)
        |> Map.put(:character_eve_id, character_eve_id)

      case MapSystemSignature.create(attrs) do
        {:ok, _} ->
          not MapSet.member?(existing_eve_ids, to_string(signature["eve_id"]))

        {:error, reason} ->
          Logger.warning("[Transfer] skipped signature: #{inspect(reason)}")
          false
      end
    end)
  end

  defp existing_signature_eve_ids(system_id, signatures) do
    eve_ids = signatures |> Enum.map(&to_string(&1["eve_id"])) |> Enum.uniq()

    case MapSystemSignature.by_system_id_and_eve_ids(system_id, eve_ids) do
      {:ok, existing} -> MapSet.new(existing, &to_string(&1.eve_id))
      _ -> MapSet.new()
    end
  end

  # `character_eve_id` is required on a signature, and the character who scanned it on the
  # exporting side means nothing here - the import is attributed to whoever ran it.
  defp importing_character_eve_id(character_id) do
    case WandererApp.Character.get_character(character_id) do
      {:ok, %{eve_id: eve_id}} when not is_nil(eve_id) -> to_string(eve_id)
      _ -> "0"
    end
  end

  defp import_comments(map_id, comments, character_id) do
    by_system(map_id, comments, fn system, entries ->
      existing = existing_comment_texts(system.id)

      Enum.count(entries, fn comment ->
        text = comment["text"]

        if is_binary(text) and text != "" and not MapSet.member?(existing, text) do
          case MapSystemComment.create(%{
                 system_id: system.id,
                 character_id: character_id,
                 text: text
               }) do
            {:ok, _} ->
              true

            {:error, reason} ->
              Logger.warning("[Transfer] skipped comment: #{inspect(reason)}")
              false
          end
        else
          false
        end
      end)
    end)
  end

  defp existing_comment_texts(system_id) do
    case MapSystemComment.by_system_ids([system_id]) do
      {:ok, comments} -> MapSet.new(comments, & &1.text)
      _ -> MapSet.new()
    end
  end

  defp import_structures(map_id, structures, character_id) do
    character_eve_id = importing_character_eve_id(character_id)

    by_system(map_id, structures, fn system, entries ->
      existing = existing_structure_names(system.id)

      Enum.count(entries, fn structure ->
        name = structure["name"]

        if is_binary(name) and not MapSet.member?(existing, name) do
          attrs =
            structure
            |> Map.take([
              "solar_system_name",
              "structure_type_id",
              "structure_type",
              "name",
              "notes",
              "owner_name",
              "owner_ticker",
              "owner_id",
              "status",
              "end_time"
            ])
            |> Map.new(fn {key, value} -> {String.to_existing_atom(key), value} end)
            |> Map.merge(%{
              system_id: system.id,
              solar_system_id: system.solar_system_id,
              character_eve_id: character_eve_id
            })

          case MapSystemStructure.create(attrs) do
            {:ok, _} ->
              true

            {:error, reason} ->
              Logger.warning("[Transfer] skipped structure: #{inspect(reason)}")
              false
          end
        else
          false
        end
      end)
    end)
  end

  defp existing_structure_names(system_id) do
    case MapSystemStructure.by_system_ids([system_id]) do
      {:ok, structures} -> MapSet.new(structures, & &1.name)
      _ -> MapSet.new()
    end
  end

  # comments and structures both arrive keyed by solar system, and both have to find the row the
  # import has just written for that system
  defp by_system(map_id, entries, create_fun) do
    entries
    |> Enum.filter(&is_map/1)
    |> Enum.group_by(& &1["solar_system_id"])
    |> Enum.reduce(0, fn {solar_system_id, grouped}, acc ->
      with {:ok, parsed_id} <- parse_solar_system_id(solar_system_id),
           {:ok, system} when not is_nil(system) <-
             WandererApp.MapSystemRepo.get_by_map_and_solar_system_id(map_id, parsed_id) do
        acc + create_fun.(system, grouped)
      else
        _ -> acc
      end
    end)
  end

  # The target map's own labels win: a document only adds the definitions for ids the target
  # does not know yet, so importing never renames or recolours a label somebody here set up.
  defp merge_system_labels(map_id, incoming) when is_list(incoming) do
    with {:ok, current} <- WandererApp.MapRepo.get_system_labels(map_id) do
      known = MapSet.new(current, & &1["id"])

      additions =
        incoming
        |> Enum.filter(&is_map/1)
        |> Enum.reject(&MapSet.member?(known, &1["id"]))

      if additions != [] do
        case WandererApp.MapRepo.update_system_labels(map_id, current ++ additions) do
          {:ok, _map, _labels} ->
            :ok

          {:error, reason} ->
            Logger.warning("[Transfer] kept the target's labels as they were: #{inspect(reason)}")
        end
      end
    end

    :ok
  end

  defp merge_system_labels(_map_id, _incoming), do: :ok

  defp position(%{"x" => x, "y" => y}) when is_number(x) and is_number(y),
    do: %{"x" => round(x), "y" => round(y)}

  defp position(_), do: nil

  defp parse_solar_system_id(id) when is_integer(id), do: {:ok, id}

  defp parse_solar_system_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {parsed, ""} -> {:ok, parsed}
      _ -> {:error, :invalid_solar_system_id}
    end
  end

  defp parse_solar_system_id(_), do: {:error, :invalid_solar_system_id}
end
