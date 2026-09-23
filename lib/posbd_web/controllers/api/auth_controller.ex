defmodule PosbdWeb.Api.AuthController do
  use PosbdWeb, :controller

  alias Posbd.Accounts
  alias Posbd.Accounts.Scope

  action_fallback PosbdWeb.Api.FallbackController

  def register(conn, %{"user" => user_params}) do
    with {:ok, user} <- Accounts.register_user(user_params) do
      token = Accounts.create_api_token(user)

      conn
      |> put_status(:created)
      |> render(:session, user: user, token: token)
    end
  end

  def login(conn, %{"email" => email, "password" => password}) do
    if user = Accounts.get_user_by_email_and_password(email, password) do
      token = Accounts.create_api_token(user)
      render(conn, :session, user: user, token: token)
    else
      conn
      |> put_status(:unauthorized)
      |> json(%{error: %{message: "Invalid email or password"}})
    end
  end

  def logout(conn, _params) do
    ["Bearer " <> token] = get_req_header(conn, "authorization")
    Accounts.revoke_api_token(token)
    send_resp(conn, :no_content, "")
  end

  def me(%{assigns: %{current_scope: %Scope{user: user}}} = conn, _params) do
    businesses = Posbd.Businesses.list_businesses_for_user(%Scope{user: user})
    render(conn, :me, user: user, businesses: businesses)
  end
end
