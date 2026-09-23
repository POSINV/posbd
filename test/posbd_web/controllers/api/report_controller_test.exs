defmodule PosbdWeb.Api.ReportControllerTest do
  use PosbdWeb.ConnCase, async: true

  import Posbd.BusinessesFixtures
  import Posbd.ProductsFixtures

  setup %{conn: conn} do
    scope = full_scope_fixture()

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{Posbd.Accounts.create_api_token(scope.user)}")
      |> put_req_header("x-business-id", scope.business.id)

    %{conn: conn, scope: scope}
  end

  defp seed_stock(scope, product, quantity) do
    Posbd.Inventory.record_movement(scope, product, %{
      "movement_type" => "opening_stock",
      "direction" => "in",
      "quantity" => quantity
    })
  end

  test "GET /reports/sales_summary totals today's completed sales", %{conn: conn, scope: scope} do
    product = product_fixture(scope, selling_price: "100.00", tax_rate: "0")
    {:ok, _} = seed_stock(scope, product, 5)

    Posbd.Billing.create_invoice(scope, %{
      "items" => [%{"product_id" => product.id, "quantity" => 1}]
    })

    today = Date.to_iso8601(Date.utc_today())
    conn = get(conn, ~p"/api/v1/reports/sales_summary?from=#{today}&to=#{today}")

    assert %{"data" => %{"revenue" => "100.00", "invoice_count" => 1}} = json_response(conn, 200)
  end

  test "GET /reports/sales_summary requires from/to", %{conn: conn} do
    conn = get(conn, ~p"/api/v1/reports/sales_summary")
    assert %{"error" => %{"message" => _}} = json_response(conn, 422)
  end

  test "GET /reports/top_products ranks by revenue", %{conn: conn, scope: scope} do
    product = product_fixture(scope, name: "Best Seller", selling_price: "50.00")
    {:ok, _} = seed_stock(scope, product, 5)

    Posbd.Billing.create_invoice(scope, %{
      "items" => [%{"product_id" => product.id, "quantity" => 2}]
    })

    today = Date.to_iso8601(Date.utc_today())
    conn = get(conn, ~p"/api/v1/reports/top_products?from=#{today}&to=#{today}")

    assert %{"data" => [%{"name" => "Best Seller", "quantity_sold" => 2}]} =
             json_response(conn, 200)
  end

  test "GET /reports/stock lists current stock and can filter to low stock", %{
    conn: conn,
    scope: scope
  } do
    product = product_fixture(scope, name: "Almost Out", reorder_level: 10)
    {:ok, _} = seed_stock(scope, product, 1)

    conn = get(conn, ~p"/api/v1/reports/stock?low_stock_only=true")

    assert %{"data" => [%{"name" => "Almost Out", "low_stock" => true}]} =
             json_response(conn, 200)
  end
end
