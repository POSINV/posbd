defmodule Posbd.Subscriptions.Subscription do
  @moduledoc """
  The single current subscription record for a business (Phase 2 §5) - one
  row per business, continuously updated as it moves through its
  lifecycle. `status` stores only the small set of states that are
  actually *persisted* decisions; presentational states like "trial
  ending soon" or "renewal due" are derived at read time from the dates
  here (see `Posbd.Subscriptions.Lifecycle`) so they can never drift out
  of sync with a background job that hasn't run yet.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(trialing active past_due grace_period suspended cancelled)

  schema "subscriptions" do
    field :status, :string, default: "trialing"

    field :trial_started_at, :utc_datetime
    field :trial_ends_at, :utc_datetime

    field :current_period_start, :utc_datetime
    field :current_period_end, :utc_datetime

    field :cancel_at, :utc_datetime
    field :cancelled_at, :utc_datetime
    field :grace_period_ends_at, :utc_datetime

    belongs_to :business, Posbd.Businesses.Business
    belongs_to :plan, Posbd.Subscriptions.SubscriptionPlan

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  @fields ~w(business_id plan_id status trial_started_at trial_ends_at
             current_period_start current_period_end cancel_at cancelled_at
             grace_period_ends_at)a
  @required ~w(business_id status)a

  @doc "`business_id` is set explicitly by the context, never cast from client params."
  def changeset(subscription, attrs) do
    subscription
    |> cast(attrs, @fields)
    |> validate_required(@required)
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint(:business_id)
  end
end
