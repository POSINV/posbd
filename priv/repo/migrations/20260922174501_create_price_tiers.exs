defmodule Posbd.Repo.Migrations.CreatePriceTiers do
  use Ecto.Migration

  def change do
    create table(:price_tiers, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :business_id, references(:businesses, type: :binary_id, on_delete: :delete_all),
        null: false

      add :product_id, references(:products, type: :binary_id, on_delete: :delete_all)
      add :variant_id, references(:product_variants, type: :binary_id, on_delete: :delete_all)

      # Free-text so the business can call it "Wholesale", "Bulk Order",
      # "Festival Sale", etc. - the mechanism (quantity break + optional
      # date window) is the same regardless of what they call it.
      add :label, :string, null: false, default: "Custom"
      add :min_quantity, :integer, null: false, default: 1
      add :price, :decimal, null: false
      add :effective_from, :date
      add :effective_to, :date

      timestamps(type: :utc_datetime)
    end

    create constraint(:price_tiers, :exactly_one_of_product_or_variant,
             check: "(product_id IS NOT NULL)::int + (variant_id IS NOT NULL)::int = 1"
           )

    create index(:price_tiers, [:business_id])
    create index(:price_tiers, [:product_id])
    create index(:price_tiers, [:variant_id])
  end
end
