defmodule PosbdWeb.Api.LoyaltyControllerTest do
  use PosbdWeb.ConnCase, async: true

  import Posbd.BusinessesFixtures
  import Posbd.CustomersFixtures

  setup do
    %{scope: full_scope_fixture()}
  end

  test "GET /loyalty/program returns the default program when unconfigured", %{scope: scope} do
    conn = get(authed_conn(scope), ~p"/api/v1/loyalty/program")

    assert %{"data" => %{"enabled" => false, "active" => false}} = json_response(conn, 200)
  end

  test "PATCH /loyalty/program configures and enables the program", %{scope: scope} do
    conn =
      patch(authed_conn(scope), ~p"/api/v1/loyalty/program",
        program: %{"enabled" => true, "earn_amount_per_point" => "50"}
      )

    assert %{"data" => %{"enabled" => true, "earn_amount_per_point" => "50", "active" => true}} =
             json_response(conn, 200)
  end

  test "GET /customers/:id/loyalty returns balance and ledger history", %{scope: scope} do
    {:ok, _} = Posbd.Loyalty.upsert_program(scope, %{"enabled" => true})
    customer = customer_fixture(scope)

    {:ok, _} =
      Posbd.Loyalty.record_entry(scope, %{
        "customer_id" => customer.id,
        "entry_type" => "bonus",
        "points" => 25,
        "description" => "Welcome bonus"
      })

    conn = get(authed_conn(scope), ~p"/api/v1/customers/#{customer.id}/loyalty")

    assert %{"balance" => 25, "data" => [%{"entry_type" => "bonus", "points" => 25}]} =
             json_response(conn, 200)
  end

  test "GET /reports/loyalty summarizes points issued/redeemed", %{scope: scope} do
    {:ok, _} = Posbd.Loyalty.upsert_program(scope, %{"enabled" => true})
    customer = customer_fixture(scope)

    {:ok, _} =
      Posbd.Loyalty.record_entry(scope, %{
        "customer_id" => customer.id,
        "entry_type" => "bonus",
        "points" => 25
      })

    today = Date.utc_today() |> Date.to_iso8601()

    conn =
      get(authed_conn(scope), ~p"/api/v1/reports/loyalty?from=#{today}&to=#{today}")

    assert %{"data" => %{"points_earned" => 25, "active_members" => 1}} = json_response(conn, 200)
  end
end
