defmodule Posbd.Loyalty.LoyaltyLedgerEntry do
  @moduledoc """
  One row per loyalty points movement (Phase 2 §19-§20) - earned,
  redeemed, expired, manually adjusted, or a birthday/promotional bonus.
  Rows are append-only, mirroring `Posbd.Inventory.InventoryTransaction`:
  nothing here is ever updated or deleted after insert, since it's the
  audit trail behind the cached `loyalty_points_balance` on Customer.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @entry_types ~w(earn redeem expire adjustment bonus)

  schema "loyalty_ledger_entries" do
    field :entry_type, :string
    field :points, :integer
    field :balance_after, :integer
    field :description, :string

    belongs_to :business, Posbd.Businesses.Business
    belongs_to :customer, Posbd.Customers.Customer
    belongs_to :invoice, Posbd.Billing.Invoice
    belongs_to :created_by, Posbd.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def entry_types, do: @entry_types

  @fields ~w(entry_type points balance_after description business_id customer_id
             invoice_id created_by_id)a
  @required ~w(entry_type points balance_after business_id customer_id)a

  @doc """
  `business_id` and `balance_after` are computed and set explicitly by
  `Posbd.Loyalty.record_entry/2`, never cast from raw client params.
  """
  def changeset(entry, attrs) do
    entry
    |> cast(attrs, @fields)
    |> validate_required(@required)
    |> validate_inclusion(:entry_type, @entry_types)
    |> validate_number(:points, not_equal_to: 0)
  end
end
