defmodule PosbdWeb.Api.Admin.PlanControllerTest do
  use PosbdWeb.ConnCase, async: true

  import Posbd.SubscriptionsFixtures

  defp admin_conn(role \\ "admin") do
    admin = platform_admin_fixture(role: role)
    token = Posbd.PlatformAdmins.create_api_token(admin)
    build_conn() |> put_req_header("authorization", "Bearer #{token}")
  end

  test "GET /admin/plans lists plans including inactive ones" do
    plan_fixture(is_active: false)
    conn = get(admin_conn(), ~p"/api/v1/admin/plans")

    assert %{"data" => plans} = json_response(conn, 200)
    assert Enum.any?(plans, &(&1["is_active"] == false))
  end

  test "an admin can create and then update a plan" do
    conn = admin_conn()

    create_resp =
      post(conn, ~p"/api/v1/admin/plans", %{
        "plan" => %{
          "name" => "Starter",
          "slug" => "starter-#{System.unique_integer()}",
          "price" => "499.00",
          "currency" => "INR",
          "billing_period" => "yearly",
          "features" => %{"loyalty" => false}
        }
      })

    assert %{"data" => %{"id" => id, "name" => "Starter"}} = json_response(create_resp, 201)

    update_resp =
      patch(admin_conn(), ~p"/api/v1/admin/plans/#{id}", %{"plan" => %{"price" => "599.00"}})

    assert %{"data" => %{"price" => "599.00"}} = json_response(update_resp, 200)
  end

  test "a support-role admin cannot create a plan" do
    conn = admin_conn("support")

    resp =
      post(conn, ~p"/api/v1/admin/plans", %{
        "plan" => %{
          "name" => "Starter",
          "slug" => "starter-#{System.unique_integer()}",
          "price" => "499.00",
          "currency" => "INR",
          "billing_period" => "yearly"
        }
      })

    assert json_response(resp, 403)
  end
end
