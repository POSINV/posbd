defmodule PosbdWeb.Api.CategoryController do
  use PosbdWeb, :controller

  alias Posbd.Categories
  alias PosbdWeb.Api.Authorize

  action_fallback PosbdWeb.Api.FallbackController

  def index(%{assigns: %{current_scope: scope}} = conn, _params) do
    render(conn, :index, categories: Categories.list_categories(scope))
  end

  def create(%{assigns: %{current_scope: scope}} = conn, %{"category" => params}) do
    with :ok <- Authorize.require(scope, "products.create"),
         {:ok, category} <- Categories.create_category(scope, params) do
      conn |> put_status(:created) |> render(:show, category: category)
    end
  end

  def show(%{assigns: %{current_scope: scope}} = conn, %{"id" => id}) do
    case Categories.get_category(scope, id) do
      nil -> {:error, :not_found}
      category -> render(conn, :show, category: category)
    end
  end

  def update(%{assigns: %{current_scope: scope}} = conn, %{"id" => id, "category" => params}) do
    with :ok <- Authorize.require(scope, "products.update"),
         category when not is_nil(category) <- Categories.get_category(scope, id),
         {:ok, updated} <- Categories.update_category(category, params) do
      render(conn, :show, category: updated)
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  def delete(%{assigns: %{current_scope: scope}} = conn, %{"id" => id}) do
    with :ok <- Authorize.require(scope, "products.delete"),
         category when not is_nil(category) <- Categories.get_category(scope, id),
         {:ok, _} <- Categories.delete_category(category) do
      send_resp(conn, :no_content, "")
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end
end
