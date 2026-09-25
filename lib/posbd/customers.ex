defmodule Posbd.Customers do
  @moduledoc """
  Customer records for a business - walk-in billing just skips a
  customer_id. Phase 2 §15/§16/§22/§33 add purchase history, lifetime
  value, and segment classification, all computed fresh from
  `Posbd.Billing`'s invoices rather than a separately-maintained ledger -
  there's no cached total that could drift, so nothing to keep in sync.
  """

  import Ecto.Query, warn: false

  alias Posbd.AuditLogs
  alias Posbd.Repo
  alias Posbd.Accounts.Scope
  alias Posbd.Billing.{Invoice, InvoiceItem}
  alias Posbd.Customers.Customer

  @doc """
  Lists customers with their purchase stats and computed segment. Stats
  come from one aggregate query (not one query per customer - AGENTS.md
  §29), so paging through a large customer list stays cheap. Accepts
  `search` (name/phone/email) and `segment` (filters the *already*
  computed segment, since a segment isn't a stored column).
  """
  def list_customers(%Scope{business: business}, params \\ %{}) do
    search = params[:search] || params["search"]
    segment_filter = params[:segment] || params["segment"]

    stats_by_customer_id = purchase_stats_by_customer(business)

    rows =
      Customer
      |> where([c], c.business_id == ^business.id)
      |> maybe_search(search)
      |> order_by([c], asc: c.name)
      |> Repo.all()
      |> Enum.map(fn customer ->
        stats = Map.get(stats_by_customer_id, customer.id, empty_stats())
        %{customer: customer, stats: Map.put(stats, :segment, segment(stats, customer))}
      end)

    if segment_filter,
      do: Enum.filter(rows, &(to_string(&1.stats.segment) == segment_filter)),
      else: rows
  end

  defp purchase_stats_by_customer(business) do
    from(i in Invoice,
      where:
        i.business_id == ^business.id and i.status != "cancelled" and not is_nil(i.customer_id),
      group_by: i.customer_id,
      select: %{
        customer_id: i.customer_id,
        total_spent: sum(i.total_amount),
        visit_count: count(i.id),
        last_purchase_at: max(i.issued_at),
        outstanding_balance: sum(i.total_amount) - sum(i.amount_paid)
      }
    )
    |> Repo.all()
    |> Map.new(fn row -> {row.customer_id, Map.delete(row, :customer_id)} end)
  end

  defp empty_stats,
    do: %{
      total_spent: Decimal.new(0),
      visit_count: 0,
      last_purchase_at: nil,
      outstanding_balance: Decimal.new(0)
    }

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

  def create_customer(%Scope{} = scope, attrs) do
    %Customer{business_id: scope.business.id}
    |> Customer.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, customer} = ok ->
        AuditLogs.record(scope, "customer.created", "Customer", customer.id, %{
          name: customer.name
        })

        ok

      error ->
        error
    end
  end

  def update_customer(%Scope{} = scope, %Customer{} = customer, attrs) do
    customer
    |> Customer.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, updated} = ok ->
        AuditLogs.record(scope, "customer.updated", "Customer", updated.id, %{})
        ok

      error ->
        error
    end
  end

  def delete_customer(%Scope{} = scope, %Customer{} = customer) do
    Repo.delete(customer)
    |> case do
      {:ok, deleted} = ok ->
        AuditLogs.record(scope, "customer.deleted", "Customer", deleted.id, %{name: deleted.name})
        ok

      error ->
        error
    end
  end

  @doc """
  Full purchase history summary for one customer (Phase 2 §16/§33):
  total spend, visit count, last purchase date, average bill, outstanding
  balance across unpaid/partial invoices, top products, and segment.
  """
  def purchase_summary(%Scope{business: business}, %Customer{} = customer) do
    stats =
      from(i in Invoice,
        where:
          i.business_id == ^business.id and i.customer_id == ^customer.id and
            i.status != "cancelled",
        select: %{
          total_spent: coalesce(sum(i.total_amount), 0),
          visit_count: count(i.id),
          last_purchase_at: max(i.issued_at),
          outstanding_balance: coalesce(sum(i.total_amount) - sum(i.amount_paid), 0)
        }
      )
      |> Repo.one()

    average_bill =
      if stats.visit_count > 0,
        do: stats.total_spent |> Decimal.div(stats.visit_count) |> Decimal.round(2),
        else: Decimal.new(0)

    top_products =
      from(item in InvoiceItem,
        join: i in assoc(item, :invoice),
        where:
          i.business_id == ^business.id and i.customer_id == ^customer.id and
            i.status != "cancelled",
        group_by: item.name_snapshot,
        order_by: [desc: sum(item.quantity)],
        limit: 5,
        select: %{
          name: item.name_snapshot,
          quantity: sum(item.quantity),
          revenue: sum(item.line_total)
        }
      )
      |> Repo.all()

    stats
    |> Map.put(:average_bill, average_bill)
    |> Map.put(:top_products, top_products)
    |> Map.put(:segment, segment(stats, customer))
  end

  # Fixed, currency-agnostic default thresholds for a first pass (Phase 2
  # §22 explicitly allows this: "based on configurable rules where
  # practical"). Making these business-configurable (per-currency
  # thresholds) is a reasonable follow-up once real usage data suggests
  # what the defaults should be.
  @vip_threshold Decimal.new(10_000)
  @high_value_threshold Decimal.new(5_000)
  @inactive_after_days 90
  @new_within_days 30

  @doc "Classifies a customer as :vip, :high_value, :new, :inactive, or :regular from their purchase stats."
  def segment(stats, %Customer{} = customer) do
    now = DateTime.utc_now()

    days_since_purchase =
      stats.last_purchase_at && DateTime.diff(now, stats.last_purchase_at, :day)

    days_since_created = DateTime.diff(now, customer.inserted_at, :day)

    cond do
      Decimal.compare(stats.total_spent, @vip_threshold) != :lt -> :vip
      Decimal.compare(stats.total_spent, @high_value_threshold) != :lt -> :high_value
      is_nil(stats.last_purchase_at) and days_since_created <= @new_within_days -> :new
      is_nil(stats.last_purchase_at) -> :inactive
      days_since_purchase > @inactive_after_days -> :inactive
      stats.visit_count <= 1 and days_since_created <= @new_within_days -> :new
      true -> :regular
    end
  end
end
