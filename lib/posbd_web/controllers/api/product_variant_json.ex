defmodule PosbdWeb.Api.ProductVariantJSON do
  alias Posbd.Products.ProductVariant
  alias PosbdWeb.Api.ProductJSON

  def show(%{variant: variant}), do: %{data: variant_json(variant)}

  def variant_json(%ProductVariant{} = variant) do
    %{
      id: variant.id,
      product_id: variant.product_id,
      sku: variant.sku,
      barcode: variant.barcode,
      purchase_price: ProductJSON.money(variant.purchase_price),
      selling_price: ProductJSON.money(variant.selling_price),
      mrp: ProductJSON.money(variant.mrp),
      tax_rate: ProductJSON.money(variant.tax_rate),
      position: variant.position,
      active: variant.active,
      stock_quantity: variant.stock_quantity,
      reorder_level: variant.reorder_level,
      low_stock: variant.stock_quantity <= variant.reorder_level,
      attributes: attributes_map(variant)
    }
  end

  defp attributes_map(%ProductVariant{attribute_values: %Ecto.Association.NotLoaded{}}), do: %{}

  defp attributes_map(%ProductVariant{attribute_values: attribute_values}) do
    Map.new(attribute_values, fn av -> {av.attribute.name, av.value} end)
  end
end
