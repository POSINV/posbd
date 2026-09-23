defmodule Posbd.Repo.Migrations.AddInvoiceHeaderFieldsToBusinesses do
  use Ecto.Migration

  def change do
    alter table(:businesses) do
      add :address, :string
      add :phone, :string
      add :email, :string
      add :tax_number, :string
      add :invoice_footer, :string
      add :invoice_terms, :string
    end
  end
end
