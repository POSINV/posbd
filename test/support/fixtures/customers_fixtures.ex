defmodule Posbd.CustomersFixtures do
  alias Posbd.Accounts.Scope
  alias Posbd.Customers

  def valid_customer_attrs(attrs \\ %{}) do
    Enum.into(attrs, %{name: "Customer #{System.unique_integer()}", phone: "9990001111"})
  end

  def customer_fixture(%Scope{} = scope, attrs \\ %{}) do
    {:ok, customer} = Customers.create_customer(scope, valid_customer_attrs(attrs))
    customer
  end
end
