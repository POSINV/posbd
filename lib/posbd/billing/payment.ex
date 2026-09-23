defmodule Posbd.Billing.Payment do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @methods ~w(cash card upi credit other)

  schema "payments" do
    field :method, :string
    field :amount, :decimal
    field :reference, :string
    field :received_at, :utc_datetime_usec

    belongs_to :invoice, Posbd.Billing.Invoice
    belongs_to :recorded_by, Posbd.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def methods, do: @methods

  def build_changeset(payment, fields) do
    payment
    |> change(fields)
    |> validate_required([:invoice_id, :method, :amount, :received_at])
    |> validate_inclusion(:method, @methods)
    |> validate_number(:amount, greater_than: 0)
    |> check_constraint(:amount, name: :amount_must_be_positive)
  end
end
