defmodule Posbd.Products.VariantAttributeValue do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "variant_attribute_values" do
    belongs_to :variant, Posbd.Products.ProductVariant
    belongs_to :attribute, Posbd.Products.Attribute
    belongs_to :attribute_value, Posbd.Products.AttributeValue

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc "All three ids are set explicitly by the context, never cast from client params."
  def changeset(variant_attribute_value, %{
        variant_id: variant_id,
        attribute_id: attribute_id,
        attribute_value_id: attribute_value_id
      }) do
    variant_attribute_value
    |> change(
      variant_id: variant_id,
      attribute_id: attribute_id,
      attribute_value_id: attribute_value_id
    )
    |> unique_constraint([:variant_id, :attribute_id])
  end
end
