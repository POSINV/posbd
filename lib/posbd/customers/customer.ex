defmodule Posbd.Customers.Customer do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @customer_types ~w(individual business)

  schema "customers" do
    field :name, :string
    field :phone, :string
    field :email, :string
    field :address, :string
    field :notes, :string
    field :date_of_birth, :date
    field :preferred_language, :string
    field :customer_type, :string, default: "individual"
    field :accepts_transactional_messages, :boolean, default: true
    field :accepts_promotional_messages, :boolean, default: false

    belongs_to :business, Posbd.Businesses.Business

    timestamps(type: :utc_datetime)
  end

  def customer_types, do: @customer_types

  @fields ~w(name phone email address notes date_of_birth preferred_language
             customer_type accepts_transactional_messages accepts_promotional_messages)a

  @doc "`business_id` is set explicitly by the context, never cast from client params."
  def changeset(customer, attrs) do
    customer
    |> cast(attrs, @fields)
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 160)
    |> validate_inclusion(:customer_type, @customer_types)
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
