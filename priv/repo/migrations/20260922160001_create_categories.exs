defmodule Posbd.Repo.Migrations.CreateCategories do
  use Ecto.Migration

  def change do
    create table(:categories, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :business_id, references(:businesses, type: :binary_id, on_delete: :delete_all),
        null: false

      add :parent_id, references(:categories, type: :binary_id, on_delete: :nilify_all)
      add :name, :string, null: false
      add :slug, :string, null: false
      add :position, :integer, null: false, default: 0
      add :active, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    create index(:categories, [:business_id])
    create index(:categories, [:parent_id])
    create unique_index(:categories, [:business_id, :slug])
  end
end
