defmodule Posbd.Repo.Migrations.CreateProductVariants do
  use Ecto.Migration

  def change do
    create table(:product_variants, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :product_id, references(:products, type: :binary_id, on_delete: :delete_all),
        null: false

      # Denormalized so barcode/SKU lookups at billing time (and uniqueness)
      # don't require joining through products for every scan.
      add :business_id, references(:businesses, type: :binary_id, on_delete: :delete_all),
        null: false

      add :sku, :string
      add :barcode, :string
      add :purchase_price, :decimal
      add :selling_price, :decimal
      add :mrp, :decimal
      add :tax_rate, :decimal, null: false, default: 0
      add :position, :integer, null: false, default: 0
      add :active, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    create index(:product_variants, [:product_id])
    create index(:product_variants, [:business_id])
    create unique_index(:product_variants, [:business_id, :sku], where: "sku IS NOT NULL")
    create unique_index(:product_variants, [:business_id, :barcode], where: "barcode IS NOT NULL")
  end
end
