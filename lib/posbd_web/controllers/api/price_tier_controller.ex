defmodule PosbdWeb.Api.PriceTierController do
  use PosbdWeb, :controller

  alias Posbd.Pricing
  alias PosbdWeb.Api.{Authorize, TargetLookup}

  action_fallback PosbdWeb.Api.FallbackController

  def index(%{assigns: %{current_scope: scope}} = conn, params) do
    with {:ok, target} <- TargetLookup.target_filter(params) do
      render(conn, :index, price_tiers: Pricing.list_price_tiers(scope, target))
    end
  end

  def create(%{assigns: %{current_scope: scope}} = conn, %{"price_tier" => params}) do
    with :ok <- Authorize.require(scope, "products.update"),
         {:ok, tier} <- Pricing.create_price_tier(scope, params) do
      conn |> put_status(:created) |> render(:show, price_tier: tier)
    end
  end

  def update(%{assigns: %{current_scope: scope}} = conn, %{"id" => id, "price_tier" => params}) do
    with :ok <- Authorize.require(scope, "products.update"),
         tier when not is_nil(tier) <- Pricing.get_price_tier(scope, id),
         {:ok, updated} <- Pricing.update_price_tier(tier, params) do
      render(conn, :show, price_tier: updated)
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  def delete(%{assigns: %{current_scope: scope}} = conn, %{"id" => id}) do
    with :ok <- Authorize.require(scope, "products.update"),
         tier when not is_nil(tier) <- Pricing.get_price_tier(scope, id),
         {:ok, _} <- Pricing.delete_price_tier(tier) do
      send_resp(conn, :no_content, "")
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  @doc "GET /price_tiers/quote?product_id=X|variant_id=Y&quantity=N[&date=YYYY-MM-DD]"
  def quote(%{assigns: %{current_scope: scope}} = conn, params) do
    quantity = String.to_integer(params["quantity"] || "1")
    date = parse_date(params["date"]) || Date.utc_today()

    with {:ok, item} <- TargetLookup.fetch_item(scope, params) do
      result = Pricing.price_for(scope, item, quantity, date)
      render(conn, :quote, result)
    end
  end

  defp parse_date(nil), do: nil

  defp parse_date(string) do
    case Date.from_iso8601(string) do
      {:ok, date} -> date
      _ -> nil
    end
  end
end
