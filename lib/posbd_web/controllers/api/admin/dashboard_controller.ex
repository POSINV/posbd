defmodule PosbdWeb.Api.Admin.DashboardController do
  use PosbdWeb, :controller

  alias Posbd.Subscriptions

  action_fallback PosbdWeb.Api.FallbackController

  @doc "Business counts by effective subscription status (Phase 2 §13/§14)."
  def show(conn, _params) do
    render(conn, :show, counts: Subscriptions.dashboard_counts())
  end

  @doc "All businesses with their effective status, optionally filtered by `?status=`."
  def businesses(conn, params) do
    render(conn, :businesses, rows: Subscriptions.list_businesses_with_status(params["status"]))
  end
end
