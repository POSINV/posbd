defmodule Posbd.Marketing.Offer do
  @moduledoc """
  A discount promotion (Phase 2 §21/§30) - either code-based (the
  customer/cashier must enter `code` at billing) or automatic (`code` is
  `nil`, and it's applied to any eligible bill without asking). Eligible
  products/categories aren't modeled separately - `min_purchase_amount`
  and `eligible_segment` (reusing the same segments `Posbd.Customers`
  already computes) cover the common cases for an MVP without a second
  targeting system to keep in sync with the first.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @discount_types ~w(percentage fixed_amount)
  @statuses ~w(active inactive)
  @eligible_segments ~w(all vip high_value regular new inactive)

  schema "offers" do
    field :name, :string
    field :code, :string
    field :discount_type, :string, default: "percentage"
    field :discount_value, :decimal
    field :starts_at, :utc_datetime
    field :ends_at, :utc_datetime
    field :min_purchase_amount, :decimal, default: Decimal.new(0)
    field :eligible_segment, :string, default: "all"
    field :usage_limit_total, :integer
    field :usage_limit_per_customer, :integer
    field :status, :string, default: "active"

    belongs_to :business, Posbd.Businesses.Business
    belongs_to :created_by, Posbd.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def discount_types, do: @discount_types
  def statuses, do: @statuses
  def eligible_segments, do: @eligible_segments

  @fields ~w(name code discount_type discount_value starts_at ends_at min_purchase_amount
             eligible_segment usage_limit_total usage_limit_per_customer status)a
  @required ~w(name discount_type discount_value business_id)a

  @doc "`business_id`/`created_by_id` are set explicitly by `Posbd.Marketing`, never cast from client params."
  def changeset(offer, attrs) do
    offer
    |> cast(attrs, @fields)
    |> validate_required(@required)
    |> validate_length(:name, min: 1, max: 160)
    |> validate_inclusion(:discount_type, @discount_types)
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:eligible_segment, @eligible_segments)
    |> validate_number(:discount_value, greater_than: 0)
    |> validate_number(:min_purchase_amount, greater_than_or_equal_to: 0)
    |> validate_number(:usage_limit_total, greater_than: 0)
    |> validate_number(:usage_limit_per_customer, greater_than: 0)
    |> validate_percentage()
    |> update_change(:code, &normalize_code/1)
    |> unique_constraint([:business_id, :code], error_key: :code)
  end

  defp validate_percentage(changeset) do
    if get_field(changeset, :discount_type) == "percentage" do
      validate_number(changeset, :discount_value, less_than_or_equal_to: 100)
    else
      changeset
    end
  end

  defp normalize_code(nil), do: nil
  defp normalize_code(""), do: nil
  defp normalize_code(code), do: code |> String.trim() |> String.upcase()
end
