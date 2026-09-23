defmodule Posbd.Repo.Migrations.CreateProducts do
  use Ecto.Migration

  def change do
    create table(:products, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :business_id, references(:businesses, type: :binary_id, on_delete: :delete_all),
        null: false

      add :category_id, references(:categories, type: :binary_id, on_delete: :nilify_all)

      add :name, :string, null: false
      add :description, :string
      add :brand, :string
      add :unit, :string, null: false, default: "pcs"
      add :status, :string, null: false, default: "active"
      add :has_variants, :boolean, null: false, default: false

      # Only meaningful when has_variants is false; variant-level fields
      # take over otherwise (see product_variants).
      add :sku, :string
      add :barcode, :string
      add :purchase_price, :decimal
      add :selling_price, :decimal
      add :mrp, :decimal
      add :tax_rate, :decimal, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:products, [:business_id])
    create index(:products, [:category_id])
    create index(:products, [:business_id, :name])
    create unique_index(:products, [:business_id, :sku], where: "sku IS NOT NULL")
  end
end
