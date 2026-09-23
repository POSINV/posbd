defmodule Posbd.Repo.Migrations.CreateBusinessMemberships do
  use Ecto.Migration

  def change do
    create table(:business_memberships, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :business_id, references(:businesses, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :role, :string, null: false, default: "owner"
      add :permissions, {:array, :string}, null: false, default: []

      timestamps(type: :utc_datetime)
    end

    create index(:business_memberships, [:business_id])
    create index(:business_memberships, [:user_id])
    create unique_index(:business_memberships, [:business_id, :user_id])
  end
end
