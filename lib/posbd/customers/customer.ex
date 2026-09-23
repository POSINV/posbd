defmodule Posbd.Customers.Customer do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "customers" do
    field :name, :string
    field :phone, :string
    field :email, :string
    field :address, :string
    field :notes, :string

    belongs_to :business, Posbd.Businesses.Business

    timestamps(type: :utc_datetime)
  end

  @fields ~w(name phone email address notes)a

  @doc "`business_id` is set explicitly by the context, never cast from client params."
  def changeset(customer, attrs) do
    customer
    |> cast(attrs, @fields)
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 160)
    |> validate_email()
  end

  defp validate_email(changeset) do
    case get_change(changeset, :email) do
      nil ->
        changeset

      "" ->
        changeset

      _ ->
        validate_format(changeset, :email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/,
          message: "must be a valid email"
        )
    end
  end
end
