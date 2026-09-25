defmodule PosbdWeb.Api.Admin.SubscriptionControllerTest do
  use PosbdWeb.ConnCase, async: true

  import Posbd.BusinessesFixtures
  import Posbd.SubscriptionsFixtures

  defp token_for(admin) do
    Posbd.PlatformAdmins.create_api_token(admin)
  end

  test "an 'admin' role can activate a plan for a business, which then shows as active" do
    scope = full_scope_fixture()
    admin = platform_admin_fixture(role: "admin")
    plan = plan_fixture()
    conn = build_conn() |> put_req_header("authorization", "Bearer #{token_for(admin)}")

    resp =
      post(conn, ~p"/api/v1/admin/businesses/#{scope.business.id}/activate_plan", %{
        "plan_id" => plan.id,
        "payment_provider" => "manual",
        "provider_reference" => "REF-99"
      })

    assert %{
             "data" => %{
               "subscription" => %{"status" => "active"},
               "payment" => %{"status" => "paid"}
             }
           } =
             json_response(resp, 200)

    status_conn = get(authed_conn(scope), ~p"/api/v1/subscription")
    assert %{"data" => %{"status" => "active"}} = json_response(status_conn, 200)
  end

  test "a 'support' role cannot activate a plan" do
    scope = full_scope_fixture()
    admin = platform_admin_fixture(role: "support")
    plan = plan_fixture()
    conn = build_conn() |> put_req_header("authorization", "Bearer #{token_for(admin)}")

    resp =
      post(conn, ~p"/api/v1/admin/businesses/#{scope.business.id}/activate_plan", %{
        "plan_id" => plan.id
      })

    assert json_response(resp, 403)
  end

  test "an 'admin' role can cancel a business's subscription" do
    scope = full_scope_fixture()
    admin = platform_admin_fixture(role: "admin")
    conn = build_conn() |> put_req_header("authorization", "Bearer #{token_for(admin)}")

    resp = post(conn, ~p"/api/v1/admin/businesses/#{scope.business.id}/cancel_subscription", %{})
    assert %{"data" => %{"status" => "cancelled"}} = json_response(resp, 200)
  end
end
