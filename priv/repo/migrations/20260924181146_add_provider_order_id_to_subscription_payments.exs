defmodule Posbd.Repo.Migrations.AddProviderOrderIdToSubscriptionPayments do
  use Ecto.Migration

  def change do
    alter table(:subscription_payments) do
      # The Razorpay Order id, created *before* checkout - distinct from
      # provider_payment_id, which only exists once the customer actually
      # pays (Phase 2 §10 checkout flow).
      add :provider_order_id, :string
    end

    create index(:subscription_payments, [:provider_order_id])
  end
end
