defmodule Posbd.ReportsTest do
  use Posbd.DataCase, async: true

  alias Posbd.{Billing, Reports}

  import Posbd.BusinessesFixtures
  import Posbd.ProductsFixtures

  setup do
    %{scope: full_scope_fixture()}
  end

  defp seed_stock(scope, product, quantity) do
    Posbd.Inventory.record_movement(scope, product, %{
      "movement_type" => "opening_stock",
      "direction" => "in",
      "quantity" => quantity
    })
  end

  describe "sales_summary/3" do
    test "totals completed invoices within the date range and breaks down by payment method", %{
      scope: scope
    } do
      product = product_fixture(scope, selling_price: "100.00", tax_rate: "10")
      {:ok, _} = seed_stock(scope, product, 10)

      {:ok, _} =
        Billing.create_invoice(scope, %{
          "items" => [%{"product_id" => product.id, "quantity" => 1}],
          "payments" => [%{"method" => "cash", "amount" => "110.00"}]
        })

      {:ok, _} =
        Billing.create_invoice(scope, %{
          "items" => [%{"product_id" => product.id, "quantity" => 1}],
          "payments" => [%{"method" => "upi", "amount" => "110.00"}]
        })

      today = Date.utc_today()
      report = Reports.sales_summary(scope, today, today)

      assert report.invoice_count == 2
      assert Decimal.equal?(report.revenue, Decimal.new("220.00"))
      assert Decimal.equal?(report.tax, Decimal.new("20.00"))
      assert Decimal.equal?(report.average_sale, Decimal.new("110.00"))
      assert Decimal.equal?(report.by_payment_method["cash"], Decimal.new("110.00"))
      assert Decimal.equal?(report.by_payment_method["upi"], Decimal.new("110.00"))
    end

    test "excludes a cancelled invoice", %{scope: scope} do
      product = product_fixture(scope, selling_price: "50.00")
      {:ok, _} = seed_stock(scope, product, 5)

      {:ok, invoice} =
        Billing.create_invoice(scope, %{
          "items" => [%{"product_id" => product.id, "quantity" => 1}]
        })

      {:ok, _} = Billing.cancel_invoice(scope, invoice)

      today = Date.utc_today()
      report = Reports.sales_summary(scope, today, today)
      assert report.invoice_count == 0
      assert Decimal.equal?(report.revenue, Decimal.new(0))
    end

    test "excludes invoices outside the date range", %{scope: scope} do
      product = product_fixture(scope, selling_price: "50.00")
      {:ok, _} = seed_stock(scope, product, 5)

      {:ok, _} =
        Billing.create_invoice(scope, %{
          "items" => [%{"product_id" => product.id, "quantity" => 1}]
        })

      yesterday = Date.add(Date.utc_today(), -1)
      report = Reports.sales_summary(scope, yesterday, yesterday)
      assert report.invoice_count == 0
    end
  end

  describe "daily_sales/3" do
    test "returns one entry per day in range, zero-filling days with no sales", %{scope: scope} do
      product = product_fixture(scope, selling_price: "40.00")
      {:ok, _} = seed_stock(scope, product, 5)

      {:ok, _} =
        Billing.create_invoice(scope, %{
          "items" => [%{"product_id" => product.id, "quantity" => 1}]
        })

      today = Date.utc_today()
      from = Date.add(today, -2)
      days = Reports.daily_sales(scope, from, today)

      assert length(days) == 3
      assert Enum.map(days, & &1.date) == [from, Date.add(from, 1), today]

      today_entry = List.last(days)
      assert Decimal.equal?(today_entry.revenue, Decimal.new("40.00"))

      empty_entry = hd(days)
      assert Decimal.equal?(empty_entry.revenue, Decimal.new(0))
    end
  end

  describe "top_products/4" do
    test "ranks items by revenue", %{scope: scope} do
      cheap = product_fixture(scope, name: "Cheap Item", selling_price: "10.00")
      pricey = product_fixture(scope, name: "Pricey Item", selling_price: "500.00")
      {:ok, _} = seed_stock(scope, cheap, 10)
      {:ok, _} = seed_stock(scope, pricey, 10)

      {:ok, _} =
        Billing.create_invoice(scope, %{
          "items" => [
            %{"product_id" => cheap.id, "quantity" => 5},
            %{"product_id" => pricey.id, "quantity" => 1}
          ]
        })

      today = Date.utc_today()
      [top | _] = Reports.top_products(scope, today, today)
      assert top.name == "Pricey Item"
      assert Decimal.equal?(top.revenue, Decimal.new("500.00"))
    end
  end

  describe "stock_report/2" do
    test "lists products and variants with their stock, filterable to low stock only", %{
      scope: scope
    } do
      low = product_fixture(scope, name: "Low Stock Item", reorder_level: 10)
      {:ok, _} = seed_stock(scope, low, 2)

      healthy = product_fixture(scope, name: "Healthy Stock Item", reorder_level: 5)
      {:ok, _} = seed_stock(scope, healthy, 50)

      all_items = Reports.stock_report(scope)
      assert length(all_items) == 2

      low_only = Reports.stock_report(scope, low_stock_only: true)
      assert [%{name: "Low Stock Item"}] = low_only
    end
  end
end
