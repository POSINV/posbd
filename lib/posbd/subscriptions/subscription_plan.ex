defmodule Posbd.Subscriptions.SubscriptionPlan do
  @moduledoc """
  A purchasable plan (Phase 2 §6/§7). `features` is a plain data map
  (`%{"loyalty" => true, "max_users" => 5}`) rather than a join table, so
  new plans/limits are just data - no schema change, no deploy - matching
  the same philosophy as `Posbd.Businesses.Roles`'s permission lists.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @billing_periods ~w(monthly yearly)

  schema "subscription_plans" do
    field :name, :string
    field :slug, :string
    field :description, :string
    field :price, :decimal
    field :currency, :string, default: "INR"
    field :billing_period, :string, default: "yearly"
    field :features, :map, default: %{}
    field :trial_days, :integer
    field :is_active, :boolean, default: true
    field :position, :integer, default: 0

    timestamps(type: :utc_datetime)
  end

  def billing_periods, do: @billing_periods

  @fields ~w(name slug description price currency billing_period features trial_days is_active position)a
  @required ~w(name slug price currency billing_period)a

  def changeset(plan, attrs) do
    plan
    |> cast(attrs, @fields)
    |> validate_required(@required)
    |> validate_inclusion(:billing_period, @billing_periods)
    |> validate_number(:price, greater_than_or_equal_to: 0)
    |> validate_length(:slug, min: 1, max: 60)
    |> unsafe_validate_unique(:slug, Posbd.Repo)
    |> unique_constraint(:slug)
  end

  @doc "True if the plan grants `feature_key` (e.g. `\"loyalty\"`, `\"whatsapp\"`)."
  def has_feature?(%__MODULE__{features: features}, feature_key) do
    case Map.get(features, feature_key) do
      nil -> false
      false -> false
      _ -> true
    end
  end

  def has_feature?(nil, _feature_key), do: false
end
