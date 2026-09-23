defmodule Posbd.Repo.Migrations.AddStockFieldsToProducts do
  use Ecto.Migration

  def change do
    alter table(:products) do
      # Cached read model kept in sync with inventory_transactions inside
      # the same DB transaction as every movement - the ledger is the
      # source of truth, this column just avoids summing it on every read.
      add :stock_quantity, :integer, null: false, default: 0
      add :reorder_level, :integer, null: false, default: 0
    end

    alter table(:product_variants) do
      add :stock_quantity, :integer, null: false, default: 0
      add :reorder_level, :integer, null: false, default: 0
    end
  end
end
