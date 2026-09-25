defmodule PosbdWeb.Api.Admin.SessionController do
  use PosbdWeb, :controller

  import Plug.Conn

  alias Posbd.PlatformAdmins

  action_fallback PosbdWeb.Api.FallbackController

  @doc "There is no admin self-registration endpoint - accounts are created out-of-band by someone who already has one."
  def login(conn, %{"email" => email, "password" => password}) do
    case PlatformAdmins.get_by_email_and_password(email, password) do
      nil ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: %{message: "Invalid email or password"}})

      admin ->
        token = PlatformAdmins.create_api_token(admin)
        render(conn, :session, admin: admin, token: token)
    end
  end

  def me(%{assigns: %{current_platform_admin: admin}} = conn, _params) do
    render(conn, :me, admin: admin)
  end

  def logout(conn, _params) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> PlatformAdmins.revoke_api_token(token)
      _ -> :ok
    end

    send_resp(conn, :no_content, "")
  end
end
