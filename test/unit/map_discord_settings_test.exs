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
