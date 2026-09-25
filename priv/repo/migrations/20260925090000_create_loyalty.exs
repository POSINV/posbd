defmodule Posbd.Repo.Migrations.CreateLoyalty do
  use Ecto.Migration

  def change do
    create table(:loyalty_programs, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :business_id, references(:businesses, type: :binary_id, on_delete: :delete_all),
        null: false

      add :enabled, :boolean, null: false, default: false
      add :earn_amount_per_point, :decimal, null: false, default: 100.0
      add :redeem_value_per_point, :decimal, null: false, default: 0.5
      add :min_redeem_points, :integer, null: false, default: 100
      add :max_redemption_percentage, :decimal, null: false, default: 50.0
      add :points_expiry_days, :integer
      add :birthday_bonus_points, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:loyalty_programs, [:business_id])

    create table(:loyalty_ledger_entries, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :business_id, references(:businesses, type: :binary_id, on_delete: :delete_all),
        null: false

      add :customer_id, references(:customers, type: :binary_id, on_delete: :delete_all),
        null: false

      add :invoice_id, references(:invoices, type: :binary_id, on_delete: :nilify_all)
      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :entry_type, :string, null: false
      add :points, :integer, null: false
      add :balance_after, :integer, null: false
      add :description, :string

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:loyalty_ledger_entries, [:business_id, :customer_id, :inserted_at])
    create index(:loyalty_ledger_entries, [:invoice_id])

    alter table(:customers) do
      add :loyalty_points_balance, :integer, null: false, default: 0
    end

    create constraint(:customers, :loyalty_balance_non_negative,
             check: "loyalty_points_balance >= 0"
           )

    alter table(:invoices) do
      add :loyalty_points_redeemed, :integer, null: false, default: 0
      add :loyalty_points_earned, :integer, null: false, default: 0
      add :loyalty_discount_amount, :decimal, null: false, default: 0
    end
  end
end
