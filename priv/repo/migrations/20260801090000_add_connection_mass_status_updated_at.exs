defmodule WandererApp.Repo.Migrations.AddConnectionMassStatusUpdatedAt do
  @moduledoc """
  Records when a connection's mass status was last set, so rolling can count the passages made
  since the mark rather than every passage the connection ever had.
  """

  use Ecto.Migration

  def up do
    alter table(:map_chain_v1) do
      add :mass_status_updated_at, :utc_datetime_usec
    end
  end

  def down do
    alter table(:map_chain_v1) do
      remove :mass_status_updated_at
    end
  end
end
