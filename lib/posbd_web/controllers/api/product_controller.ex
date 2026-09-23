defmodule PosbdWeb.Api.ProductController do
  use PosbdWeb, :controller

  alias Posbd.Products
  alias PosbdWeb.Api.Authorize

  action_fallback PosbdWeb.Api.FallbackController

  def index(%{assigns: %{current_scope: scope}} = conn, params) do
    result = Products.list_products(scope, params)
    render(conn, :index, result)
  end

  def create(%{assigns: %{current_scope: scope}} = conn, %{"product" => params}) do
    with :ok <- Authorize.require(scope, "products.create"),
         {:ok, product} <- Products.create_product(scope, params) do
      conn |> put_status(:created) |> render(:show, product: product)
    end
  end

  def show(%{assigns: %{current_scope: scope}} = conn, %{"id" => id}) do
    case Products.get_product(scope, id) do
      nil -> {:error, :not_found}
      product -> render(conn, :show, product: product)
    end
  end

  def update(%{assigns: %{current_scope: scope}} = conn, %{"id" => id, "product" => params}) do
    with :ok <- Authorize.require(scope, "products.update"),
         product when not is_nil(product) <- Products.get_product(scope, id),
         {:ok, updated} <- Products.update_product(product, params) do
      render(conn, :show, product: updated)
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  def delete(%{assigns: %{current_scope: scope}} = conn, %{"id" => id}) do
    with :ok <- Authorize.require(scope, "products.delete"),
         product when not is_nil(product) <- Products.get_product(scope, id),
         {:ok, _} <- Products.delete_product(product) do
      send_resp(conn, :no_content, "")
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end
end
