defmodule PosbdWeb.Plugs.ApiAuth do
  @moduledoc """
  Authenticates API requests via a `Bearer <token>` Authorization header
  and assigns `conn.assigns.current_scope`. Renders 401 when missing/invalid.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias Posbd.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         %Posbd.Accounts.Scope{} = scope <- Accounts.fetch_scope_by_api_token(token) do
      assign(conn, :current_scope, scope)
    else
      _ ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: %{message: "Unauthorized"}})
        |> halt()
    end
  end
end
