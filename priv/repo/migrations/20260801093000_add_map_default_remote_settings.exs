defmodule WandererApp.Repo.Migrations.AddMapDefaultRemoteSettings do
  @moduledoc """
  Map defaults only covered the settings kept in the browser, so anything stored per user on the
  server - system labels among them - could not be handed to a new member of the map.
  """

  use Ecto.Migration

  def up do
    alter table(:map_default_settings) do
      add :remote_settings, :text
    end
  end

  def down do
    alter table(:map_default_settings) do
      remove :remote_settings
    end
  end
end
