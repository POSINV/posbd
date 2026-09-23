defmodule Posbd.Products.Product do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(active inactive draft)

  schema "products" do
    field :name, :string
    field :description, :string
    field :brand, :string
    field :unit, :string, default: "pcs"
    field :status, :string, default: "active"
    field :has_variants, :boolean, default: false

    # Only used when has_variants is false.
    field :sku, :string
    field :barcode, :string
    field :purchase_price, :decimal
    field :selling_price, :decimal
    field :mrp, :decimal
    field :tax_rate, :decimal, default: Decimal.new(0)

    # Maintained only by Posbd.Inventory alongside inventory_transactions -
    # never cast from client params (see AGENTS.md §33).
    field :stock_quantity, :integer, default: 0
    field :reorder_level, :integer, default: 0

    belongs_to :business, Posbd.Businesses.Business
    belongs_to :category, Posbd.Categories.Category
    has_many :variants, Posbd.Products.ProductVariant, preload_order: [asc: :position]

    timestamps(type: :utc_datetime)
  end

  @fields ~w(name description brand unit status has_variants category_id
             sku barcode purchase_price selling_price mrp tax_rate reorder_level)a

  @doc "`business_id` is set explicitly by the context, never cast from client params."
  def changeset(product, attrs) do
    product
    |> cast(attrs, @fields)
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 200)
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:purchase_price, greater_than_or_equal_to: 0)
    |> validate_number(:selling_price, greater_than_or_equal_to: 0)
    |> validate_number(:mrp, greater_than_or_equal_to: 0)
    |> validate_number(:tax_rate, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_number(:reorder_level, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:category_id)
    |> unique_constraint([:business_id, :sku],
      name: :products_business_id_sku_index,
      error_key: :sku
    )
  end
end
