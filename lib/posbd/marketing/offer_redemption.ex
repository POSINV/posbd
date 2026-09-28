defmodule Posbd.Marketing.OfferRedemption do
  @moduledoc """
  One row per time an offer was actually applied to a bill (Phase 2
  §21/§34) - append-only, the audit trail (and usage-limit source of
  truth) behind `Posbd.Marketing.Offer`'s usage limits. Counts are always
  derived fresh from this table (mirrors `Posbd.Customers`' own "derived,
  not ledgered" purchase stats), never cached on the offer itself.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "offer_redemptions" do
    field :discount_amount, :decimal

    belongs_to :business, Posbd.Businesses.Business
    belongs_to :offer, Posbd.Marketing.Offer
    belongs_to :customer, Posbd.Customers.Customer
    belongs_to :invoice, Posbd.Billing.Invoice

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @fields ~w(discount_amount business_id offer_id customer_id invoice_id)a
  @required ~w(discount_amount business_id offer_id)a

  @doc "`business_id` is set explicitly by `Posbd.Marketing.record_redemption/4`, never cast from client params."
  def changeset(redemption, attrs) do
    redemption
    |> cast(attrs, @fields)
    |> validate_required(@required)
  end
end
