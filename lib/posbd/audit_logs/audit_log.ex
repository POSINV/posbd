defmodule Posbd.AuditLogs.AuditLog do
  @moduledoc """
  One row per auditable action (see AGENTS.md §26) - who did what, to
  which entity, when, and with what relevant change information. Rows are
  append-only: nothing here is ever updated or deleted after insert.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "audit_logs" do
    field :action, :string
    field :entity_type, :string
    field :entity_id, :binary_id
    field :metadata, :map, default: %{}

    belongs_to :business, Posbd.Businesses.Business
    belongs_to :user, Posbd.Accounts.User

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @fields ~w(business_id user_id action entity_type entity_id metadata)a
  @required ~w(business_id action entity_type)a

  @doc """
  `business_id` and `user_id` are set explicitly by `Posbd.AuditLogs.record/5`,
  never cast from client params.
  """
  def changeset(log, attrs) do
    log
    |> cast(attrs, @fields)
    |> validate_required(@required)
  end
end
