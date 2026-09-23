defmodule PosbdWeb.Api.BusinessControllerTest do
  use PosbdWeb.ConnCase, async: true

  import Posbd.AccountsFixtures
  import Posbd.BusinessesFixtures

  setup %{conn: conn} do
    user = user_fixture()
    token = Posbd.Accounts.create_api_token(user)
    conn = put_req_header(conn, "authorization", "Bearer #{token}")
    %{conn: conn, user: user}
  end

  test "GET /api/v1/business_types is public and lists templates", %{conn: conn} do
    conn = conn |> delete_req_header("authorization") |> get(~p"/api/v1/business_types")
    assert %{"data" => templates} = json_response(conn, 200)
    assert Enum.any?(templates, &(&1["key"] == "restaurant"))
  end

  test "POST /api/v1/businesses creates a business and makes the caller its owner", %{conn: conn} do
    conn =
      post(conn, ~p"/api/v1/businesses",
        business: %{name: "Sam's Store", business_type: "general", currency: "INR"}
      )

    assert %{"data" => %{"role" => "owner", "name" => "Sam's Store"}} = json_response(conn, 201)
  end

  test "GET /api/v1/businesses/:id 404s for a business the user does not belong to", %{
    conn: conn
  } do
    other_scope = Posbd.Accounts.Scope.for_user(user_fixture())
    business = business_fixture(other_scope)

    conn = get(conn, ~p"/api/v1/businesses/#{business.id}")
    assert json_response(conn, 404)
  end

  test "PATCH /api/v1/businesses/:id updates settings for an owner", %{conn: conn, user: user} do
    business = business_fixture(Posbd.Accounts.Scope.for_user(user))

    conn = patch(conn, ~p"/api/v1/businesses/#{business.id}", business: %{name: "Renamed"})
    assert %{"data" => %{"name" => "Renamed"}} = json_response(conn, 200)
  end

  test "POST /api/v1/businesses/:id/complete_onboarding marks onboarding done", %{
    conn: conn,
    user: user
  } do
    business = business_fixture(Posbd.Accounts.Scope.for_user(user))

    conn = post(conn, ~p"/api/v1/businesses/#{business.id}/complete_onboarding")
    assert %{"data" => %{"onboarding_completed" => true}} = json_response(conn, 200)
  end
end
