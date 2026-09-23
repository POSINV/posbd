defmodule PosbdWeb.Api.ProductVariantController do
  use PosbdWeb, :controller

  alias Posbd.Products
  alias PosbdWeb.Api.Authorize

  action_fallback PosbdWeb.Api.FallbackController

  def create(%{assigns: %{current_scope: scope}} = conn, %{
        "product_id" => product_id,
        "variant" => params
      }) do
    with :ok <- Authorize.require(scope, "products.create"),
         product when not is_nil(product) <- Products.get_product(scope, product_id),
         {:ok, variant} <- Products.create_variant(scope, product, params) do
      conn |> put_status(:created) |> render(:show, variant: variant)
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  def update(%{assigns: %{current_scope: scope}} = conn, %{"id" => id, "variant" => params}) do
    with :ok <- Authorize.require(scope, "products.update"),
         variant when not is_nil(variant) <- Products.get_variant(scope, id),
         {:ok, updated} <- Products.update_variant(scope, variant, params) do
      render(conn, :show, variant: updated)
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  def delete(%{assigns: %{current_scope: scope}} = conn, %{"id" => id}) do
    with :ok <- Authorize.require(scope, "products.delete"),
         variant when not is_nil(variant) <- Products.get_variant(scope, id),
         {:ok, _} <- Products.delete_variant(variant) do
      send_resp(conn, :no_content, "")
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end
end
