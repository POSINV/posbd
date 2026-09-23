defmodule Posbd.Products.ProductVariant do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "product_variants" do
    field :sku, :string
    field :barcode, :string
    field :purchase_price, :decimal
    field :selling_price, :decimal
    field :mrp, :decimal
    field :tax_rate, :decimal, default: Decimal.new(0)
    field :position, :integer, default: 0
    field :active, :boolean, default: true

    # Maintained only by Posbd.Inventory alongside inventory_transactions -
    # never cast from client params (see AGENTS.md §33).
    field :stock_quantity, :integer, default: 0
    field :reorder_level, :integer, default: 0

    belongs_to :product, Posbd.Products.Product
    belongs_to :business, Posbd.Businesses.Business

    has_many :variant_attribute_values, Posbd.Products.VariantAttributeValue,
      foreign_key: :variant_id

    has_many :attribute_values, through: [:variant_attribute_values, :attribute_value]

    timestamps(type: :utc_datetime)
  end

  @fields ~w(sku barcode purchase_price selling_price mrp tax_rate position active reorder_level)a

  @doc """
  `product_id`/`business_id` are set explicitly by the context, never cast
  from client params.
  """
  def changeset(variant, attrs) do
    variant
    |> cast(attrs, @fields)
    |> validate_number(:purchase_price, greater_than_or_equal_to: 0)
    |> validate_number(:selling_price, greater_than_or_equal_to: 0)
    |> validate_number(:mrp, greater_than_or_equal_to: 0)
    |> validate_number(:tax_rate, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_number(:reorder_level, greater_than_or_equal_to: 0)
    |> unique_constraint([:business_id, :sku],
      name: :product_variants_business_id_sku_index,
      error_key: :sku
    )
    |> unique_constraint([:business_id, :barcode],
      name: :product_variants_business_id_barcode_index,
      error_key: :barcode
    )
  end
end
