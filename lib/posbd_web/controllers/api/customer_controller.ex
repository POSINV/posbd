defmodule PosbdWeb.Api.CustomerController do
  use PosbdWeb, :controller

  alias Posbd.Customers
  alias PosbdWeb.Api.Authorize

  action_fallback PosbdWeb.Api.FallbackController

  def index(%{assigns: %{current_scope: scope}} = conn, params) do
    render(conn, :index, customers: Customers.list_customers(scope, params))
  end

  def create(%{assigns: %{current_scope: scope}} = conn, %{"customer" => params}) do
    with :ok <- Authorize.require(scope, "customers.manage"),
         {:ok, customer} <- Customers.create_customer(scope, params) do
      conn |> put_status(:created) |> render(:show, customer: customer)
    end
  end

  def show(%{assigns: %{current_scope: scope}} = conn, %{"id" => id}) do
    case Customers.get_customer(scope, id) do
      nil -> {:error, :not_found}
      customer -> render(conn, :show, customer: customer)
    end
  end

  def update(%{assigns: %{current_scope: scope}} = conn, %{"id" => id, "customer" => params}) do
    with :ok <- Authorize.require(scope, "customers.manage"),
         customer when not is_nil(customer) <- Customers.get_customer(scope, id),
         {:ok, updated} <- Customers.update_customer(customer, params) do
      render(conn, :show, customer: updated)
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  def delete(%{assigns: %{current_scope: scope}} = conn, %{"id" => id}) do
    with :ok <- Authorize.require(scope, "customers.manage"),
         customer when not is_nil(customer) <- Customers.get_customer(scope, id),
         {:ok, _} <- Customers.delete_customer(customer) do
      send_resp(conn, :no_content, "")
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end
end
