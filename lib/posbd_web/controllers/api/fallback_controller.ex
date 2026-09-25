defmodule PosbdWeb.Api.FallbackController do
  use PosbdWeb, :controller

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: PosbdWeb.Api.ChangesetJSON)
    |> render(:error, changeset: changeset)
  end

  def call(conn, {:error, :unauthorized}) do
    conn
    |> put_status(:forbidden)
    |> json(%{error: %{message: "You do not have permission to perform this action"}})
  end

  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> json(%{error: %{message: "Not found"}})
  end

  def call(conn, {:error, :customer_not_found}) do
    conn
    |> put_status(:not_found)
    |> json(%{error: %{message: "Customer not found"}})
  end

  def call(conn, {:error, %{message: message}}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: %{message: message}})
  end
end
