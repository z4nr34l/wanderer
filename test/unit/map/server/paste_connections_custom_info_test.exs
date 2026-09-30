defmodule WandererApp.Map.Server.PasteConnectionsCustomInfoTest do
  @moduledoc """
  Pasting connections carries the connection's free-text note (`custom_info`) into the created
  connection, the same way it carries mass/time status and the other optional attributes.
  """

  use WandererApp.DataCase

  import WandererApp.MapTestHelpers

  alias WandererApp.Map.Server

  @system_a 31_000_001
  @system_b 31_000_002

  setup do
    setup_system_static_info_cache(%{
      @system_a => static_info(@system_a, "J100001", 1),
      @system_b => static_info(@system_b, "J100002", 2)
    })

    :ok
  end

  describe "paste_connections/4" do
    test "keeps custom_info together with the other pasted attributes" do
      %{map_id: map_id, user_id: user_id, character_id: character_id} = start_map_with_systems()

      Server.paste_connections(
        map_id,
        [
          %{
            "source" => "#{@system_a}",
            "target" => "#{@system_b}",
            "mass_status" => 1,
            "custom_info" => ~s({"note":"static to C2"})
          }
        ],
        user_id,
        character_id
      )

      assert {:ok, connection} = find_connection(map_id)
      assert connection.custom_info == ~s({"note":"static to C2"})
      assert connection.mass_status == 1

      cleanup_test_data(map_id)
    end

    test "a pasted connection without custom_info has none" do
      %{map_id: map_id, user_id: user_id, character_id: character_id} = start_map_with_systems()

      Server.paste_connections(
        map_id,
        [%{"source" => "#{@system_a}", "target" => "#{@system_b}"}],
        user_id,
        character_id
      )

      assert {:ok, connection} = find_connection(map_id)
      assert is_nil(connection.custom_info)

      cleanup_test_data(map_id)
    end
  end

  defp find_connection(map_id) do
    with {:ok, connections} <- WandererApp.MapConnectionRepo.get_by_map(map_id),
         %{} = connection <-
           Enum.find(
             connections,
             &(&1.solar_system_source == @system_a and &1.solar_system_target == @system_b)
           ) do
      {:ok, connection}
    else
      _ -> {:error, :not_found}
    end
  end

  defp start_map_with_systems do
    setup_ddrt_mocks()

    user = insert(:user)
    character = insert(:character, %{user_id: user.id})
    map = insert(:map, %{owner_id: character.id})

    :ok = ensure_map_started(map.id)

    Enum.each([@system_a, @system_b], fn solar_system_id ->
      :ok =
        Server.add_system(
          map.id,
          %{solar_system_id: solar_system_id, coordinates: %{"x" => 0, "y" => 0}},
          user.id,
          character.id
        )

      assert wait_for_system_on_map(map.id, solar_system_id)
    end)

    %{map_id: map.id, user_id: user.id, character_id: character.id}
  end

  defp static_info(id, name, system_class) do
    %{
      solar_system_id: id,
      solar_system_name: name,
      solar_system_name_lc: String.downcase(name),
      region_id: 11_000_001,
      constellation_id: 21_000_001,
      region_name: "A-R00001",
      constellation_name: "A-C00001",
      system_class: system_class,
      security: "-1.0"
    }
  end
end
