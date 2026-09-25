defmodule Posbd.Whatsapp.WhatsappCampaign do
  @moduledoc """
  A promotional WhatsApp send to a segment of customers (Phase 2 §28) -
  audience selection reuses the customer segments already computed by
  `Posbd.Customers.segment/2` (vip/high_value/regular/new/inactive, or
  `"all"`), so there's a single definition of what each segment means
  across the whole platform. Sending itself always goes through a
  background job (`Posbd.Whatsapp.CampaignDispatchWorker`, Phase 2 §35) -
  never inline in the request that creates or schedules the campaign.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @audience_segments ~w(all vip high_value regular new inactive)
  @statuses ~w(draft scheduled sent cancelled)

  schema "whatsapp_campaigns" do
    field :name, :string
    field :audience_segment, :string, default: "all"
    field :status, :string, default: "draft"
    field :scheduled_at, :utc_datetime

    belongs_to :business, Posbd.Businesses.Business
    belongs_to :template, Posbd.Whatsapp.WhatsappTemplate
    belongs_to :created_by, Posbd.Accounts.User

    timestamps(type: :utc_datetime_usec)
  end

  def audience_segments, do: @audience_segments
  def statuses, do: @statuses

  @fields ~w(name audience_segment scheduled_at business_id template_id created_by_id)a
  @required ~w(name audience_segment business_id template_id created_by_id)a

  @doc "`business_id`/`created_by_id`/`status` are set explicitly by `Posbd.Whatsapp`, never cast from client params."
  def changeset(campaign, attrs) do
    campaign
    |> cast(attrs, @fields)
    |> validate_required(@required)
    |> validate_inclusion(:audience_segment, @audience_segments)
    |> foreign_key_constraint(:template_id)
  end

  def status_changeset(campaign, status) do
    campaign |> change(status: status) |> validate_inclusion(:status, @statuses)
  end
end
