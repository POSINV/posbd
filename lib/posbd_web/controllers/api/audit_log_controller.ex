defmodule PosbdWeb.Api.AuditLogController do
  use PosbdWeb, :controller

  alias Posbd.AuditLogs
  alias PosbdWeb.Api.Authorize

  action_fallback PosbdWeb.Api.FallbackController

  def index(%{assigns: %{current_scope: scope}} = conn, params) do
    with :ok <- Authorize.require(scope, "audit.view") do
      result = AuditLogs.list(scope, params)
      render(conn, :index, result)
    end
  end
end
