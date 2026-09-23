defmodule PosbdWeb.Api.InvoiceJSON do
  alias Posbd.Billing.{Invoice, InvoiceItem, Payment}
  alias PosbdWeb.Api.ProductJSON

  def index(%{data: invoices, page: page, page_size: page_size, total_count: total_count}) do
    %{
      data: Enum.map(invoices, &invoice_summary/1),
      pagination: %{page: page, page_size: page_size, total_count: total_count}
    }
  end

  def show(%{invoice: invoice}), do: %{data: invoice_detail(invoice)}

  defp invoice_summary(%Invoice{} = invoice) do
    %{
      id: invoice.id,
      invoice_number: invoice.invoice_number,
      status: invoice.status,
      payment_status: invoice.payment_status,
      currency: invoice.currency,
      total_amount: ProductJSON.money(invoice.total_amount),
      amount_paid: ProductJSON.money(invoice.amount_paid),
      customer: customer(invoice),
      issued_at: invoice.issued_at
    }
  end

  defp invoice_detail(%Invoice{} = invoice) do
    invoice
    |> invoice_summary()
    |> Map.merge(%{
      subtotal: ProductJSON.money(invoice.subtotal),
      discount_amount: ProductJSON.money(invoice.discount_amount),
      tax_amount: ProductJSON.money(invoice.tax_amount),
      notes: invoice.notes,
      items: Enum.map(loaded(invoice.items), &item_json/1),
      payments: Enum.map(loaded(invoice.payments), &payment_json/1)
    })
  end

  defp customer(%Invoice{customer: %Ecto.Association.NotLoaded{}}), do: nil
  defp customer(%Invoice{customer: nil}), do: nil
  defp customer(%Invoice{customer: c}), do: %{id: c.id, name: c.name, phone: c.phone}

  defp loaded(%Ecto.Association.NotLoaded{}), do: []
  defp loaded(list), do: list

  defp item_json(%InvoiceItem{} = item) do
    %{
      id: item.id,
      product_id: item.product_id,
      variant_id: item.variant_id,
      name: item.name_snapshot,
      quantity: item.quantity,
      unit_price: ProductJSON.money(item.unit_price),
      tax_rate: ProductJSON.money(item.tax_rate),
      discount_amount: ProductJSON.money(item.discount_amount),
      tax_amount: ProductJSON.money(item.tax_amount),
      line_total: ProductJSON.money(item.line_total)
    }
  end

  defp payment_json(%Payment{} = payment) do
    %{
      id: payment.id,
      method: payment.method,
      amount: ProductJSON.money(payment.amount),
      reference: payment.reference,
      received_at: payment.received_at
    }
  end
end
