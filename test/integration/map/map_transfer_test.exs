defmodule WandererApp.Map.MapTransferTest do
  @moduledoc """
  The export/import round trip.

  Covers the three things the shape of this feature rests on: what comes out of a map goes back
  into an empty one, running the same document twice adds nothing the second time, and a system
  deleted from the target comes back with the attributes the document carries for it.
  """

  use WandererApp.DataCase

  import WandererApp.MapTestHelpers

  alias WandererApp.Api.MapSystemComment
  alias WandererApp.Api.MapSystemSignature
  alias WandererApp.Api.MapSystemStructure
  alias WandererApp.Map.Operations.Transfer
  alias WandererApp.Map.Server

  @system_a 31_000_101
  @system_b 31_000_102

  setup do
    setup_transfer_test_systems()
    :ok
  end

  describe "export/2 then import/5" do
    test "carries the flags a chain is read by: dangerous, bubbled, and what a system is linked to" do
      source = start_test_map()
      target = start_test_map()

      seed_source_map(source)

      {:ok, document} = Transfer.export(source.map_id)

      [exported_connection] = document["connections"]
      assert exported_connection["dangerous"] == true
      assert exported_connection["bubbled"] == 2

      exported_system =
        Enum.find(document["systems"], &(&1["solar_system_id"] == @system_a))

      assert exported_system["linked_sig_eve_id"] == "ABC-123"

      {:ok, _stats} =
        Transfer.import(target.map_id, document, target.user_id, target.character_id)

      connection = connection_between(target.map_id, @system_a, @system_b)
      assert connection.dangerous
      assert connection.bubbled == 2

      {:ok, system} =
        WandererApp.MapSystemRepo.get_by_map_and_solar_system_id(target.map_id, @system_a)

      assert system.linked_sig_eve_id == "ABC-123"
    end

    test "carries systems, their attributes, connections and signatures into an empty map" do
      source = start_test_map()
      target = start_test_map()

      seed_source_map(source)

      {:ok, document} = Transfer.export(source.map_id)

      assert document["version"] == 2
      assert length(document["systems"]) == 2
      assert length(document["connections"]) == 1
      assert length(document["signatures"]) == 1

      {:ok, stats} =
        Transfer.import(target.map_id, document, target.user_id, target.character_id)

      assert stats == %{
               systems: 2,
               hidden_systems: 0,
               connections: 1,
               signatures: 1,
               comments: 0,
               structures: 0
             }

      assert wait_for_system_on_map(target.map_id, @system_a)
      assert wait_for_system_on_map(target.map_id, @system_b)

      {:ok, system} =
        WandererApp.MapSystemRepo.get_by_map_and_solar_system_id(target.map_id, @system_a)

      assert system.custom_name == "Home"
      assert system.description == "staging"
      assert system.tag == "A"
      assert system.status == 1
      assert system.temporary_name == "HS-1"
      assert system.position_x == 120
      assert system.position_y == 240

      {:ok, connections} = WandererApp.MapConnectionRepo.get_by_map(target.map_id)
      assert length(connections) == 1

      {:ok, signatures} = MapSystemSignature.by_system_id(system.id)
      assert [%{eve_id: "ABC-123", name: "Wormhole"}] = signatures

      cleanup_test_data(source.map_id)
      cleanup_test_data(target.map_id)
    end

    test "a second import of the same document adds nothing and says so" do
      source = start_test_map()
      target = start_test_map()

      seed_source_map(source)

      {:ok, document} = Transfer.export(source.map_id)

      {:ok, _first} =
        Transfer.import(target.map_id, document, target.user_id, target.character_id)

      assert wait_for_system_on_map(target.map_id, @system_a)

      {:ok, second} =
        Transfer.import(target.map_id, document, target.user_id, target.character_id)

      # the counts are the only feedback anyone gets about an import being safe to re-run, so a
      # no-op has to report zeroes rather than the size of the document
      assert second == %{
               systems: 0,
               hidden_systems: 0,
               connections: 0,
               signatures: 0,
               comments: 0,
               structures: 0
             }

      cleanup_test_data(source.map_id)
      cleanup_test_data(target.map_id)
    end

    test "a system deleted from the target comes back with its attributes" do
      source = start_test_map()
      target = start_test_map()

      seed_source_map(source)

      {:ok, document} = Transfer.export(source.map_id)
      {:ok, _} = Transfer.import(target.map_id, document, target.user_id, target.character_id)

      assert wait_for_system_on_map(target.map_id, @system_a)

      :ok = Server.delete_systems(target.map_id, [@system_a], target.user_id, target.character_id)

      refute system_visible?(target.map_id, @system_a)

      {:ok, stats} =
        Transfer.import(target.map_id, document, target.user_id, target.character_id)

      # deletion leaves the row behind with visible: false, so counting rows rather than systems
      # on the map used to treat this one as already present - it came back stripped
      assert stats.systems == 1

      assert wait_for_system_on_map(target.map_id, @system_a)

      {:ok, system} =
        WandererApp.MapSystemRepo.get_by_map_and_solar_system_id(target.map_id, @system_a)

      assert system.custom_name == "Home"
      assert system.tag == "A"
      assert system.status == 1
      assert system.temporary_name == "HS-1"

      cleanup_test_data(source.map_id)
      cleanup_test_data(target.map_id)
    end

    test "a system nobody has on the map any more still carries its intel" do
      source = start_test_map()
      target = start_test_map()

      seed_source_map(source)

      Server.update_system_description(source.map_id, %{
        solar_system_id: @system_b,
        description: "staging, three jumps out"
      })

      :ok = Server.delete_systems(source.map_id, [@system_b], source.user_id, source.character_id)
      refute system_visible?(source.map_id, @system_b)

      {:ok, document} = Transfer.export(source.map_id)

      exported = Enum.find(document["systems"], &(&1["solar_system_id"] == @system_b))
      assert exported["visible"] == false
      assert exported["description"] == "staging, three jumps out"

      {:ok, stats} =
        Transfer.import(target.map_id, document, target.user_id, target.character_id)

      assert stats.hidden_systems == 1

      {:ok, system} =
        WandererApp.MapSystemRepo.get_by_map_and_solar_system_id(target.map_id, @system_b)

      assert system.description == "staging, three jumps out"

      # it arrived with its intel, but nobody asked for it on the map
      refute system.visible
      refute system_visible?(target.map_id, @system_b)

      cleanup_test_data(source.map_id)
      cleanup_test_data(target.map_id)
    end

    test "an off-map system on the target keeps the note somebody here wrote on it" do
      source = start_test_map()
      target = start_test_map()

      seed_source_map(source)

      Server.update_system_description(source.map_id, %{
        solar_system_id: @system_b,
        description: "what they saw"
      })

      :ok = Server.delete_systems(source.map_id, [@system_b], source.user_id, source.character_id)

      {:ok, document} = Transfer.export(source.map_id)

      :ok =
        Server.add_system(
          target.map_id,
          %{solar_system_id: @system_b, coordinates: %{"x" => 0, "y" => 0}},
          target.user_id,
          target.character_id
        )

      assert wait_for_system_on_map(target.map_id, @system_b)

      Server.update_system_description(target.map_id, %{
        solar_system_id: @system_b,
        description: "what we saw"
      })

      :ok = Server.delete_systems(target.map_id, [@system_b], target.user_id, target.character_id)

      {:ok, _stats} =
        Transfer.import(target.map_id, document, target.user_id, target.character_id)

      {:ok, system} =
        WandererApp.MapSystemRepo.get_by_map_and_solar_system_id(target.map_id, @system_b)

      assert system.description == "what we saw"

      cleanup_test_data(source.map_id)
      cleanup_test_data(target.map_id)
    end

    test "the notes on a connection, on a system and on a structure all survive the trip" do
      source = start_test_map()
      target = start_test_map()

      seed_source_map(source)

      Server.update_connection_custom_info(source.map_id, %{
        solar_system_source_id: @system_a,
        solar_system_target_id: @system_b,
        custom_info: "rolls at 2bn"
      })

      {:ok, seeded} =
        WandererApp.MapSystemRepo.get_by_map_and_solar_system_id(source.map_id, @system_a)

      {:ok, _} =
        MapSystemComment.create(%{
          system_id: seeded.id,
          character_id: source.character_id,
          text: "two Lokis sat here all evening"
        })

      {:ok, _} =
        MapSystemStructure.create(%{
          system_id: seeded.id,
          solar_system_id: @system_a,
          solar_system_name: "J101101",
          structure_type_id: "35832",
          structure_type: "Astrahus",
          character_eve_id: "90000001",
          name: "Their staging",
          notes: "timer Tuesday",
          owner_ticker: "BAD"
        })

      {:ok, document} = Transfer.export(source.map_id)

      assert length(document["comments"]) == 1
      assert length(document["structures"]) == 1

      {:ok, stats} =
        Transfer.import(target.map_id, document, target.user_id, target.character_id)

      assert stats.comments == 1
      assert stats.structures == 1

      assert wait_for_system_on_map(target.map_id, @system_a)

      connection = connection_between(target.map_id, @system_a, @system_b)
      assert connection.custom_info == "rolls at 2bn"

      {:ok, imported} =
        WandererApp.MapSystemRepo.get_by_map_and_solar_system_id(target.map_id, @system_a)

      {:ok, [comment]} = MapSystemComment.by_system_ids([imported.id])
      assert comment.text == "two Lokis sat here all evening"

      {:ok, [structure]} = MapSystemStructure.by_system_ids([imported.id])
      assert structure.name == "Their staging"
      assert structure.notes == "timer Tuesday"

      cleanup_test_data(source.map_id)
      cleanup_test_data(target.map_id)
    end

    test "a document from before hidden systems were carried still imports" do
      source = start_test_map()
      target = start_test_map()

      seed_source_map(source)

      {:ok, document} = Transfer.export(source.map_id)

      older =
        document
        |> Map.put("version", 1)
        |> Map.update!("systems", fn systems ->
          Enum.map(systems, &Map.delete(&1, "visible"))
        end)

      {:ok, stats} = Transfer.import(target.map_id, older, target.user_id, target.character_id)

      assert stats.systems == 2
      assert stats.hidden_systems == 0
      assert wait_for_system_on_map(target.map_id, @system_a)

      cleanup_test_data(source.map_id)
      cleanup_test_data(target.map_id)
    end
  end

  describe "import/5 with a document it cannot read" do
    test "refuses another version and anything that is not a document" do
      %{map_id: map_id, user_id: user_id, character_id: character_id} = start_test_map()

      assert {:error, {:unsupported_version, 99}} =
               Transfer.import(map_id, %{"version" => 99}, user_id, character_id)

      assert {:error, :invalid_document} = Transfer.import(map_id, %{}, user_id, character_id)

      cleanup_test_data(map_id)
    end
  end

  defp seed_source_map(%{map_id: map_id, user_id: user_id, character_id: character_id}) do
    :ok =
      Server.add_system(
        map_id,
        %{solar_system_id: @system_a, coordinates: %{"x" => 120, "y" => 240}},
        user_id,
        character_id
      )

    :ok =
      Server.add_system(
        map_id,
        %{solar_system_id: @system_b, coordinates: %{"x" => 300, "y" => 240}},
        user_id,
        character_id
      )

    assert wait_for_system_on_map(map_id, @system_a)
    assert wait_for_system_on_map(map_id, @system_b)

    Server.update_system_custom_name(map_id, %{solar_system_id: @system_a, custom_name: "Home"})

    Server.update_system_description(map_id, %{solar_system_id: @system_a, description: "staging"})

    Server.update_system_tag(map_id, %{solar_system_id: @system_a, tag: "A"})
    Server.update_system_status(map_id, %{solar_system_id: @system_a, status: 1})

    Server.update_system_temporary_name(map_id, %{
      solar_system_id: @system_a,
      temporary_name: "HS-1"
    })

    :ok =
      Server.add_connection(
        map_id,
        %{
          solar_system_source_id: @system_a,
          solar_system_target_id: @system_b,
          character_id: character_id
        }
      )

    Server.update_connection_dangerous(map_id, %{
      solar_system_source_id: @system_a,
      solar_system_target_id: @system_b,
      dangerous: true
    })

    Server.update_connection_bubbled(map_id, %{
      solar_system_source_id: @system_a,
      solar_system_target_id: @system_b,
      bubbled: 2
    })

    Server.update_system_linked_sig_eve_id(map_id, %{
      solar_system_id: @system_a,
      linked_sig_eve_id: "ABC-123"
    })

    {:ok, system} = WandererApp.MapSystemRepo.get_by_map_and_solar_system_id(map_id, @system_a)

    {:ok, _} =
      MapSystemSignature.create(%{
        system_id: system.id,
        eve_id: "ABC-123",
        character_eve_id: "90000001",
        name: "Wormhole",
        kind: "cosmic_signature",
        group: "Wormhole"
      })

    :ok
  end

  defp connection_between(map_id, source, target) do
    case WandererApp.MapConnectionRepo.get_by_map(map_id) do
      {:ok, connections} ->
        Enum.find(connections, fn connection ->
          {connection.solar_system_source, connection.solar_system_target} in [
            {source, target},
            {target, source}
          ]
        end)

      _ ->
        nil
    end
  end

  defp system_visible?(map_id, solar_system_id) do
    case WandererApp.MapSystemRepo.get_visible_by_map(map_id) do
      {:ok, systems} -> Enum.any?(systems, &(&1.solar_system_id == solar_system_id))
      _ -> false
    end
  end

  defp start_test_map do
    setup_ddrt_mocks()

    user = insert(:user)
    character = insert(:character, %{user_id: user.id})
    map = insert(:map, %{owner_id: character.id})

    :ok = ensure_map_started(map.id)

    %{map_id: map.id, user_id: user.id, character_id: character.id}
  end

  defp setup_transfer_test_systems do
    setup_system_static_info_cache(%{
      @system_a => %{
        solar_system_id: @system_a,
        solar_system_name: "J101101",
        solar_system_name_lc: "j101101",
        region_id: 11_000_001,
        constellation_id: 21_000_001,
        region_name: "A-R00001",
        constellation_name: "A-C00001",
        system_class: 1,
        security: "-1.0"
      },
      @system_b => %{
        solar_system_id: @system_b,
        solar_system_name: "J101102",
        solar_system_name_lc: "j101102",
        region_id: 11_000_001,
        constellation_id: 21_000_001,
        region_name: "A-R00001",
        constellation_name: "A-C00001",
        system_class: 2,
        security: "-1.0"
      }
    })
  end
end
