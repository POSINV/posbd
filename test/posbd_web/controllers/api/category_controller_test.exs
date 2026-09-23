defmodule PosbdWeb.Api.CategoryControllerTest do
  use PosbdWeb.ConnCase, async: true

  import Posbd.BusinessesFixtures
  import Posbd.ProductsFixtures

  setup %{conn: conn} do
    scope = full_scope_fixture()
    token = Posbd.Accounts.create_api_token(scope.user)

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{token}")
      |> put_req_header("x-business-id", scope.business.id)

    %{conn: conn, scope: scope}
  end

  test "full CRUD round-trip", %{scope: scope} do
    conn = post(authed_conn(scope), ~p"/api/v1/categories", category: %{name: "Men's Wear"})
    assert %{"data" => %{"id" => id, "slug" => "men-s-wear"}} = json_response(conn, 201)

    conn = get(authed_conn(scope), ~p"/api/v1/categories/#{id}")
    assert %{"data" => %{"name" => "Men's Wear"}} = json_response(conn, 200)

    conn = patch(authed_conn(scope), ~p"/api/v1/categories/#{id}", category: %{name: "Menswear"})
    assert %{"data" => %{"name" => "Menswear"}} = json_response(conn, 200)

    conn = delete(authed_conn(scope), ~p"/api/v1/categories/#{id}")
    assert response(conn, 204)
  end

  test "GET /api/v1/categories lists only the current business's categories", %{
    conn: conn,
    scope: scope
  } do
    category_fixture(scope, name: "Mine")
    category_fixture(full_scope_fixture(), name: "Theirs")

    conn = get(conn, ~p"/api/v1/categories")
    assert %{"data" => [%{"name" => "Mine"}]} = json_response(conn, 200)
  end
end
