defmodule PosbdWeb.Api.CustomerControllerTest do
  use PosbdWeb.ConnCase, async: true

  import Posbd.BusinessesFixtures
  import Posbd.CustomersFixtures

  setup %{conn: conn} do
    scope = full_scope_fixture()

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{Posbd.Accounts.create_api_token(scope.user)}")
      |> put_req_header("x-business-id", scope.business.id)

    %{conn: conn, scope: scope}
  end

  test "full CRUD round-trip", %{scope: scope} do
    conn =
      post(authed_conn(scope), ~p"/api/v1/customers",
        customer: %{name: "Priya Sharma", phone: "9998887777"}
      )

    assert %{"data" => %{"id" => id, "name" => "Priya Sharma"}} = json_response(conn, 201)

    conn = get(authed_conn(scope), ~p"/api/v1/customers/#{id}")
    assert %{"data" => %{"phone" => "9998887777"}} = json_response(conn, 200)

    conn =
      patch(authed_conn(scope), ~p"/api/v1/customers/#{id}",
        customer: %{email: "priya@example.com"}
      )

    assert %{"data" => %{"email" => "priya@example.com"}} = json_response(conn, 200)

    conn = delete(authed_conn(scope), ~p"/api/v1/customers/#{id}")
    assert response(conn, 204)
  end

  test "GET /customers searches and stays scoped to the current business", %{
    conn: conn,
    scope: scope
  } do
    customer_fixture(scope, name: "Findable Customer", phone: "1112223333")
    customer_fixture(full_scope_fixture(), name: "Other Business Customer")

    conn = get(conn, ~p"/api/v1/customers?search=Findable")
    assert %{"data" => [%{"name" => "Findable Customer"}]} = json_response(conn, 200)
  end

  test "GET /customers includes purchase stats and segment for each row", %{scope: scope} do
    customer_fixture(scope, name: "No Purchases Yet")

    conn = get(authed_conn(scope), ~p"/api/v1/customers")

    assert %{"data" => [%{"total_spent" => "0", "visit_count" => 0, "segment" => "new"}]} =
             json_response(conn, 200)
  end

  test "GET /customers/:id/summary returns purchase history for one customer", %{
    conn: conn,
    scope: scope
  } do
    customer = customer_fixture(scope, name: "Summary Customer")

    conn = get(conn, ~p"/api/v1/customers/#{customer.id}/summary")

    assert %{
             "data" => %{
               "visit_count" => 0,
               "total_spent" => "0",
               "top_products" => [],
               "segment" => "new"
             }
           } = json_response(conn, 200)
  end
end
