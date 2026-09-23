defmodule PosbdWeb.Api.ProductJSON do
  alias Posbd.Products.Product
  alias PosbdWeb.Api.ProductVariantJSON

  def index(%{data: products, page: page, page_size: page_size, total_count: total_count}) do
    %{
      data: Enum.map(products, &product_json/1),
      pagination: %{page: page, page_size: page_size, total_count: total_count}
    }
  end

  def show(%{product: product}), do: %{data: product_json(product)}

  defp product_json(%Product{} = product) do
    %{
      id: product.id,
      name: product.name,
      description: product.description,
      brand: product.brand,
      unit: product.unit,
      status: product.status,
      has_variants: product.has_variants,
      category_id: product.category_id,
      sku: product.sku,
      barcode: product.barcode,
      purchase_price: money(product.purchase_price),
      selling_price: money(product.selling_price),
      mrp: money(product.mrp),
      tax_rate: money(product.tax_rate),
      stock_quantity: product.stock_quantity,
      reorder_level: product.reorder_level,
      low_stock: not product.has_variants and product.stock_quantity <= product.reorder_level,
      variants:
        case product.variants do
          %Ecto.Association.NotLoaded{} -> []
          variants -> Enum.map(variants, &ProductVariantJSON.variant_json/1)
        end,
      inserted_at: product.inserted_at
    }
  end

  def money(nil), do: nil
  def money(%Decimal{} = decimal), do: Decimal.to_string(decimal)
end
