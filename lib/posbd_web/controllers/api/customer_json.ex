defmodule PosbdWeb.Api.CustomerJSON do
  alias Posbd.Customers.Customer

  def index(%{customers: customers}), do: %{data: Enum.map(customers, &customer_json/1)}
  def show(%{customer: customer}), do: %{data: customer_json(customer)}

  defp customer_json(%Customer{} = customer) do
    %{
      id: customer.id,
      name: customer.name,
      phone: customer.phone,
      email: customer.email,
      address: customer.address,
      notes: customer.notes
    }
  end
end
