defmodule PosbdWeb.Api.CustomerJSON do
  alias Posbd.Customers.Customer
  alias PosbdWeb.Api.ProductJSON

  def index(%{rows: rows}), do: %{data: Enum.map(rows, &row_json/1)}
  def show(%{customer: customer}), do: %{data: customer_json(customer)}
  def summary(%{summary: summary}), do: %{data: summary_json(summary)}

  defp row_json(%{customer: customer, stats: stats}) do
    customer_json(customer)
    |> Map.merge(%{
      total_spent: ProductJSON.money(stats.total_spent),
      visit_count: stats.visit_count,
      last_purchase_at: stats.last_purchase_at,
      outstanding_balance: ProductJSON.money(stats.outstanding_balance),
      segment: stats.segment
    })
  end

  defp customer_json(%Customer{} = customer) do
    %{
      id: customer.id,
      name: customer.name,
      phone: customer.phone,
      email: customer.email,
      address: customer.address,
      notes: customer.notes,
      date_of_birth: customer.date_of_birth,
      preferred_language: customer.preferred_language,
      customer_type: customer.customer_type,
      accepts_transactional_messages: customer.accepts_transactional_messages,
      accepts_promotional_messages: customer.accepts_promotional_messages,
      loyalty_points_balance: customer.loyalty_points_balance
    }
  end

  defp summary_json(summary) do
    %{
      total_spent: ProductJSON.money(summary.total_spent),
      visit_count: summary.visit_count,
      last_purchase_at: summary.last_purchase_at,
      average_bill: ProductJSON.money(summary.average_bill),
      outstanding_balance: ProductJSON.money(summary.outstanding_balance),
      segment: summary.segment,
      top_products:
        Enum.map(summary.top_products, fn p ->
          %{name: p.name, quantity: p.quantity, revenue: ProductJSON.money(p.revenue)}
        end)
    }
  end
end
