defmodule Posbd.Imports.ImportLog do
  @moduledoc "A record of one bulk import run, kept for the migration history (AGENTS.md §27)."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @import_types ~w(products opening_stock historical_bills)

  schema "import_logs" do
    field :import_type, :string
    field :total_rows, :integer
    field :success_count, :integer
    field :error_count, :integer

    belongs_to :business, Posbd.Businesses.Business
    belongs_to :performed_by, Posbd.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def import_types, do: @import_types

  def changeset(log, attrs) do
    log
    |> cast(attrs, [
      :business_id,
      :performed_by_id,
      :import_type,
      :total_rows,
      :success_count,
      :error_count
    ])
    |> validate_required([:business_id, :import_type, :total_rows, :success_count, :error_count])
    |> validate_inclusion(:import_type, @import_types)
  end
end
