defmodule PosbdWeb.Api.WhatsappTemplateController do
  use PosbdWeb, :controller

  alias Posbd.Whatsapp
  alias PosbdWeb.Api.Authorize

  action_fallback PosbdWeb.Api.FallbackController

  def index(%{assigns: %{current_scope: scope}} = conn, _params) do
    with :ok <- Authorize.require(scope, "whatsapp.manage") do
      render(conn, :index, templates: Whatsapp.list_templates(scope))
    end
  end

  def show(%{assigns: %{current_scope: scope}} = conn, %{"id" => id}) do
    with :ok <- Authorize.require(scope, "whatsapp.manage") do
      case Whatsapp.get_template(scope, id) do
        nil -> {:error, :not_found}
        template -> render(conn, :show, template: template)
      end
    end
  end

  def create(%{assigns: %{current_scope: scope}} = conn, %{"template" => attrs}) do
    with :ok <- Authorize.require(scope, "whatsapp.manage"),
         {:ok, template} <- Whatsapp.create_template(scope, attrs) do
      conn |> put_status(:created) |> render(:show, template: template)
    end
  end

  def update(%{assigns: %{current_scope: scope}} = conn, %{"id" => id, "template" => attrs}) do
    with :ok <- Authorize.require(scope, "whatsapp.manage"),
         template when not is_nil(template) <- Whatsapp.get_template(scope, id),
         {:ok, updated} <- Whatsapp.update_template(scope, template, attrs) do
      render(conn, :show, template: updated)
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end
end
