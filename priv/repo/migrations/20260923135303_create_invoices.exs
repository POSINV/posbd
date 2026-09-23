defmodule Posbd.Repo.Migrations.CreateInvoices do
  use Ecto.Migration

  def change do
    create table(:invoices, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :business_id, references(:businesses, type: :binary_id, on_delete: :delete_all),
        null: false

      add :customer_id, references(:customers, type: :binary_id, on_delete: :nilify_all)
      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      add :invoice_number, :string, null: false
      add :status, :string, null: false, default: "completed"
      add :payment_status, :string, null: false, default: "unpaid"
      add :currency, :string, null: false

      add :subtotal, :decimal, null: false
      add :discount_amount, :decimal, null: false, default: 0
      add :tax_amount, :decimal, null: false
      add :total_amount, :decimal, null: false
      add :amount_paid, :decimal, null: false, default: 0

      # Lets the client safely retry a POST /invoices after a timeout/double
      # click without risking a duplicate invoice (AGENTS.md §54).
      add :idempotency_key, :string

      add :notes, :string
      add :issued_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:invoices, [:business_id, :invoice_number])

    create unique_index(:invoices, [:business_id, :idempotency_key],
             where: "idempotency_key IS NOT NULL"
           )

    create index(:invoices, [:business_id, :issued_at])
    create index(:invoices, [:customer_id])
  end
end
