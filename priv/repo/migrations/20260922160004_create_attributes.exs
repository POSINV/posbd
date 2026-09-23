defmodule Posbd.Repo.Migrations.CreateAttributes do
  use Ecto.Migration

  def change do
    create table(:attributes, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :business_id, references(:businesses, type: :binary_id, on_delete: :delete_all),
        null: false

      add :name, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:attributes, [:business_id, :name])

    create table(:attribute_values, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :attribute_id, references(:attributes, type: :binary_id, on_delete: :delete_all),
        null: false

      add :value, :string, null: false
      add :position, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:attribute_values, [:attribute_id, :value])

    create table(:variant_attribute_values, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :variant_id, references(:product_variants, type: :binary_id, on_delete: :delete_all),
        null: false

      add :attribute_id, references(:attributes, type: :binary_id, on_delete: :delete_all),
        null: false

      add :attribute_value_id,
          references(:attribute_values, type: :binary_id, on_delete: :delete_all),
          null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:variant_attribute_values, [:attribute_value_id])
    # One value per attribute per variant (e.g. a variant can't be both Size=S and Size=M).
    create unique_index(:variant_attribute_values, [:variant_id, :attribute_id])
  end
end
