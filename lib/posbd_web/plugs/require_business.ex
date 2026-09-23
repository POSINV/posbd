defmodule PosbdWeb.Plugs.RequireBusiness do
  @moduledoc """
  Resolves the tenant for the request from the `x-business-id` header,
  verifies the current user is a member of it, and upgrades
  `conn.assigns.current_scope` to include the business + membership.

  This is the single enforcement point for tenant isolation on API
  routes: every downstream controller/context call receives a scope
  that already carries a *verified* business, so a client can never
  read another tenant's data just by sending a different id.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias Posbd.Businesses

  def init(opts), do: opts

  def call(conn, _opts) do
    scope = conn.assigns.current_scope

    with [business_id] <- get_req_header(conn, "x-business-id"),
         {business, membership} <- Businesses.get_business_for_user(scope, business_id) do
      assign(conn, :current_scope, %{scope | business: business, membership: membership})
    else
      _ ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: %{message: "Missing or inaccessible business (x-business-id header)"}})
        |> halt()
    end
  end
end
