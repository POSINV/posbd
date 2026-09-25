defmodule Posbd.Loyalty.LoyaltyProgram do
  @moduledoc """
  A business's loyalty configuration (Phase 2 §17-§18) - whether the
  program is enabled, how many points a bill earns, and what a point is
  worth when redeemed. One row per business. A business that has never
  configured this gets an un-persisted struct with `enabled: false` (see
  `Posbd.Loyalty.get_program/1`), so the rest of the codebase never has
  to special-case a missing row.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "loyalty_programs" do
    field :enabled, :boolean, default: false
    field :earn_amount_per_point, :decimal, default: Decimal.new("100")
    field :redeem_value_per_point, :decimal, default: Decimal.new("0.5")
    field :min_redeem_points, :integer, default: 100
    field :max_redemption_percentage, :decimal, default: Decimal.new("50")
    field :points_expiry_days, :integer
    field :birthday_bonus_points, :integer, default: 0

    belongs_to :business, Posbd.Businesses.Business

    timestamps(type: :utc_datetime)
  end

  @fields ~w(enabled earn_amount_per_point redeem_value_per_point min_redeem_points
             max_redemption_percentage points_expiry_days birthday_bonus_points)a

  @doc "`business_id` is set explicitly by `Posbd.Loyalty`, never cast from client params."
  def changeset(program, attrs) do
    program
    |> cast(attrs, @fields)
    |> validate_number(:earn_amount_per_point, greater_than: 0)
    |> validate_number(:redeem_value_per_point, greater_than: 0)
    |> validate_number(:min_redeem_points, greater_than_or_equal_to: 0)
    |> validate_number(:max_redemption_percentage, greater_than: 0, less_than_or_equal_to: 100)
    |> validate_number(:birthday_bonus_points, greater_than_or_equal_to: 0)
    |> validate_number(:points_expiry_days, greater_than: 0)
    |> unique_constraint(:business_id)
  end
end
