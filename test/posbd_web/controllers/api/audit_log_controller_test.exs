defmodule PosbdWeb.Api.AuditLogControllerTest do
  use PosbdWeb.ConnCase, async: true

  import Posbd.BusinessesFixtures
  import Posbd.ProductsFixtures

  setup do
    scope = full_scope_fixture()
    %{scope: scope, conn: authed_conn(scope)}
  end

  test "GET /audit_logs lists entries for the current business, newest first", %{
    conn: conn,
    scope: scope
  } do
    product = product_fixture(scope)
    {:ok, _} = Posbd.Products.update_product(scope, product, %{selling_price: "500.00"})

    conn = get(conn, ~p"/api/v1/audit_logs")

    assert %{"data" => [first, second], "pagination" => %{"total_count" => 2}} =
             json_response(conn, 200)

    assert first["action"] == "product.price_changed"
    assert second["action"] == "product.created"
  end

  test "supports filtering by entity_type", %{conn: conn, scope: scope} do
    product_fixture(scope)

    conn = get(conn, ~p"/api/v1/audit_logs?entity_type=Invoice")
    assert %{"data" => []} = json_response(conn, 200)

    conn = get(authed_conn(scope), ~p"/api/v1/audit_logs?entity_type=Product")
    assert %{"data" => [%{"entity_type" => "Product"}]} = json_response(conn, 200)
  end

  test "a cashier cannot view the audit log", %{scope: scope} do
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

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> put_req_header("x-business-id", scope.business.id)
      |> get(~p"/api/v1/audit_logs")

    assert json_response(conn, 403)
  end
end
