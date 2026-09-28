defmodule PosbdWeb.Api.OfferController do
  use PosbdWeb, :controller

  alias Posbd.Marketing
  alias PosbdWeb.Api.Authorize

  action_fallback PosbdWeb.Api.FallbackController

  def index(%{assigns: %{current_scope: scope}} = conn, _params) do
    with :ok <- Authorize.require(scope, "offers.manage") do
      render(conn, :index, offers: Marketing.list_offers(scope))
    end
  end

  def show(%{assigns: %{current_scope: scope}} = conn, %{"id" => id}) do
    with :ok <- Authorize.require(scope, "offers.manage") do
      case Marketing.get_offer(scope, id) do
        nil ->
          {:error, :not_found}

        offer ->
          render(conn, :show,
            offer: offer,
            performance: Marketing.offer_performance(scope, offer)
          )
      end
    end
  end

  def create(%{assigns: %{current_scope: scope}} = conn, %{"offer" => attrs}) do
    with :ok <- Authorize.require(scope, "offers.manage"),
         {:ok, offer} <- Marketing.create_offer(scope, attrs) do
      conn |> put_status(:created) |> render(:show, offer: offer, performance: nil)
    end
  end

  def update(%{assigns: %{current_scope: scope}} = conn, %{"id" => id, "offer" => attrs}) do
    with :ok <- Authorize.require(scope, "offers.manage"),
         offer when not is_nil(offer) <- Marketing.get_offer(scope, id),
         {:ok, updated} <- Marketing.update_offer(scope, offer, attrs) do
      render(conn, :show,
        offer: updated,
        performance: Marketing.offer_performance(scope, updated)
      )
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end
end
