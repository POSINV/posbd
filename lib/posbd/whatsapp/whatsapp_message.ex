defmodule Posbd.Whatsapp.WhatsappMessage do
  @moduledoc """
  One row per WhatsApp send attempt (Phase 2 §27 - message history with
  sent/delivered/read/failed tracking). Created eagerly with `status:
  "queued"` the moment a send is decided, *before* the background job
  actually calls the provider - so message history is visible
  immediately, and the row is later updated in place as the provider
  webhook reports delivery/read/failure (see `Posbd.Whatsapp.SendMessageWorker`
  and the webhook handler), unlike the fully append-only ledgers
  elsewhere in the codebase.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @kinds ~w(transactional promotional)
  @statuses ~w(queued sent delivered read failed)

  schema "whatsapp_messages" do
    field :kind, :string
    field :phone, :string
    field :body, :string
    field :status, :string, default: "queued"
    field :provider_message_id, :string
    field :error_message, :string
    field :sent_at, :utc_datetime
    field :delivered_at, :utc_datetime
    field :read_at, :utc_datetime

    belongs_to :business, Posbd.Businesses.Business
    belongs_to :customer, Posbd.Customers.Customer
    belongs_to :template, Posbd.Whatsapp.WhatsappTemplate
    belongs_to :campaign, Posbd.Whatsapp.WhatsappCampaign

    timestamps(type: :utc_datetime_usec)
  end

  def kinds, do: @kinds
  def statuses, do: @statuses

  @fields ~w(kind phone body business_id customer_id template_id campaign_id)a
  @required ~w(kind phone body business_id customer_id)a

  @doc "`business_id` is set explicitly by `Posbd.Whatsapp`, never cast from client params."
  def changeset(message, attrs) do
    message
    |> cast(attrs, @fields)
    |> validate_required(@required)
    |> validate_inclusion(:kind, @kinds)
  end

  def sent_changeset(message, provider_message_id) do
    change(message,
      status: "sent",
      provider_message_id: provider_message_id,
      sent_at: DateTime.utc_now() |> DateTime.truncate(:second)
    )
  end

  def failed_changeset(message, error_message) do
    change(message, status: "failed", error_message: error_message)
  end

  def status_update_changeset(message, "delivered") do
    change(message,
      status: "delivered",
      delivered_at: DateTime.utc_now() |> DateTime.truncate(:second)
    )
  end

  def status_update_changeset(message, "read") do
    change(message,
      status: "read",
      read_at: DateTime.utc_now() |> DateTime.truncate(:second),
      delivered_at: message.delivered_at || DateTime.utc_now() |> DateTime.truncate(:second)
    )
  end

  def status_update_changeset(message, "failed") do
    change(message, status: "failed")
  end

  def status_update_changeset(message, _status), do: change(message)
end
