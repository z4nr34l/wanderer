defmodule WandererApp.Api.MapBridge do
  @moduledoc """
  A jump bridge the map knows about.

  Bridges are kept apart from the map's own connections on purpose: a null bloc runs hundreds of
  them and drawing that on a chain map would drown it. They exist to be counted - or not - when a
  route is worked out, and a bridge marked dangerous is one the route settings can steer around.
  """

  use Ash.Resource,
    domain: WandererApp.Api,
    data_layer: AshPostgres.DataLayer,
    primary_read_warning?: false

  postgres do
    repo(WandererApp.Repo)
    table("map_bridges_v1")

    references do
      reference :map, on_delete: :delete
    end
  end

  code_interface do
    define(:new, action: :new)
    define(:destroy, action: :destroy)
    define(:by_id, get_by: [:id], action: :read)
    define(:by_map, action: :by_map)
    define(:by_map_and_systems, action: :by_map_and_systems)
    define(:update_dangerous, action: :update_dangerous)
  end

  actions do
    defaults [:read, :destroy]

    create :new do
      accept [:map_id, :solar_system_source, :solar_system_target, :dangerous]
      primary?(true)

      upsert?(true)
      upsert_identity(:unique_bridge)
      upsert_fields([:dangerous])
    end

    update :update_dangerous do
      accept [:dangerous]
      require_atomic? false
    end

    read :by_map do
      argument(:map_id, :string, allow_nil?: false)

      filter(expr(map_id == ^arg(:map_id)))
    end

    read :by_map_and_systems do
      argument(:map_id, :string, allow_nil?: false)
      argument(:solar_system_source, :integer, allow_nil?: false)
      argument(:solar_system_target, :integer, allow_nil?: false)

      filter(
        expr(
          map_id == ^arg(:map_id) and
            solar_system_source == ^arg(:solar_system_source) and
            solar_system_target == ^arg(:solar_system_target)
        )
      )
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :solar_system_source, :integer do
      allow_nil? false
    end

    attribute :solar_system_target, :integer do
      allow_nil? false
    end

    # a bridge somebody would rather not be bounced through - the route settings can avoid these
    attribute :dangerous, :boolean do
      default false
      allow_nil? false
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :map, WandererApp.Api.Map do
      attribute_writable? true
    end
  end

  identities do
    identity :unique_bridge, [:map_id, :solar_system_source, :solar_system_target]
  end
end
