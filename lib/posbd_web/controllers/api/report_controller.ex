defmodule PosbdWeb.Api.ReportController do
  use PosbdWeb, :controller

  alias Posbd.Reports
  alias PosbdWeb.Api.Authorize

  action_fallback PosbdWeb.Api.FallbackController

  def sales_summary(%{assigns: %{current_scope: scope}} = conn, params) do
    with :ok <- Authorize.require(scope, "reports.view"),
         {:ok, from, to} <- parse_range(params) do
      render(conn, :sales_summary, Reports.sales_summary(scope, from, to))
    end
  end

  def daily_sales(%{assigns: %{current_scope: scope}} = conn, params) do
    with :ok <- Authorize.require(scope, "reports.view"),
         {:ok, from, to} <- parse_range(params) do
      render(conn, :daily_sales, days: Reports.daily_sales(scope, from, to))
    end
  end

  def top_products(%{assigns: %{current_scope: scope}} = conn, params) do
    with :ok <- Authorize.require(scope, "reports.view"),
         {:ok, from, to} <- parse_range(params) do
      limit = String.to_integer(params["limit"] || "10")
      render(conn, :top_products, products: Reports.top_products(scope, from, to, limit))
    end
  end

  def stock(%{assigns: %{current_scope: scope}} = conn, params) do
    with :ok <- Authorize.require(scope, "reports.view") do
      low_stock_only = params["low_stock_only"] in ["true", "1"]
      render(conn, :stock, items: Reports.stock_report(scope, low_stock_only: low_stock_only))
    end
  end

  defp parse_range(params) do
    with {:ok, from} <- parse_date(params["from"]),
         {:ok, to} <- parse_date(params["to"]) do
      if Date.compare(from, to) == :gt do
        {:error, %{message: "`from` must be on or before `to`"}}
      else
        {:ok, from, to}
      end
    end
  end

  defp parse_date(nil), do: {:error, %{message: "`from` and `to` (YYYY-MM-DD) are required"}}

  defp parse_date(string) do
    case Date.from_iso8601(string) do
      {:ok, date} -> {:ok, date}
      _ -> {:error, %{message: "invalid date: #{string}"}}
    end
  end
end
