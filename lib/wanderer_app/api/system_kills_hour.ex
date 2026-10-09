defmodule WandererApp.Api.SystemKillsHour do
  @moduledoc """
  One hour of NPC kills across New Eden, as CCP reported it.

  ESI only ever says what happened in the last hour. A day's worth has to be put together an
  hour at a time and kept, which is what Dotlan does too - and it has to be kept somewhere a
  restart does not wipe, or the day would start over at every deploy.

  One row per hour CCP published, named by the time CCP gave it, so reading the same hour twice
  replaces it rather than counting it twice. The kills themselves are one map of system to count,
  holding only the systems where something died: that is what ESI sends, and a day of it is a
  couple of dozen rows rather than tens of thousands.
  """

  use Ash.Resource,
    domain: WandererApp.Api,
    data_layer: AshPostgres.DataLayer,
    primary_read_warning?: false

  postgres do
    repo(WandererApp.Repo)
    table("system_kills_hours_v1")
  end

  code_interface do
    define(:record, action: :record)
    define(:since, action: :since, args: [:since])
    define(:before, action: :before, args: [:before])
    define(:destroy, action: :destroy)
  end

  actions do
    defaults [:read, :destroy]

    create :record do
      accept [:hour, :npc_kills]
      primary?(true)

      upsert?(true)
      upsert_identity(:unique_hour)
      upsert_fields([:npc_kills])
    end

    read :since do
      argument(:since, :utc_datetime, allow_nil?: false)

      filter(expr(hour >= ^arg(:since)))
    end

    read :before do
      argument(:before, :utc_datetime, allow_nil?: false)

      filter(expr(hour < ^arg(:before)))
    end
  end

  attributes do
    uuid_primary_key :id

    # the moment CCP last published this hour, which is what tells one hour from the next
    attribute :hour, :utc_datetime do
      allow_nil?(false)
    end

    # solar system id, as a string key, to the NPC kills in it that hour
    attribute :npc_kills, :map do
      allow_nil?(false)
      default(%{})
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  identities do
    identity :unique_hour, [:hour]
  end
end
