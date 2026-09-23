defmodule PosbdWeb.Api.InvoiceController do
  use PosbdWeb, :controller

  alias Posbd.Billing
  alias PosbdWeb.Api.Authorize

  action_fallback PosbdWeb.Api.FallbackController

  def index(%{assigns: %{current_scope: scope}} = conn, params) do
    with :ok <- Authorize.require(scope, "billing.create") do
      render(conn, :index, Billing.list_invoices(scope, params))
    end
  end

  def create(%{assigns: %{current_scope: scope}} = conn, params) do
    with :ok <- Authorize.require(scope, "billing.create"),
         {:ok, invoice} <- Billing.create_invoice(scope, params) do
      conn |> put_status(:created) |> render(:show, invoice: invoice)
    end
  end

  def show(%{assigns: %{current_scope: scope}} = conn, %{"id" => id}) do
    with :ok <- Authorize.require(scope, "billing.create") do
      case Billing.get_invoice(scope, id) do
        nil -> {:error, :not_found}
        invoice -> render(conn, :show, invoice: invoice)
      end
    end
  end

  def add_payment(%{assigns: %{current_scope: scope}} = conn, %{"id" => id, "payment" => params}) do
    with :ok <- Authorize.require(scope, "billing.create"),
         invoice when not is_nil(invoice) <- Billing.get_invoice(scope, id),
         {:ok, updated} <- Billing.add_payment(scope, invoice, params) do
      render(conn, :show, invoice: updated)
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  def cancel(%{assigns: %{current_scope: scope}} = conn, %{"id" => id}) do
    with :ok <- Authorize.require(scope, "billing.cancel"),
         invoice when not is_nil(invoice) <- Billing.get_invoice(scope, id),
         {:ok, updated} <- Billing.cancel_invoice(scope, invoice) do
      render(conn, :show, invoice: updated)
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end
end
