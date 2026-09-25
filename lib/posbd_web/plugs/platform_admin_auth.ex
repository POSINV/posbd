defmodule PosbdWeb.Plugs.PlatformAdminAuth do
  @moduledoc "Authenticates platform-admin API requests via a `Bearer <token>` header and assigns `conn.assigns.current_platform_admin`. Entirely separate from `PosbdWeb.Plugs.ApiAuth` (tenant users)."

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias Posbd.PlatformAdmins

  def init(opts), do: opts

  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         %PlatformAdmins.PlatformAdmin{} = admin <- PlatformAdmins.fetch_admin_by_api_token(token) do
      assign(conn, :current_platform_admin, admin)
    else
      _ ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: %{message: "Unauthorized"}})
        |> halt()
    end
  end
end
