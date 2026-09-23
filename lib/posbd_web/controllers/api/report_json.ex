defmodule PosbdWeb.Api.ReportJSON do
  alias PosbdWeb.Api.ProductJSON

  def sales_summary(%{
        from: from,
        to: to,
        revenue: revenue,
        tax: tax,
        discount: discount,
        invoice_count: invoice_count,
        average_sale: average_sale,
        by_payment_method: by_payment_method
      }) do
    %{
      data: %{
        from: from,
        to: to,
        revenue: ProductJSON.money(revenue),
        tax: ProductJSON.money(tax),
        discount: ProductJSON.money(discount),
        invoice_count: invoice_count,
        average_sale: ProductJSON.money(average_sale),
        by_payment_method: Map.new(by_payment_method, fn {k, v} -> {k, ProductJSON.money(v)} end)
      }
    }
  end

  def daily_sales(%{days: days}) do
    %{data: Enum.map(days, fn d -> %{date: d.date, revenue: ProductJSON.money(d.revenue)} end)}
  end

  def top_products(%{products: products}) do
    %{
      data:
        Enum.map(products, fn p ->
          %{name: p.name, quantity_sold: p.quantity_sold, revenue: ProductJSON.money(p.revenue)}
        end)
    }
  end

  def stock(%{items: items}) do
    %{
      data:
        Enum.map(items, fn i ->
          %{
            id: i.id,
            name: i.name,
            sku: i.sku,
            stock_quantity: i.stock_quantity,
            reorder_level: i.reorder_level,
            low_stock: i.stock_quantity <= i.reorder_level
          }
        end)
    }
  end
end
