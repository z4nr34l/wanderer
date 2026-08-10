defmodule WandererApp.Repo.Migrations.AddMapSystemLabels do
  @moduledoc """
  Moves system-label definitions from per-user JSON settings to one server-side value per map.

  Existing labels are preserved by preferring the map default, then any member's saved labels.
  Legacy JSON keys are deliberately left in place for rollback safety; application code no longer
  reads or writes them.
  """

  use Ecto.Migration

  @default_labels ~s([{"id":"a","name":"A","color":"#2d803b"},{"id":"b","name":"B","color":"#3d94af"},{"id":"c","name":"C","color":"#3d94af"},{"id":"1","name":"1","color":"#563daf"},{"id":"2","name":"2","color":"#8f3daf"},{"id":"3","name":"3","color":"#3d65af"}])

  def up do
    alter table(:maps_v1) do
      add :system_labels, :text, null: false, default: @default_labels
    end

    flush()

    execute("""
    UPDATE maps_v1 AS map
    SET system_labels = COALESCE(
      (
        SELECT defaults.remote_settings::jsonb->'system_labels'
        FROM map_default_settings AS defaults
        WHERE defaults.map_id = map.id
          AND defaults.remote_settings IS NOT NULL
          AND jsonb_typeof(defaults.remote_settings::jsonb->'system_labels') = 'array'
          AND jsonb_array_length(defaults.remote_settings::jsonb->'system_labels') > 0
        LIMIT 1
      )::text,
      (
        SELECT settings.settings::jsonb->'system_labels'
        FROM map_user_settings_v1 AS settings
        WHERE settings.map_id = map.id
          AND settings.settings IS NOT NULL
          AND jsonb_typeof(settings.settings::jsonb->'system_labels') = 'array'
          AND jsonb_array_length(settings.settings::jsonb->'system_labels') > 0
        ORDER BY settings.id
        LIMIT 1
      )::text,
      '#{@default_labels}'
    )
    """)
  end

  def down do
    alter table(:maps_v1) do
      remove :system_labels
    end
  end
end
