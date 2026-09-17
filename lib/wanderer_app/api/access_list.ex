defmodule WandererApp.Api.AccessList do
  @moduledoc false

  use Ash.Resource,
    domain: WandererApp.Api,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource]

  postgres do
    repo(WandererApp.Repo)
    table("access_lists_v1")
  end

  json_api do
    type "access_lists"

    includes([:owner, :members])

    default_fields([
      :name,
      :description,
      :discord_guild_id
    ])

    derive_filter?(true)
    derive_sort?(true)

    routes do
      base("/access_lists")
      get(:read)
      index :read
      post(:new)
      patch(:update)
      delete(:destroy)
    end
  end

  code_interface do
    define(:create, action: :create)
    define(:available, action: :available)
    define(:new, action: :new)
    define(:read, action: :read)
    define(:update, action: :update)
    define(:destroy, action: :destroy)

    define(:by_id,
      get_by: [:id],
      action: :read
    )
  end

  actions do
    default_accept [
      :name,
      :description,
      :owner_id,
      :discord_guild_id
    ]

    defaults [:create, :read, :destroy]

    read :available do
      prepare WandererApp.Api.Preparations.FilterAclsByRoles
    end

    create :new do
      # Added :api_key to the accepted attributes
      accept [:name, :description, :owner_id, :api_key, :discord_guild_id]
      primary?(true)
    end

    update :update do
      accept [:name, :description, :owner_id, :api_key, :discord_guild_id]
      primary?(true)
      require_atomic? false
    end

    update :assign_owner do
      accept [:owner_id]
      require_atomic? false
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :description, :string do
      allow_nil? true
      public? true
    end

    # Which Discord server the role members of this list live on. A role id on its own says
    # nothing about where it came from, so it is kept here, once, for the whole list rather than
    # repeated on every member. An access list is also the thing that is shared between maps, so
    # this is the level at which the answer stays true.
    attribute :discord_guild_id, :string do
      allow_nil? true
      public? true
    end

    # Note: api_key intentionally not public for security
    attribute :api_key, :string do
      allow_nil? true
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :owner, WandererApp.Api.Character do
      attribute_writable? true
      public? true
    end

    has_many :members, WandererApp.Api.AccessListMember do
      public? true
    end
  end
end
