defmodule Posbd.Repo.Migrations.AddSourceToInvoices do
  use Ecto.Migration

  def change do
    alter table(:invoices) do
      add :source, :string, null: false, default: "pos"
    end

    create index(:invoices, [:business_id, :source])
  end
end
