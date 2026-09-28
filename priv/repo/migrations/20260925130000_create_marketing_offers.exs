defmodule Posbd.Repo.Migrations.CreateMarketingOffers do
  use Ecto.Migration

  def change do
    create table(:offers, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :business_id, references(:businesses, type: :binary_id, on_delete: :delete_all),
        null: false

      add :name, :string, null: false
      add :code, :string
      add :discount_type, :string, null: false, default: "percentage"
      add :discount_value, :decimal, null: false
      add :starts_at, :utc_datetime
      add :ends_at, :utc_datetime
      add :min_purchase_amount, :decimal, null: false, default: 0
      add :eligible_segment, :string, null: false, default: "all"
      add :usage_limit_total, :integer
      add :usage_limit_per_customer, :integer
      add :status, :string, null: false, default: "active"
      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:offers, [:business_id, :status])
    create unique_index(:offers, [:business_id, :code], where: "code IS NOT NULL")

    create table(:offer_redemptions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :business_id, references(:businesses, type: :binary_id, on_delete: :delete_all),
        null: false

      add :offer_id, references(:offers, type: :binary_id, on_delete: :delete_all), null: false
      add :customer_id, references(:customers, type: :binary_id, on_delete: :nilify_all)
      add :invoice_id, references(:invoices, type: :binary_id, on_delete: :nilify_all)
      add :discount_amount, :decimal, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:offer_redemptions, [:offer_id])
    create index(:offer_redemptions, [:offer_id, :customer_id])
    create index(:offer_redemptions, [:business_id, :inserted_at])

    alter table(:invoices) do
      add :offer_id, references(:offers, type: :binary_id, on_delete: :nilify_all)
      add :offer_discount_amount, :decimal, null: false, default: 0
    end
  end
end
