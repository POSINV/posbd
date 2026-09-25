defmodule PosbdWeb.Api.WhatsappMessageController do
  use PosbdWeb, :controller

  alias Posbd.Whatsapp
  alias PosbdWeb.Api.Authorize

  action_fallback PosbdWeb.Api.FallbackController

  def index(%{assigns: %{current_scope: scope}} = conn, params) do
    with :ok <- Authorize.require(scope, "whatsapp.manage") do
      render(conn, :index, Whatsapp.list_messages(scope, params))
    end
  end
end
