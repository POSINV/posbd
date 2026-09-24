defmodule Posbd.Customers do
  @moduledoc "Customer records for a business - walk-in billing just skips a customer_id."

  import Ecto.Query, warn: false

  alias Posbd.Repo
  alias Posbd.Accounts.Scope
  alias Posbd.Customers.Customer

  def list_customers(%Scope{business: business}, params \\ %{}) do
    search = params[:search] || params["search"]

    Customer
    |> where([c], c.business_id == ^business.id)
    |> maybe_search(search)
    |> order_by([c], asc: c.name)
    |> Repo.all()
  end

  defp maybe_search(query, nil), do: query
  defp maybe_search(query, ""), do: query

  defp maybe_search(query, term) do
    pattern = "%#{term}%"

    from c in query,
      where: ilike(c.name, ^pattern) or ilike(c.phone, ^pattern) or ilike(c.email, ^pattern)
  end

  def get_customer(%Scope{business: business}, id) do
    Repo.get_by(Customer, id: id, business_id: business.id)
  end

  @doc "Finds a customer by exact phone match, or `nil`. Used by historical bill migration to avoid creating duplicate customers on re-import."
  def find_by_phone(_scope, nil), do: nil
  def find_by_phone(_scope, ""), do: nil

  def find_by_phone(%Scope{business: business}, phone) do
    Repo.get_by(Customer, business_id: business.id, phone: phone)
  end

  def create_customer(%Scope{business: business}, attrs) do
    %Customer{business_id: business.id}
    |> Customer.changeset(attrs)
    |> Repo.insert()
  end

  def update_customer(%Customer{} = customer, attrs) do
    customer
    |> Customer.changeset(attrs)
    |> Repo.update()
  end

  def delete_customer(%Customer{} = customer) do
    Repo.delete(customer)
  end
end
