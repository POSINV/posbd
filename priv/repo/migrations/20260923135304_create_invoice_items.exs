defmodule Posbd.Repo.Migrations.CreateInvoiceItems do
  use Ecto.Migration

  def change do
    create table(:invoice_items, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :invoice_id, references(:invoices, type: :binary_id, on_delete: :delete_all),
        null: false

      add :product_id, references(:products, type: :binary_id, on_delete: :nilify_all)
      add :variant_id, references(:product_variants, type: :binary_id, on_delete: :nilify_all)

      # Snapshotted at sale time so the invoice stays accurate even if the
      # product is later renamed, repriced, or deleted.
      add :name_snapshot, :string, null: false
      add :quantity, :integer, null: false
      add :unit_price, :decimal, null: false
      add :tax_rate, :decimal, null: false
      add :discount_amount, :decimal, null: false, default: 0
      add :tax_amount, :decimal, null: false
      add :line_total, :decimal, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create constraint(:invoice_items, :exactly_one_of_product_or_variant,
             check: "(product_id IS NOT NULL)::int + (variant_id IS NOT NULL)::int = 1"
           )

    create constraint(:invoice_items, :quantity_must_be_positive, check: "quantity > 0")

    create index(:invoice_items, [:invoice_id])
    create index(:invoice_items, [:product_id])
    create index(:invoice_items, [:variant_id])
  end
end
