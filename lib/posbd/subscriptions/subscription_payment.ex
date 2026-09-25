defmodule Posbd.Subscriptions.SubscriptionPayment do
  @moduledoc """
  A record of money a business paid *us* for the platform (Phase 2 §12) -
  the SaaS subscription invoice/receipt. Completely separate from
  `Posbd.Billing.Payment`, which is money the business's own customer
  paid the business (Phase 2 §2 - never mix these two domains).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(pending paid failed refunded)

  schema "subscription_payments" do
    field :plan_name_snapshot, :string
    field :amount, :decimal
    field :currency, :string

    field :period_start, :utc_datetime
    field :period_end, :utc_datetime

    field :status, :string, default: "pending"
    field :payment_provider, :string
    field :provider_order_id, :string
    field :provider_payment_id, :string
    field :provider_reference, :string
    field :notes, :string
    field :paid_at, :utc_datetime

    belongs_to :business, Posbd.Businesses.Business
    belongs_to :subscription, Posbd.Subscriptions.Subscription
    belongs_to :plan, Posbd.Subscriptions.SubscriptionPlan
    belongs_to :recorded_by, Posbd.PlatformAdmins.PlatformAdmin

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  @fields ~w(business_id subscription_id plan_id plan_name_snapshot amount
             currency period_start period_end status payment_provider
             provider_order_id provider_payment_id provider_reference notes
             paid_at recorded_by_id)a
  @required ~w(business_id amount currency status)a

  def changeset(payment, attrs) do
    payment
    |> cast(attrs, @fields)
    |> validate_required(@required)
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:amount, greater_than: 0)
  end
end
