defmodule PosbdWeb.Api.Admin.SessionControllerTest do
  use PosbdWeb.ConnCase, async: true

  import Posbd.SubscriptionsFixtures

  test "POST /admin/login with correct credentials returns a token" do
    platform_admin_fixture(email: "ops@example.com", password: "supersecret1")

    conn =
      post(build_conn(), ~p"/api/v1/admin/login", %{
        "email" => "ops@example.com",
        "password" => "supersecret1"
      })

    assert %{"data" => %{"token" => token, "admin" => %{"email" => "ops@example.com"}}} =
             json_response(conn, 200)

    assert is_binary(token)
  end

  test "POST /admin/login with a wrong password is rejected" do
    platform_admin_fixture(email: "ops2@example.com", password: "supersecret1")

    conn =
      post(build_conn(), ~p"/api/v1/admin/login", %{
        "email" => "ops2@example.com",
        "password" => "nope"
      })

    assert json_response(conn, 401)
  end

  test "a tenant-user bearer token cannot authenticate admin routes" do
    user = Posbd.AccountsFixtures.user_fixture()
    token = Posbd.Accounts.create_api_token(user)

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> get(~p"/api/v1/admin/me")

    assert json_response(conn, 401)
  end

  test "GET /admin/me and DELETE /admin/logout" do
    admin = platform_admin_fixture(email: "ops3@example.com", password: "supersecret1")
    token = Posbd.PlatformAdmins.create_api_token(admin)

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> get(~p"/api/v1/admin/me")

    assert %{"data" => %{"email" => "ops3@example.com", "role" => "admin"}} =
             json_response(conn, 200)

    logout_conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> delete(~p"/api/v1/admin/logout")

    assert response(logout_conn, 204)

    reuse_conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> get(~p"/api/v1/admin/me")

    assert json_response(reuse_conn, 401)
  end
end
