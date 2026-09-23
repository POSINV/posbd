defmodule PosbdWeb.Api.ProductControllerTest do
  use PosbdWeb.ConnCase, async: true

  import Posbd.AccountsFixtures
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

  test "GET /api/v1/products requires the x-business-id header", %{conn: conn} do
    conn = conn |> delete_req_header("x-business-id") |> get(~p"/api/v1/products")
    assert json_response(conn, 403)
  end

  test "GET /api/v1/products lists paginated products for the current business", %{
    conn: conn,
    scope: scope
  } do
    product_fixture(scope, name: "Blue Jeans")

    conn = get(conn, ~p"/api/v1/products")

    assert %{"data" => [%{"name" => "Blue Jeans"}], "pagination" => %{"total_count" => 1}} =
             json_response(conn, 200)
  end

  test "a business cannot see another business's product", %{conn: conn} do
    other = full_scope_fixture()
    product = product_fixture(other)

    conn = get(conn, ~p"/api/v1/products/#{product.id}")
    assert json_response(conn, 404)
  end

  test "POST /api/v1/products creates a product", %{conn: conn} do
    conn =
      post(conn, ~p"/api/v1/products",
        product: %{name: "Red Saree", selling_price: "1200.00", unit: "pcs"}
      )

    assert %{"data" => %{"name" => "Red Saree", "selling_price" => "1200.00"}} =
             json_response(conn, 201)
  end

  test "POST /api/v1/products validates presence of name", %{conn: conn} do
    conn = post(conn, ~p"/api/v1/products", product: %{})
    assert %{"errors" => %{"name" => _}} = json_response(conn, 422)
  end

  test "variants: create, update, delete round-trip with attributes", %{scope: scope} do
    product = product_fixture(scope, name: "T-Shirt", has_variants: true)

    conn =
      post(authed_conn(scope), ~p"/api/v1/products/#{product.id}/variants",
        variant: %{
          sku: "TS-RED-M",
          selling_price: "299.00",
          attributes: %{Size: "M", Color: "Red"}
        }
      )

    assert %{"data" => %{"id" => variant_id, "attributes" => attributes}} =
             json_response(conn, 201)

    assert attributes == %{"Size" => "M", "Color" => "Red"}

    conn =
      patch(authed_conn(scope), ~p"/api/v1/products/#{product.id}/variants/#{variant_id}",
        variant: %{attributes: %{Size: "L"}}
      )

    assert %{"data" => %{"attributes" => %{"Size" => "L"}}} = json_response(conn, 200)

    conn = delete(authed_conn(scope), ~p"/api/v1/products/#{product.id}/variants/#{variant_id}")
    assert response(conn, 204)
  end

  test "a cashier cannot create a product", %{scope: scope} do
    cashier_user = user_fixture()
    token = Posbd.Accounts.create_api_token(cashier_user)

    {:ok, _membership} =
      %Posbd.Businesses.Membership{}
      |> Posbd.Businesses.Membership.owner_changeset(scope.business.id, cashier_user.id)
      |> Ecto.Changeset.change(
        role: "cashier",
        permissions: Posbd.Businesses.Roles.default_permissions_for("cashier")
      )
      |> Posbd.Repo.insert()

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> put_req_header("x-business-id", scope.business.id)
      |> post(~p"/api/v1/products", product: %{name: "Should Fail"})

    assert json_response(conn, 403)
  end
end
