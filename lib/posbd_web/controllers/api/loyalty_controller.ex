defmodule PosbdWeb.Api.LoyaltyController do
  use PosbdWeb, :controller

  alias Posbd.Customers
  alias Posbd.Loyalty
  alias PosbdWeb.Api.Authorize

  action_fallback PosbdWeb.Api.FallbackController

  def show_program(%{assigns: %{current_scope: %{business: business} = scope}} = conn, _params) do
    with :ok <- Authorize.require(scope, "settings.manage") do
      render(conn, :program,
        program: Loyalty.get_program(business),
        active: Loyalty.active?(business)
      )
    end
  end

  def update_program(%{assigns: %{current_scope: scope}} = conn, %{"program" => attrs}) do
    with :ok <- Authorize.require(scope, "settings.manage"),
         {:ok, program} <- Loyalty.upsert_program(scope, attrs) do
      render(conn, :program, program: program, active: Loyalty.active?(scope.business))
    end
  end

  def ledger(%{assigns: %{current_scope: scope}} = conn, %{"id" => customer_id} = params) do
    with :ok <- Authorize.require(scope, "customers.view"),
         %Customers.Customer{} = customer <- Customers.get_customer(scope, customer_id) do
      result = Loyalty.list_ledger(scope, customer_id, params)
      render(conn, :ledger, Map.put(result, :balance, customer.loyalty_points_balance))
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end
end
