defmodule PosbdWeb.Api.ImportController do
  use PosbdWeb, :controller

  alias Posbd.Imports
  alias PosbdWeb.Api.Authorize

  action_fallback PosbdWeb.Api.FallbackController

  def products_template(conn, _params) do
    send_csv(conn, "products_import_template.csv", Imports.products_template())
  end

  def opening_stock_template(conn, _params) do
    send_csv(conn, "opening_stock_import_template.csv", Imports.opening_stock_template())
  end

  def historical_bills_template(conn, _params) do
    send_csv(conn, "historical_bills_import_template.csv", Imports.historical_bills_template())
  end

  def preview_products(%{assigns: %{current_scope: scope}} = conn, params) do
    with :ok <- Authorize.require(scope, "products.create"),
         {:ok, binary} <- read_upload(params["file"]),
         {:ok, preview} <- Imports.preview_products(scope, binary) do
      render(conn, :preview, preview)
    end
  end

  def commit_products(%{assigns: %{current_scope: scope}} = conn, %{"rows" => rows}) do
    with :ok <- Authorize.require(scope, "products.create") do
      render(conn, :commit, Imports.commit_products(scope, rows))
    end
  end

  def preview_opening_stock(%{assigns: %{current_scope: scope}} = conn, params) do
    with :ok <- Authorize.require(scope, "inventory.adjust"),
         {:ok, binary} <- read_upload(params["file"]),
         {:ok, preview} <- Imports.preview_opening_stock(scope, binary) do
      render(conn, :preview, preview)
    end
  end

  def commit_opening_stock(%{assigns: %{current_scope: scope}} = conn, %{"rows" => rows}) do
    with :ok <- Authorize.require(scope, "inventory.adjust") do
      render(conn, :commit, Imports.commit_opening_stock(scope, rows))
    end
  end

  # Gated the same as the other bulk importers (not "billing.create" -
  # a cashier can ring up a sale but a historical migration is a much
  # bigger, backdated, inventory-bypassing action and shouldn't be
  # available at that tier).
  def preview_historical_bills(%{assigns: %{current_scope: scope}} = conn, params) do
    with :ok <- Authorize.require(scope, "products.create"),
         {:ok, binary} <- read_upload(params["file"]),
         {:ok, preview} <- Imports.preview_historical_bills(scope, binary) do
      render(conn, :preview, preview)
    end
  end

  def commit_historical_bills(%{assigns: %{current_scope: scope}} = conn, %{"rows" => rows}) do
    with :ok <- Authorize.require(scope, "products.create") do
      render(conn, :commit, Imports.commit_historical_bills(scope, rows))
    end
  end

  def history(%{assigns: %{current_scope: scope}} = conn, _params) do
    render(conn, :history, logs: Imports.list_import_logs(scope))
  end

  defp read_upload(%Plug.Upload{path: path}) do
    case File.read(path) do
      {:ok, binary} -> {:ok, binary}
      {:error, _reason} -> {:error, %{message: "Could not read the uploaded file"}}
    end
  end

  defp read_upload(_), do: {:error, %{message: "No file was uploaded (expected a `file` field)"}}

  defp send_csv(conn, filename, csv) do
    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
    |> send_resp(200, csv)
  end
end
