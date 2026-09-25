defmodule Posbd.Subscriptions.SubscriptionWebhookEvent do
  @moduledoc """
  One row per payment-provider webhook delivery (Phase 2 §11). The unique
  index on `{provider, provider_event_id}` is what makes processing
  idempotent - a retried/duplicate delivery hits the unique constraint
  and is treated as already-handled instead of being applied twice.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(received processed ignored failed)

  schema "subscription_webhook_events" do
    field :provider, :string
    field :event_type, :string
    field :provider_event_id, :string
    field :payload, :map, default: %{}
    field :status, :string, default: "received"
    field :processed_at, :utc_datetime
    field :error, :string

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def statuses, do: @statuses

  @fields ~w(provider event_type provider_event_id payload status processed_at error)a
  @required ~w(provider event_type provider_event_id)a

  def changeset(event, attrs) do
    event
    |> cast(attrs, @fields)
    |> validate_required(@required)
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint([:provider, :provider_event_id], error_key: :provider_event_id)
  end
end
