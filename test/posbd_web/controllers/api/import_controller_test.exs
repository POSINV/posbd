defmodule PosbdWeb.Api.ImportControllerTest do
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

  defp upload(content, filename \\ "import.csv") do
    path = Path.join(System.tmp_dir!(), "#{System.unique_integer([:positive])}-#{filename}")
    File.write!(path, content)
    %Plug.Upload{path: path, filename: filename, content_type: "text/csv"}
  end

  test "GET /imports/products/template downloads a CSV", %{conn: conn} do
    conn = get(conn, ~p"/api/v1/imports/products/template")
    assert response(conn, 200)
    assert get_resp_header(conn, "content-type") |> hd() =~ "text/csv"
    assert conn.resp_body =~ "name,category,sku"
  end

  test "POST /imports/products/preview validates rows from an uploaded file", %{
    conn: conn,
    scope: scope
  } do
    category_fixture(scope, name: "Grocery")

    csv = "name,category,sku,selling_price\nRice 5kg,Grocery,RICE-5,450.00\n,Grocery,BAD,10.00\n"

    conn = post(conn, ~p"/api/v1/imports/products/preview", %{"file" => upload(csv)})

    assert %{"data" => %{"total" => 2, "valid" => 1, "invalid" => 1, "rows" => rows}} =
             json_response(conn, 200)

    assert [%{"valid" => true}, %{"valid" => false, "errors" => %{"name" => _}}] = rows
  end

  test "POST /imports/products/commit creates only the submitted valid rows", %{
    conn: conn,
    scope: scope
  } do
    category_fixture(scope, name: "Grocery")

    conn =
      post(conn, ~p"/api/v1/imports/products/commit", %{
        "rows" => [
          %{
            "row_number" => 1,
            "name" => "Rice 5kg",
            "category" => "Grocery",
            "sku" => "RICE-5",
            "selling_price" => "450.00",
            "opening_stock" => "20"
          }
        ]
      })

    assert %{"data" => %{"created" => 1, "failed_count" => 0}} = json_response(conn, 200)

    conn = get(authed_conn(scope), ~p"/api/v1/products?search=Rice")

    assert %{"data" => [%{"name" => "Rice 5kg", "stock_quantity" => 20}]} =
             json_response(conn, 200)
  end

  test "opening stock preview + commit round-trip", %{conn: conn, scope: scope} do
    product_fixture(scope, sku: "OS-1", selling_price: "100.00")

    csv = "sku,quantity\nOS-1,15\n"
    conn1 = post(conn, ~p"/api/v1/imports/opening_stock/preview", %{"file" => upload(csv)})

    assert %{"data" => %{"valid" => 1, "rows" => [%{"valid" => true} = row]}} =
             json_response(conn1, 200)

    conn2 =
      post(authed_conn(scope), ~p"/api/v1/imports/opening_stock/commit", %{
        "rows" => [Map.put(row["fields"], "row_number", row["row_number"])]
      })

    assert %{"data" => %{"created" => 1}} = json_response(conn2, 200)

    conn3 = get(authed_conn(scope), ~p"/api/v1/products?search=OS")
    assert %{"data" => [%{"stock_quantity" => 15}]} = json_response(conn3, 200)
  end

  test "GET /imports/historical_bills/template downloads a CSV", %{conn: conn} do
    conn = get(conn, ~p"/api/v1/imports/historical_bills/template")
    assert response(conn, 200)
    assert get_resp_header(conn, "content-type") |> hd() =~ "text/csv"
    assert conn.resp_body =~ "invoice_number,date,customer_name"
  end

  test "historical bills preview + commit round-trip creates an invoice without touching stock",
       %{conn: conn, scope: scope} do
    product_fixture(scope, sku: "HB-1")

    csv =
      "invoice_number,date,customer_name,customer_phone,sku,quantity,unit_price,discount_amount,tax_amount,amount_paid,payment_method,notes\n" <>
        "OLD-9001,2025-02-01,Priya,9998887770,HB-1,3,50.00,0,0,150.00,cash,Migrated\n"

    conn1 = post(conn, ~p"/api/v1/imports/historical_bills/preview", %{"file" => upload(csv)})

    assert %{"data" => %{"valid" => 1, "invalid" => 0, "rows" => [row]}} =
             json_response(conn1, 200)

    conn2 =
      post(authed_conn(scope), ~p"/api/v1/imports/historical_bills/commit", %{
        "rows" => [Map.put(row["fields"], "row_number", row["row_number"])]
      })

    assert %{"data" => %{"created" => 1, "failed_count" => 0}} = json_response(conn2, 200)

    conn3 = get(authed_conn(scope), ~p"/api/v1/invoices")

    assert %{"data" => [%{"invoice_number" => "OLD-9001", "source" => "migrated"}]} =
             json_response(conn3, 200)

    conn4 = get(authed_conn(scope), ~p"/api/v1/products?search=HB-1")
    assert %{"data" => [%{"stock_quantity" => 0}]} = json_response(conn4, 200)
  end

  test "a cashier cannot import historical bills", %{scope: scope} do
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
      |> post(~p"/api/v1/imports/historical_bills/commit", %{"rows" => []})

    assert json_response(conn, 403)
  end

  test "GET /imports/history lists past import runs", %{conn: conn, scope: scope} do
    category_fixture(scope, name: "Grocery")

    post(conn, ~p"/api/v1/imports/products/commit", %{
      "rows" => [%{"row_number" => 1, "name" => "Rice 5kg", "category" => "Grocery"}]
    })

    conn = get(authed_conn(scope), ~p"/api/v1/imports/history")

    assert %{"data" => [%{"import_type" => "products", "success_count" => 1}]} =
             json_response(conn, 200)
  end

  test "a cashier cannot import products", %{scope: scope} do
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
      |> post(~p"/api/v1/imports/products/commit", %{"rows" => []})

    assert json_response(conn, 403)
  end
end
