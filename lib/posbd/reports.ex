defmodule Posbd.Reports do
  @moduledoc """
  Read-only reporting queries. Every report takes the same `from`/`to`
  (`Date` values, inclusive) so the frontend can drive them all from one
  reusable date-range component (see AGENTS.md §15). Boundaries are
  converted from the business's own timezone to UTC before querying,
  since "today" means something different depending on where the
  business is (AGENTS.md §22) - never assume a fixed offset.
  """

  import Ecto.Query, warn: false

  alias Posbd.Repo
  alias Posbd.Accounts.Scope
  alias Posbd.Billing.{Invoice, InvoiceItem, Payment}
  alias Posbd.Products.{Product, ProductVariant}

  @doc """
  Revenue, tax, discount, invoice count, average sale, and a payment
  method breakdown for completed invoices issued between `from` and `to`
  (inclusive, in the business's own timezone).
  """
  def sales_summary(%Scope{business: business}, from, to) do
    {from_dt, to_dt} = day_range(business, from, to)

    totals =
      completed_invoices(business, from_dt, to_dt)
      |> select([i], %{
        revenue: coalesce(sum(i.total_amount), 0),
        tax: coalesce(sum(i.tax_amount), 0),
        discount: coalesce(sum(i.discount_amount), 0),
        invoice_count: count(i.id)
      })
      |> Repo.one()

    by_payment_method =
      from(p in Payment,
        join: i in Invoice,
        on: i.id == p.invoice_id,
        where: i.business_id == ^business.id and i.status == "completed",
        where: i.issued_at >= ^from_dt and i.issued_at < ^to_dt,
        group_by: p.method,
        select: {p.method, sum(p.amount)}
      )
      |> Repo.all()
      |> Map.new()

    average_sale =
      if totals.invoice_count > 0 do
        totals.revenue |> Decimal.div(Decimal.new(totals.invoice_count)) |> Decimal.round(2)
      else
        Decimal.new(0)
      end

    %{
      from: from,
      to: to,
      revenue: totals.revenue,
      tax: totals.tax,
      discount: totals.discount,
      invoice_count: totals.invoice_count,
      average_sale: average_sale,
      by_payment_method: by_payment_method
    }
  end

  @doc """
  Revenue per calendar day (in the business's own timezone) between
  `from` and `to`, with every day present even if it had zero sales -
  the shape a dashboard trend chart needs without the frontend having to
  fill gaps itself.
  """
  def daily_sales(%Scope{business: business}, from, to) do
    {from_dt, to_dt} = day_range(business, from, to)

    by_day =
      completed_invoices(business, from_dt, to_dt)
      |> select([i], %{issued_at: i.issued_at, total_amount: i.total_amount})
      |> Repo.all()
      |> Enum.group_by(&local_date(&1.issued_at, business.timezone))
      |> Map.new(fn {date, rows} ->
        {date, Enum.reduce(rows, Decimal.new(0), &Decimal.add(&1.total_amount, &2))}
      end)

    for date <- Date.range(from, to) do
      %{date: date, revenue: Map.get(by_day, date, Decimal.new(0))}
    end
  end

  defp local_date(%DateTime{} = dt, timezone) do
    dt |> DateTime.shift_zone!(timezone) |> DateTime.to_date()
  end

  @doc "Best-selling items by revenue for completed invoices in the date range."
  def top_products(%Scope{business: business}, from, to, limit \\ 10) do
    {from_dt, to_dt} = day_range(business, from, to)

    from(item in InvoiceItem,
      join: invoice in Invoice,
      on: invoice.id == item.invoice_id,
      where: invoice.business_id == ^business.id and invoice.status == "completed",
      where: invoice.issued_at >= ^from_dt and invoice.issued_at < ^to_dt,
      group_by: item.name_snapshot,
      order_by: [desc: sum(item.line_total)],
      limit: ^limit,
      select: %{
        name: item.name_snapshot,
        quantity_sold: sum(item.quantity),
        revenue: sum(item.line_total)
      }
    )
    |> Repo.all()
  end

  @doc """
  Current stock levels across simple products and variants, optionally
  filtered to only items at or below their reorder level.
  """
  def stock_report(%Scope{business: business}, opts \\ []) do
    low_stock_only? = Keyword.get(opts, :low_stock_only, false)

    products =
      from(p in Product,
        where: p.business_id == ^business.id and p.has_variants == false,
        select: %{
          id: p.id,
          name: p.name,
          sku: p.sku,
          stock_quantity: p.stock_quantity,
          reorder_level: p.reorder_level
        }
      )
      |> maybe_low_stock_only(low_stock_only?)
      |> Repo.all()

    variants =
      from(v in ProductVariant,
        join: p in Product,
        on: p.id == v.product_id,
        where: v.business_id == ^business.id,
        select: %{
          id: v.id,
          name: p.name,
          sku: v.sku,
          stock_quantity: v.stock_quantity,
          reorder_level: v.reorder_level
        }
      )
      |> maybe_low_stock_only(low_stock_only?)
      |> Repo.all()

    Enum.sort_by(products ++ variants, & &1.name)
  end

  defp maybe_low_stock_only(query, false), do: query

  defp maybe_low_stock_only(query, true),
    do: where(query, [x], x.stock_quantity <= x.reorder_level)

  defp completed_invoices(business, from_dt, to_dt) do
    from(i in Invoice,
      where: i.business_id == ^business.id and i.status == "completed",
      where: i.issued_at >= ^from_dt and i.issued_at < ^to_dt
    )
  end

  defp day_range(business, from, to) do
    from_dt =
      from |> DateTime.new!(~T[00:00:00], business.timezone) |> DateTime.shift_zone!("Etc/UTC")

    to_dt =
      to
      |> Date.add(1)
      |> DateTime.new!(~T[00:00:00], business.timezone)
      |> DateTime.shift_zone!("Etc/UTC")

    {from_dt, to_dt}
  end
end
