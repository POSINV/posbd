defmodule Posbd.Whatsapp.WhatsappTemplate do
  @moduledoc """
  A message template a business wants to send over WhatsApp (Phase 2
  §24) - multi-language, with `{{1}}`, `{{2}}`, ... variable
  placeholders, and its own approval workflow: a business creates one in
  `pending_approval`, and a platform admin approves it (recording the
  name it was actually registered under with Meta) or rejects it with a
  reason, mirroring how Meta itself gatekeeps template content before
  it can be used for real sends.

  `purpose` is how the rest of the app finds "the template to use for
  this event" (a bill was created, a payment recorded, points earned, a
  promotional offer) without the caller needing to know which specific
  template a business configured for it.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @purposes ~w(billing payment loyalty offer custom)
  @categories ~w(utility marketing authentication)
  @statuses ~w(draft pending_approval approved rejected)

  schema "whatsapp_templates" do
    field :name, :string
    field :purpose, :string, default: "custom"
    field :category, :string, default: "utility"
    field :language, :string, default: "en"
    field :body, :string
    field :variable_count, :integer, default: 0
    field :status, :string, default: "pending_approval"
    field :provider_template_name, :string
    field :rejected_reason, :string
    field :reviewed_at, :utc_datetime

    belongs_to :business, Posbd.Businesses.Business
    belongs_to :reviewed_by, Posbd.PlatformAdmins.PlatformAdmin

    timestamps(type: :utc_datetime_usec)
  end

  def purposes, do: @purposes
  def categories, do: @categories
  def statuses, do: @statuses

  @fields ~w(name purpose category language body)a
  @required ~w(business_id name category language body)a

  @doc """
  `business_id` is set explicitly by `Posbd.Whatsapp`, never cast from
  client params. Any content edit resets the template to
  `pending_approval` (via `resubmit/1`) - a client can never set its own
  `status`, `provider_template_name`, or review fields.
  """
  def changeset(template, attrs) do
    template
    |> cast(attrs, @fields)
    |> validate_required(@required)
    |> validate_length(:name, min: 1, max: 160)
    |> validate_length(:body, min: 1, max: 1024)
    |> validate_inclusion(:purpose, @purposes)
    |> validate_inclusion(:category, @categories)
    |> put_variable_count()
  end

  defp put_variable_count(changeset) do
    case get_field(changeset, :body) do
      nil -> changeset
      body -> put_change(changeset, :variable_count, count_variables(body))
    end
  end

  defp count_variables(body) do
    ~r/\{\{(\d+)\}\}/
    |> Regex.scan(body)
    |> Enum.map(fn [_, n] -> String.to_integer(n) end)
    |> Enum.max(fn -> 0 end)
  end

  @doc "Business-side create/update changeset always (re)starts the approval workflow."
  def submit_changeset(template, attrs) do
    template |> changeset(attrs) |> put_change(:status, "pending_approval")
  end

  @doc "Platform-admin action: approves the template under the name actually registered with Meta."
  def approve_changeset(template, provider_template_name, admin) do
    template
    |> change(
      status: "approved",
      provider_template_name: provider_template_name,
      rejected_reason: nil,
      reviewed_by_id: admin.id,
      reviewed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    )
    |> validate_required([:provider_template_name])
  end

  @doc "Platform-admin action: rejects the template with a reason the business can act on."
  def reject_changeset(template, reason, admin) do
    template
    |> change(
      status: "rejected",
      rejected_reason: reason,
      reviewed_by_id: admin.id,
      reviewed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    )
    |> validate_required([:rejected_reason])
  end
end
