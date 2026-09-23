defmodule PosbdWeb.Api.InvoiceControllerTest do
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

  test "POST /invoices creates an invoice, decrements stock, and returns computed totals", %{
    conn: conn,
    scope: scope
  } do
    product = product_fixture(scope, selling_price: "100.00", tax_rate: "10")
    {:ok, _} = seed_stock(scope, product, 10)

    conn =
      post(conn, ~p"/api/v1/invoices", %{
        "items" => [%{"product_id" => product.id, "quantity" => 2}],
        "payments" => [%{"method" => "cash", "amount" => "220.00"}]
      })

    assert %{
             "data" => %{
               "total_amount" => "220.00",
               "payment_status" => "paid",
               "items" => [%{"quantity" => 2, "line_total" => "220.00"}]
             }
           } = json_response(conn, 201)

    conn = get(authed_conn(scope), ~p"/api/v1/products/#{product.id}")
    assert %{"data" => %{"stock_quantity" => 8}} = json_response(conn, 200)
  end

  test "a repeated idempotency_key does not double-charge or double-decrement stock", %{
    conn: conn,
    scope: scope
  } do
    product = product_fixture(scope, selling_price: "50.00")
    {:ok, _} = seed_stock(scope, product, 10)

    body = %{
      "items" => [%{"product_id" => product.id, "quantity" => 1}],
      "idempotency_key" => "abc-123"
    }

    conn1 = post(conn, ~p"/api/v1/invoices", body)
    %{"data" => %{"id" => id1}} = json_response(conn1, 201)

    conn2 = post(authed_conn(scope), ~p"/api/v1/invoices", body)
    %{"data" => %{"id" => id2}} = json_response(conn2, 201)

    assert id1 == id2

    conn = get(authed_conn(scope), ~p"/api/v1/products/#{product.id}")
    assert %{"data" => %{"stock_quantity" => 9}} = json_response(conn, 200)
  end

  test "GET /invoices lists invoices for the current business", %{conn: conn, scope: scope} do
    product = product_fixture(scope, selling_price: "10.00")
    {:ok, _} = seed_stock(scope, product, 5)

    post(conn, ~p"/api/v1/invoices", %{
      "items" => [%{"product_id" => product.id, "quantity" => 1}]
    })

    conn = get(authed_conn(scope), ~p"/api/v1/invoices")

    assert %{"data" => [%{"total_amount" => "10.00"}], "pagination" => %{"total_count" => 1}} =
             json_response(conn, 200)
  end

  test "POST /invoices/:id/cancel reverses stock", %{conn: conn, scope: scope} do
    product = product_fixture(scope, selling_price: "10.00")
    {:ok, _} = seed_stock(scope, product, 5)

    conn =
      post(conn, ~p"/api/v1/invoices", %{
        "items" => [%{"product_id" => product.id, "quantity" => 2}]
      })

    %{"data" => %{"id" => invoice_id}} = json_response(conn, 201)

    conn = post(authed_conn(scope), ~p"/api/v1/invoices/#{invoice_id}/cancel")
    assert %{"data" => %{"status" => "cancelled"}} = json_response(conn, 200)

    conn = get(authed_conn(scope), ~p"/api/v1/products/#{product.id}")
    assert %{"data" => %{"stock_quantity" => 5}} = json_response(conn, 200)
  end

  test "POST /invoices/:id/payments settles a partial invoice", %{conn: conn, scope: scope} do
    product = product_fixture(scope, selling_price: "100.00", tax_rate: "0")
    {:ok, _} = seed_stock(scope, product, 5)

    conn =
      post(conn, ~p"/api/v1/invoices", %{
        "items" => [%{"product_id" => product.id, "quantity" => 1}],
        "payments" => [%{"method" => "cash", "amount" => "40.00"}]
      })

    %{"data" => %{"id" => invoice_id}} = json_response(conn, 201)

    conn =
      post(authed_conn(scope), ~p"/api/v1/invoices/#{invoice_id}/payments",
        payment: %{method: "cash", amount: "60.00"}
      )

    assert %{"data" => %{"payment_status" => "paid"}} = json_response(conn, 200)
  end

  test "an item discount from a cashier without billing.discount is rejected", %{scope: scope} do
    user = Posbd.AccountsFixtures.user_fixture()
    token = Posbd.Accounts.create_api_token(user)

    {:ok, _} =
      %Posbd.Businesses.Membership{}
      |> Posbd.Businesses.Membership.owner_changeset(scope.business.id, user.id)
      |> Ecto.Changeset.change(
        role: "cashier",
        permissions: Posbd.Businesses.Roles.default_permissions_for("cashier")
      )
      |> Posbd.Repo.insert()

    product = product_fixture(scope, selling_price: "100.00")

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> put_req_header("x-business-id", scope.business.id)
      |> post(~p"/api/v1/invoices", %{
        "items" => [%{"product_id" => product.id, "quantity" => 1, "discount_amount" => "10.00"}]
      })

    assert json_response(conn, 403)
  end
end
