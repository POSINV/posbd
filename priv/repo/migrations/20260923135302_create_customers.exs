defmodule Posbd.Repo.Migrations.CreateCustomers do
  use Ecto.Migration

  def change do
    create table(:customers, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :business_id, references(:businesses, type: :binary_id, on_delete: :delete_all),
        null: false

      add :name, :string, null: false
      add :phone, :string
      add :email, :string
      add :address, :string
      add :notes, :string

      timestamps(type: :utc_datetime)
    end

    create index(:customers, [:business_id])
    create index(:customers, [:business_id, :phone])
    create index(:customers, [:business_id, :name])
  end
end
