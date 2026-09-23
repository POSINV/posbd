defmodule PosbdWeb.Api.BusinessController do
  use PosbdWeb, :controller

  alias Posbd.Businesses
  alias Posbd.Businesses.Roles

  action_fallback PosbdWeb.Api.FallbackController

  def index(%{assigns: %{current_scope: scope}} = conn, _params) do
    businesses = Businesses.list_businesses_for_user(scope)
    render(conn, :index, businesses: businesses)
  end

  def templates(conn, _params) do
    render(conn, :templates, templates: Posbd.Businesses.BusinessTypes.list())
  end

  def create(%{assigns: %{current_scope: scope}} = conn, %{"business" => business_params}) do
    with {:ok, business} <- Businesses.create_business(scope, business_params) do
      conn
      |> put_status(:created)
      |> render(:show, business: business, role: "owner")
    end
  end

  def show(%{assigns: %{current_scope: scope}} = conn, %{"id" => id}) do
    case Businesses.get_business_for_user(scope, id) do
      {business, membership} -> render(conn, :show, business: business, role: membership.role)
      nil -> {:error, :not_found}
    end
  end

  def update(%{assigns: %{current_scope: scope}} = conn, %{"id" => id, "business" => params}) do
    case Businesses.get_business_for_user(scope, id) do
      nil ->
        {:error, :not_found}

      {business, membership} ->
        if Roles.can?(membership, "settings.manage") do
          with {:ok, updated} <- Businesses.update_business(business, params) do
            render(conn, :show, business: updated, role: membership.role)
          end
        else
          {:error, :unauthorized}
        end
    end
  end

  def complete_onboarding(%{assigns: %{current_scope: scope}} = conn, %{"id" => id}) do
    case Businesses.get_business_for_user(scope, id) do
      nil ->
        {:error, :not_found}

      {business, membership} ->
        with {:ok, updated} <- Businesses.complete_onboarding(business) do
          render(conn, :show, business: updated, role: membership.role)
        end
    end
  end
end
