defmodule PosbdWeb.Api.AttributeController do
  use PosbdWeb, :controller

  alias Posbd.Products

  action_fallback PosbdWeb.Api.FallbackController

  def index(%{assigns: %{current_scope: scope}} = conn, _params) do
    render(conn, :index, attributes: Products.list_attributes(scope))
  end
end
