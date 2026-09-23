defmodule PosbdWeb.Api.InventoryController do
  use PosbdWeb, :controller

  alias Posbd.Inventory
  alias PosbdWeb.Api.{Authorize, TargetLookup}

  action_fallback PosbdWeb.Api.FallbackController

  @doc """
  POST /inventory/movements

  Body: `{"movement": {"product_id" | "variant_id", "movement_type",
  "direction", "quantity", "reference", "notes", "occurred_at"}}`.
  `movement_type` is one of opening_stock/purchase/sale/return/adjustment,
  `direction` is "in" or "out". This one endpoint covers opening stock
  entry too - it's just a movement with movement_type "opening_stock".
  """
  def create(%{assigns: %{current_scope: scope}} = conn, %{"movement" => params}) do
    with :ok <- Authorize.require(scope, "inventory.adjust"),
         {:ok, target} <- TargetLookup.fetch_item(scope, params),
         {:ok, transaction} <- Inventory.record_movement(scope, target, params) do
      conn |> put_status(:created) |> render(:show, transaction: transaction)
    end
  end

  def index(%{assigns: %{current_scope: scope}} = conn, params) do
    with :ok <- Authorize.require(scope, "inventory.view"),
         {:ok, target} <- TargetLookup.target_filter(params) do
      result = Inventory.list_movements(scope, target, params)
      render(conn, :index, result)
    end
  end
end
