defmodule Posbd.Products.Attribute do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "attributes" do
    field :name, :string

    belongs_to :business, Posbd.Businesses.Business
    has_many :attribute_values, Posbd.Products.AttributeValue, preload_order: [asc: :position]

    timestamps(type: :utc_datetime)
  end

  def changeset(attribute, attrs) do
    attribute
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 80)
    |> unique_constraint([:business_id, :name])
  end
end
