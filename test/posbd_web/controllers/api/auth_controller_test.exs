defmodule PosbdWeb.Api.AuthControllerTest do
  use PosbdWeb.ConnCase, async: true

  import Posbd.AccountsFixtures

  describe "POST /api/v1/auth/register" do
    test "creates a user and returns a bearer token", %{conn: conn} do
      attrs = valid_user_attrs()

      conn = post(conn, ~p"/api/v1/auth/register", user: attrs)

      assert %{"user" => %{"email" => email}, "token" => token} = json_response(conn, 201)
      assert email == String.downcase(attrs.email)
      assert is_binary(token)
    end

    test "returns validation errors for invalid params", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/auth/register", user: %{email: "not-an-email"})
      assert %{"errors" => errors} = json_response(conn, 422)
      assert errors["password"]
    end
  end

  describe "POST /api/v1/auth/login" do
    test "returns a token for valid credentials", %{conn: conn} do
      user = user_fixture()

      conn =
        post(conn, ~p"/api/v1/auth/login", email: user.email, password: valid_user_password())

      assert %{"token" => token} = json_response(conn, 200)
      assert is_binary(token)
    end

    test "returns 401 for invalid credentials", %{conn: conn} do
      user = user_fixture()
      conn = post(conn, ~p"/api/v1/auth/login", email: user.email, password: "wrong-password")
      assert json_response(conn, 401)
    end
  end

  describe "GET /api/v1/me" do
    test "requires a bearer token", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/me")
      assert json_response(conn, 401)
    end

    test "returns the current user and their businesses", %{conn: conn} do
      user = user_fixture()
      token = Posbd.Accounts.create_api_token(user)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> get(~p"/api/v1/me")

      assert %{"user" => %{"id" => id}, "businesses" => []} = json_response(conn, 200)
      assert id == user.id
    end
  end
end
