defmodule Posbd.Repo.Migrations.CreateInventoryTransactions do
  use Ecto.Migration

  def change do
    create table(:inventory_transactions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :business_id, references(:businesses, type: :binary_id, on_delete: :delete_all),
        null: false

      add :product_id, references(:products, type: :binary_id, on_delete: :delete_all)
      add :variant_id, references(:product_variants, type: :binary_id, on_delete: :delete_all)
      add :performed_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      add :movement_type, :string, null: false
      add :direction, :string, null: false
      add :quantity, :integer, null: false
      add :reference, :string
      add :notes, :string
      add :occurred_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create constraint(:inventory_transactions, :exactly_one_of_product_or_variant,
             check: "(product_id IS NOT NULL)::int + (variant_id IS NOT NULL)::int = 1"
           )

    create constraint(:inventory_transactions, :quantity_must_be_positive, check: "quantity > 0")

    create index(:inventory_transactions, [:business_id])
    create index(:inventory_transactions, [:product_id, :occurred_at])
    create index(:inventory_transactions, [:variant_id, :occurred_at])
  end
end
