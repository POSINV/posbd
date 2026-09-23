defmodule Posbd.Billing.InvoiceItem do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "invoice_items" do
    field :name_snapshot, :string
    field :quantity, :integer
    field :unit_price, :decimal
    field :tax_rate, :decimal
    field :discount_amount, :decimal, default: Decimal.new(0)
    field :tax_amount, :decimal
    field :line_total, :decimal

    belongs_to :invoice, Posbd.Billing.Invoice
    belongs_to :product, Posbd.Products.Product
    belongs_to :variant, Posbd.Products.ProductVariant

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc "Every field is computed server-side by `Posbd.Billing` - see AGENTS.md §53."
  def build_changeset(item, fields) do
    item
    |> change(fields)
    |> validate_required([
      :invoice_id,
      :name_snapshot,
      :quantity,
      :unit_price,
      :tax_rate,
      :tax_amount,
      :line_total
    ])
    |> validate_number(:quantity, greater_than: 0)
    |> check_constraint(:base, name: :exactly_one_of_product_or_variant)
    |> check_constraint(:quantity, name: :quantity_must_be_positive)
  end
end
