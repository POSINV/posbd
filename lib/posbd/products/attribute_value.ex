defmodule Posbd.Products.AttributeValue do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "attribute_values" do
    field :value, :string
    field :position, :integer, default: 0

    belongs_to :attribute, Posbd.Products.Attribute

    timestamps(type: :utc_datetime)
  end

  def changeset(attribute_value, attrs) do
    attribute_value
    |> cast(attrs, [:value, :position])
    |> validate_required([:value])
    |> validate_length(:value, min: 1, max: 80)
    |> unique_constraint([:attribute_id, :value])
  end
end
