defmodule Posbd.Repo.Migrations.CreateSubscriptionDomain do
  use Ecto.Migration

  def change do
    create table(:subscription_plans, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :slug, :string, null: false
      add :description, :string
      add :price, :decimal, null: false
      add :currency, :string, null: false, default: "INR"
      add :billing_period, :string, null: false, default: "yearly"
      # A plain data map of feature_key => true/limit, e.g.
      # %{"loyalty" => true, "whatsapp" => true, "max_users" => 5} - kept
      # as data (not a features table) so plans stay easy to add/tune
      # without a schema change, matching the platform's existing
      # Roles/permissions convention (see Posbd.Businesses.Roles).
      add :features, :map, null: false, default: %{}
      add :trial_days, :integer
      add :is_active, :boolean, null: false, default: true
      add :position, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:subscription_plans, [:slug])

    create table(:subscriptions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :business_id, references(:businesses, type: :binary_id, on_delete: :delete_all),
        null: false

      add :plan_id, references(:subscription_plans, type: :binary_id, on_delete: :nilify_all)

      # See Posbd.Subscriptions.Lifecycle for the full state machine.
      add :status, :string, null: false, default: "trialing"

      add :trial_started_at, :utc_datetime
      add :trial_ends_at, :utc_datetime

      add :current_period_start, :utc_datetime
      add :current_period_end, :utc_datetime

      add :cancel_at, :utc_datetime
      add :cancelled_at, :utc_datetime
      add :grace_period_ends_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:subscriptions, [:business_id])
    create index(:subscriptions, [:status])

    create table(:subscription_payments, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :business_id, references(:businesses, type: :binary_id, on_delete: :delete_all),
        null: false

      add :subscription_id, references(:subscriptions, type: :binary_id, on_delete: :nilify_all)
      add :plan_id, references(:subscription_plans, type: :binary_id, on_delete: :nilify_all)

      # Snapshotted so a payment record stays accurate even if the plan is
      # later renamed/repriced (same reasoning as InvoiceItem.name_snapshot).
      add :plan_name_snapshot, :string
      add :amount, :decimal, null: false
      add :currency, :string, null: false

      add :period_start, :utc_datetime
      add :period_end, :utc_datetime

      add :status, :string, null: false, default: "pending"
      add :payment_provider, :string
      add :provider_payment_id, :string
      add :provider_reference, :string
      add :notes, :string
      add :paid_at, :utc_datetime

      add :recorded_by_id, references(:platform_admins, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:subscription_payments, [:business_id])
    create index(:subscription_payments, [:subscription_id])

    create table(:subscription_webhook_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :provider, :string, null: false
      add :event_type, :string, null: false
      add :provider_event_id, :string, null: false
      add :payload, :map, null: false, default: %{}
      add :status, :string, null: false, default: "received"
      add :processed_at, :utc_datetime
      add :error, :string

      timestamps(type: :utc_datetime, updated_at: false)
    end

    # The idempotency guarantee from AGENTS.md Phase 2 §11 - the same
    # provider event id can never be recorded (and therefore processed) twice.
    create unique_index(:subscription_webhook_events, [:provider, :provider_event_id])
  end
end
