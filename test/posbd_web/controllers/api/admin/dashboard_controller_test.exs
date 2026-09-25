defmodule PosbdWeb.Api.Admin.DashboardControllerTest do
  use PosbdWeb.ConnCase, async: true

  import Posbd.BusinessesFixtures
  import Posbd.SubscriptionsFixtures

  defp admin_conn do
    admin = platform_admin_fixture()
    token = Posbd.PlatformAdmins.create_api_token(admin)
    {build_conn() |> put_req_header("authorization", "Bearer #{token}"), admin}
  end

  test "GET /admin/dashboard counts businesses by effective status" do
    full_scope_fixture()
    {conn, _admin} = admin_conn()

    conn = get(conn, ~p"/api/v1/admin/dashboard")
    assert %{"data" => counts} = json_response(conn, 200)
    assert counts["trialing"] >= 1
  end

  test "GET /admin/businesses lists businesses with their status, filterable" do
    full_scope_fixture()
    {conn, _admin} = admin_conn()

    conn = get(conn, ~p"/api/v1/admin/businesses?status=trialing")
    assert %{"data" => rows} = json_response(conn, 200)
    assert length(rows) >= 1
    assert Enum.all?(rows, &(&1["status"] == "trialing"))
  end
end
