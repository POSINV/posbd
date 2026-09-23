defmodule PosbdWeb.Api.InventoryControllerTest do
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

  test "POST /inventory/movements records opening stock and bumps the product's stock_quantity",
       %{
         conn: conn,
         scope: scope
       } do
    product = product_fixture(scope)

    conn =
      post(conn, ~p"/api/v1/inventory/movements",
        movement: %{
          product_id: product.id,
          movement_type: "opening_stock",
          direction: "in",
          quantity: 40,
          reference: "Opening balance"
        }
      )

    assert %{"data" => %{"quantity" => 40, "movement_type" => "opening_stock"}} =
             json_response(conn, 201)

    conn = get(authed_conn(scope), ~p"/api/v1/products/#{product.id}")
    assert %{"data" => %{"stock_quantity" => 40, "low_stock" => false}} = json_response(conn, 200)
  end

  test "GET /inventory/movements lists history for one product, newest first", %{
    conn: conn,
    scope: scope
  } do
    product = product_fixture(scope)

    post(conn, ~p"/api/v1/inventory/movements",
      movement: %{
        product_id: product.id,
        movement_type: "opening_stock",
        direction: "in",
        quantity: 10
      }
    )

    post(authed_conn(scope), ~p"/api/v1/inventory/movements",
      movement: %{product_id: product.id, movement_type: "sale", direction: "out", quantity: 1}
    )

    conn = get(authed_conn(scope), ~p"/api/v1/inventory/movements?product_id=#{product.id}")

    assert %{"data" => [%{"movement_type" => "sale"}, %{"movement_type" => "opening_stock"}]} =
             json_response(conn, 200)
  end

  test "rejects a movement with an invalid direction", %{conn: conn, scope: scope} do
    product = product_fixture(scope)

    conn =
      post(conn, ~p"/api/v1/inventory/movements",
        movement: %{
          product_id: product.id,
          movement_type: "sale",
          direction: "sideways",
          quantity: 1
        }
      )

    assert %{"errors" => %{"direction" => _}} = json_response(conn, 422)
  end

  test "404s for a product belonging to another business", %{conn: conn} do
    other = full_scope_fixture()
    product = product_fixture(other)

    conn =
      post(conn, ~p"/api/v1/inventory/movements",
        movement: %{
          product_id: product.id,
          movement_type: "opening_stock",
          direction: "in",
          quantity: 1
        }
      )

    assert json_response(conn, 404)
  end
end
