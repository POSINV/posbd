defmodule Posbd.Repo.Migrations.AddInvoiceNumberingToBusinesses do
  use Ecto.Migration

  def change do
    alter table(:businesses) do
      add :invoice_prefix, :string, null: false, default: "INV-"
      # Atomically incremented (UPDATE ... SET next_invoice_number = next_invoice_number + 1
      # RETURNING ...) inside the invoice-creation transaction, so concurrent
      # billing requests can never collide on the same invoice number.
      add :next_invoice_number, :integer, null: false, default: 1
    end
  end
end
