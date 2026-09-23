defmodule Posbd.Repo.Migrations.CreatePayments do
  use Ecto.Migration

  def change do
    create table(:payments, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :invoice_id, references(:invoices, type: :binary_id, on_delete: :delete_all),
        null: false

      add :recorded_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      add :method, :string, null: false
      add :amount, :decimal, null: false
      add :reference, :string
      add :received_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create constraint(:payments, :amount_must_be_positive, check: "amount > 0")
    create index(:payments, [:invoice_id])
  end
end
