defmodule WandererApp.Api.MapDiscordSettingsTest do
  @moduledoc """
  Where the Discord webhook and the home system are kept.
  """

  use WandererApp.DataCase, async: false

  alias WandererApp.Api.Map, as: MapResource

  @webhook "https://discord.com/api/webhooks/1/abc"
  @jita 30_000_142

  setup do
    %{map: WandererAppWeb.Factory.create_map()}
  end

  test "a map starts with neither", %{map: map} do
    assert is_nil(map.discord_webhook_url)
    assert is_nil(map.home_solar_system_id)
  end

  test "both are stored together", %{map: map} do
    assert {:ok, updated} =
             MapResource.update_discord_settings(map, %{
               discord_webhook_url: @webhook,
               home_solar_system_id: @jita
             })

    assert updated.discord_webhook_url == @webhook
    assert updated.home_solar_system_id == @jita
  end

  describe "the stored digest" do
    test "starts empty and can be written", %{map: map} do
      assert is_nil(map.discord_last_digest)

      assert {:ok, updated} = MapResource.update_discord_digest(map, %{discord_last_digest: 42})
      assert updated.discord_last_digest == 42
    end
  end

  describe "deliver/1" do
    test "says what is missing rather than posting nothing", %{map: map} do
      assert {:error, :no_webhook} = WandererApp.Map.HomeRoutesNotifier.deliver(map.id)

      {:ok, map} =
        MapResource.update_discord_settings(map, %{
          discord_webhook_url: @webhook,
          home_solar_system_id: nil
        })

      assert {:error, :no_home_system} = WandererApp.Map.HomeRoutesNotifier.deliver(map.id)

      {:ok, map} =
        MapResource.update_discord_settings(map, %{
          discord_webhook_url: @webhook,
          home_solar_system_id: 31_001_269
        })

      assert {:error, :no_hubs} = WandererApp.Map.HomeRoutesNotifier.deliver(map.id)
    end

    test "an unknown map is not a webhook problem" do
      assert {:error, :map_not_found} =
               WandererApp.Map.HomeRoutesNotifier.deliver(Ecto.UUID.generate())
    end
  end

  test "clearing the webhook turns the announcements off", %{map: map} do
    {:ok, map} =
      MapResource.update_discord_settings(map, %{
        discord_webhook_url: @webhook,
        home_solar_system_id: @jita
      })

    assert {:ok, cleared} =
             MapResource.update_discord_settings(map, %{
               discord_webhook_url: nil,
               home_solar_system_id: @jita
             })

    assert is_nil(cleared.discord_webhook_url)
    assert cleared.home_solar_system_id == @jita
  end
end
