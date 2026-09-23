defmodule PosbdWeb.Api.TargetLookup do
  @moduledoc """
  Resolves a `%Product{}` or `%ProductVariant{}` from `product_id`/
  `variant_id` request params, scoped to the current business. Shared by
  any controller (pricing, inventory, ...) whose target can be either a
  simple product or one specific variant.
  """

  alias Posbd.Products

  def fetch_item(scope, %{"product_id" => id}) when is_binary(id) and id != "" do
    case Products.get_product(scope, id) do
      nil -> {:error, :not_found}
      product -> {:ok, product}
    end
  end

  def fetch_item(scope, %{"variant_id" => id}) when is_binary(id) and id != "" do
    case Products.get_variant(scope, id) do
      nil -> {:error, :not_found}
      variant -> {:ok, variant}
    end
  end

  def fetch_item(_scope, _params), do: {:error, :not_found}

  def target_filter(%{"product_id" => id}) when is_binary(id) and id != "",
    do: {:ok, %{product_id: id}}

  def target_filter(%{"variant_id" => id}) when is_binary(id) and id != "",
    do: {:ok, %{variant_id: id}}

  def target_filter(_), do: {:error, :not_found}
end
