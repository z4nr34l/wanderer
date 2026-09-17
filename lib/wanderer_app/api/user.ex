defmodule WandererApp.Api.User do
  @moduledoc false

  use Ash.Resource,
    domain: WandererApp.Api,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshCloak, AshJsonApi.Resource]

  postgres do
    repo(WandererApp.Repo)
    table("user_v1")
  end

  json_api do
    type "users"

    # Only expose safe, non-sensitive attributes
    includes([:characters])

    derive_filter?(true)
    derive_sort?(true)

    routes do
      # No routes - this resource should not be exposed via API
    end
  end

  code_interface do
    define(:by_id,
      get_by: [:id],
      action: :read
    )

    define(:by_hash,
      get_by: [:hash],
      action: :read
    )

    define(:update_last_map,
      action: :update_last_map
    )

    define(:update_balance,
      action: :update_balance
    )

    define(:by_discord_user_id,
      get_by: [:discord_user_id],
      action: :read
    )

    define(:link_discord,
      action: :link_discord
    )

    define(:unlink_discord,
      action: :unlink_discord
    )
  end

  actions do
    default_accept [
      :name,
      :hash
    ]

    defaults [:create, :read, :destroy]

    update :update do
      require_atomic? false
    end

    update :update_last_map do
      accept([:last_map_id])
      require_atomic? false
    end

    update :update_balance do
      require_atomic? false

      accept([:balance])

      validate compare(:balance, greater_than_or_equal_to: 0),
        message: "balance cannot be negative"
    end

    update :link_discord do
      require_atomic? false

      accept([:discord_user_id, :discord_username])

      change(set_attribute(:discord_linked_at, &DateTime.utc_now/0))
    end

    update :unlink_discord do
      require_atomic? false

      accept([])

      change(set_attribute(:discord_user_id, nil))
      change(set_attribute(:discord_username, nil))
      change(set_attribute(:discord_linked_at, nil))
    end
  end

  cloak do
    vault(WandererApp.Vault)

    attributes([:balance])
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string
    attribute :hash, :string
    attribute :last_map_id, :uuid

    attribute :balance, :float do
      default 0.0

      allow_nil?(true)
    end

    # The Discord account this person has proved they control. It is deliberately on the user
    # and not on a character: one person holds many characters, and the point of the link is to
    # say who is behind them all.
    attribute :discord_user_id, :string do
      allow_nil?(true)
      public? true
    end

    attribute :discord_username, :string do
      allow_nil?(true)
      public? true
    end

    attribute :discord_linked_at, :utc_datetime_usec do
      allow_nil?(true)
      public? true
    end
  end

  relationships do
    has_many :characters, WandererApp.Api.Character do
      public? true
    end
  end

  identities do
    identity :unique_hash, [:hash] do
      pre_check?(false)
    end

    # A Discord account belongs to at most one person here, so a second person cannot claim
    # an identity that is already spoken for.
    identity :unique_discord_user_id, [:discord_user_id] do
      pre_check?(true)
      nils_distinct?(true)
    end
  end
end
