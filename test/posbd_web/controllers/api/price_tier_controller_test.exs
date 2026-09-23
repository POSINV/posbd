defmodule PosbdWeb.Api.PriceTierControllerTest do
  use PosbdWeb.ConnCase, async: true

  import Posbd.BusinessesFixtures
  import Posbd.ProductsFixtures
  import Posbd.PricingFixtures

  setup %{conn: conn} do
    scope = full_scope_fixture()

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{Posbd.Accounts.create_api_token(scope.user)}")
      |> put_req_header("x-business-id", scope.business.id)

    %{conn: conn, scope: scope}
  end

  test "full CRUD round-trip for a product tier", %{scope: scope} do
    product = product_fixture(scope, selling_price: "100.00")

    conn =
      post(authed_conn(scope), ~p"/api/v1/price_tiers",
        price_tier: %{product_id: product.id, label: "Bulk", min_quantity: 5, price: "85.00"}
      )

    assert %{"data" => %{"id" => id, "min_quantity" => 5}} = json_response(conn, 201)

    conn = get(authed_conn(scope), ~p"/api/v1/price_tiers?product_id=#{product.id}")
    assert %{"data" => [%{"id" => ^id}]} = json_response(conn, 200)

    conn = patch(authed_conn(scope), ~p"/api/v1/price_tiers/#{id}", price_tier: %{price: "80.00"})
    assert %{"data" => %{"price" => "80.00"}} = json_response(conn, 200)

    conn = delete(authed_conn(scope), ~p"/api/v1/price_tiers/#{id}")
    assert response(conn, 204)
  end

  test "GET /price_tiers/quote resolves the applicable unit price", %{conn: conn, scope: scope} do
    product = product_fixture(scope, selling_price: "100.00")
    price_tier_fixture(scope, product_id: product.id, min_quantity: 10, price: "80.00")

    conn = get(conn, ~p"/api/v1/price_tiers/quote?product_id=#{product.id}&quantity=1")
    assert %{"data" => %{"unit_price" => "100.00", "tier" => nil}} = json_response(conn, 200)

    conn =
      get(authed_conn(scope), ~p"/api/v1/price_tiers/quote?product_id=#{product.id}&quantity=15")

    assert %{"data" => %{"unit_price" => "80.00", "tier" => %{"min_quantity" => 10}}} =
             json_response(conn, 200)
  end

  test "quote 404s for a product from another business", %{conn: conn} do
    other = full_scope_fixture()
    product = product_fixture(other)

    conn = get(conn, ~p"/api/v1/price_tiers/quote?product_id=#{product.id}&quantity=1")
    assert json_response(conn, 404)
  end
end
