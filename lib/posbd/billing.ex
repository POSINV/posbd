defmodule Posbd.Billing do
  @moduledoc """
  Invoices, invoice items, and payments. This is the money boundary of
  the platform (AGENTS.md §53): every price, discount, tax, and total is
  computed here from server-side data (`Pricing.price_for/4`) - a
  client-submitted price is never trusted, only the requested quantity
  and which product/variant is being billed.

  `create_invoice/2` follows the transaction order from AGENTS.md §55
  (invoice -> items -> payments -> inventory) inside a single
  `Repo.transact`, so a partial invoice can never exist.
  """

  import Ecto.Query, warn: false

  alias Posbd.AuditLogs
  alias Posbd.Repo
  alias Posbd.Accounts.Scope
  alias Posbd.Businesses.{Business, Roles}
  alias Posbd.Billing.{Invoice, InvoiceItem, Payment}
  alias Posbd.Customers.Customer
  alias Posbd.Inventory
  alias Posbd.Loyalty
  alias Posbd.Marketing
  alias Posbd.Pricing
  alias Posbd.Products.{Product, ProductVariant}
  alias Posbd.Whatsapp

  @doc """
  Creates a completed invoice from `attrs`:

      %{
        "customer_id" => nil | id,
        "items" => [%{"product_id" | "variant_id" => id, "quantity" => n, "discount_amount" => "0.00"}],
        "payments" => [%{"method" => "cash", "amount" => "500.00", "reference" => nil}],
        "notes" => nil,
        "idempotency_key" => nil | string
      }

  Returns `{:ok, invoice}` with `:items`, `:payments`, and `:customer`
  preloaded, or `{:error, reason}`.
  """
  def create_invoice(
        %Scope{business: business, user: user, membership: membership} = scope,
        attrs
      ) do
    case find_by_idempotency_key(scope, attrs["idempotency_key"]) do
      {:ok, existing} ->
        {:ok, existing}

      :not_found ->
        do_create_invoice(scope, business, user, membership, attrs)
    end
  end

  defp find_by_idempotency_key(_scope, key) when key in [nil, ""], do: :not_found

  defp find_by_idempotency_key(%Scope{business: business}, key) do
    case Repo.get_by(Invoice, business_id: business.id, idempotency_key: key) do
      nil -> :not_found
      invoice -> {:ok, preload_invoice(invoice)}
    end
  end

  defp do_create_invoice(scope, business, user, membership, attrs) do
    with {:ok, lines} <- build_lines(scope, attrs["items"]),
         :ok <- authorize_discounts(membership, lines),
         base_totals <- compute_totals(lines),
         customer <- resolve_customer(business, attrs["customer_id"]),
         {:ok, offer_resolution} <-
           Marketing.resolve(business, customer, attrs["offer_code"], base_totals.total_amount),
         total_after_offer <-
           Decimal.sub(base_totals.total_amount, offer_resolution.discount_amount),
         {:ok, loyalty} <- resolve_loyalty(business, attrs, total_after_offer) do
      result =
        Repo.transact(fn ->
          with {:ok, invoice} <-
                 insert_invoice(business, user, base_totals, offer_resolution, loyalty, attrs),
               {:ok, _items} <- insert_items(invoice, lines),
               {:ok, payments} <- insert_payments(invoice, user, attrs["payments"] || []),
               {:ok, invoice} <- apply_payment_status(invoice, payments),
               :ok <- reduce_inventory(scope, lines, invoice.invoice_number),
               :ok <- apply_offer_redemption(business, invoice, offer_resolution),
               :ok <- apply_loyalty_ledger(scope, invoice, loyalty) do
            {:ok, preload_invoice(invoice)}
          end
        end)

      case result do
        {:ok, invoice} = ok ->
          discount_total =
            lines |> Enum.map(& &1.discount_amount) |> Enum.reduce(Decimal.new(0), &Decimal.add/2)

          AuditLogs.record(scope, "invoice.created", "Invoice", invoice.id, %{
            invoice_number: invoice.invoice_number,
            total_amount: Decimal.to_string(invoice.total_amount),
            discount_amount: Decimal.to_string(discount_total)
          })

          Whatsapp.notify_invoice_created(business, invoice)
          Whatsapp.notify_loyalty_earned(business, invoice)

          ok

        error ->
          error
      end
    end
  end

  # ---- loyalty (Phase 2 §17-§20) -----------------------------------------

  # Resolves how many points this bill will earn/redeem *before* the
  # invoice is inserted, since the redemption discount changes the
  # invoice's own `total_amount`. Returns a plain map, never touches the
  # DB (the actual ledger writes happen inside the transaction, once the
  # invoice - and therefore its id - exists; see `apply_loyalty_ledger/3`).
  defp resolve_loyalty(business, attrs, base_total) do
    customer_id = blank_to_nil(attrs["customer_id"])
    requested = attrs["redeem_points"]

    cond do
      requested in [nil, 0, "0", ""] ->
        points_to_earn =
          if customer_id && Loyalty.active?(business) do
            Loyalty.points_for_amount(Loyalty.get_program(business), base_total)
          else
            0
          end

        {:ok,
         %{
           customer_id: customer_id,
           points_to_redeem: 0,
           redemption_value: Decimal.new(0),
           points_to_earn: points_to_earn
         }}

      is_nil(customer_id) ->
        {:error, %{message: "A customer must be selected to redeem loyalty points"}}

      not Loyalty.active?(business) ->
        {:error, %{message: "Loyalty program is not enabled for this business"}}

      true ->
        with %Customer{} = customer <-
               Repo.get_by(Customer, id: customer_id, business_id: business.id) ||
                 {:error, %{message: "Customer not found"}} do
          program = Loyalty.get_program(business)
          requested_points = to_integer(requested, 0)

          with {:ok, %{points: points, value: value}} <-
                 Loyalty.quote_redemption(
                   program,
                   customer.loyalty_points_balance,
                   requested_points,
                   base_total
                 ) do
            net_total = Decimal.sub(base_total, value)
            points_to_earn = Loyalty.points_for_amount(program, net_total)

            {:ok,
             %{
               customer_id: customer_id,
               points_to_redeem: points,
               redemption_value: value,
               points_to_earn: points_to_earn
             }}
          end
        end
    end
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(id), do: id

  defp apply_loyalty_ledger(_scope, _invoice, %{points_to_redeem: 0, points_to_earn: 0}), do: :ok

  defp apply_loyalty_ledger(scope, invoice, loyalty) do
    with :ok <- maybe_redeem(scope, invoice, loyalty),
         :ok <- maybe_earn(scope, invoice, loyalty) do
      :ok
    end
  end

  defp maybe_redeem(_scope, _invoice, %{points_to_redeem: 0}), do: :ok

  defp maybe_redeem(scope, invoice, loyalty) do
    write_loyalty_entry(scope, invoice, loyalty.customer_id, "redeem", -loyalty.points_to_redeem)
  end

  defp maybe_earn(_scope, _invoice, %{points_to_earn: 0}), do: :ok

  defp maybe_earn(scope, invoice, loyalty) do
    write_loyalty_entry(scope, invoice, loyalty.customer_id, "earn", loyalty.points_to_earn)
  end

  defp write_loyalty_entry(scope, invoice, customer_id, entry_type, signed_points) do
    description =
      case entry_type do
        "redeem" -> "Redeemed on invoice #{invoice.invoice_number}"
        "earn" -> "Earned on invoice #{invoice.invoice_number}"
      end

    case Loyalty.record_entry(scope, %{
           "customer_id" => customer_id,
           "invoice_id" => invoice.id,
           "entry_type" => entry_type,
           "points" => signed_points,
           "description" => description
         }) do
      {:ok, _entry} -> :ok
      {:error, _} = error -> error
    end
  end

  @doc """
  Creates a historical invoice from already-migrated data (AGENTS.md §14,
  §27) - used by `Posbd.Imports.commit_historical_bills/2`, never called
  directly from the live billing screen.

      %{
        "invoice_number" => "OLD-1001",
        "issued_at" => ~U[2025-01-15 00:00:00Z],
        "customer_id" => nil | id,
        "items" => [%{"product_id" => id, "quantity" => n, "unit_price" => "..", "discount_amount" => "..", "tax_amount" => "..", "tax_rate" => ".."}],
        "payments" => [%{"method" => "cash", "amount" => "..", "reference" => nil}],
        "notes" => nil
      }

  Unlike `create_invoice/2`: the caller supplies `invoice_number` and each
  item's `unit_price`/`tax_amount` directly instead of them being computed
  from live pricing (the old system's own numbers are the source of truth
  for a sale that already happened), and inventory is never touched -
  that stock is already accounted for in whatever opening stock figure
  was imported separately, so deducting it again here would corrupt the
  current count.
  """
  def import_historical_invoice(%Scope{business: business, user: user} = scope, attrs) do
    # A date-only historical timestamp has no microsecond component, but
    # `:utc_datetime_usec` requires exactly 6-digit precision - normalize
    # here so every caller (not just the CSV importer) gets this for free.
    attrs = Map.put(attrs, "issued_at", to_usec_datetime(attrs["issued_at"]))

    with {:ok, lines} <- build_historical_lines(scope, attrs["items"]) do
      Repo.transact(fn ->
        with {:ok, invoice} <- insert_historical_invoice(business, user, lines, attrs),
             {:ok, _items} <- insert_items(invoice, lines),
             {:ok, payments} <-
               insert_payments(invoice, user, attrs["payments"] || [], attrs["issued_at"]),
             {:ok, invoice} <- apply_payment_status(invoice, payments) do
          {:ok, preload_invoice(invoice)}
        end
      end)
    end
  end

  defp to_usec_datetime(%DateTime{microsecond: {microsecond, _precision}} = dt) do
    %{dt | microsecond: {microsecond, 6}}
  end

  defp build_historical_lines(scope, items) do
    items
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
      case build_historical_line(scope, item) do
        {:ok, line} -> {:cont, {:ok, [line | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, lines} -> {:ok, Enum.reverse(lines)}
      error -> error
    end
  end

  defp build_historical_line(scope, item) do
    with {:ok, target} <- fetch_target(scope, item),
         {:ok, quantity} <- fetch_quantity(item) do
      unit_price = to_decimal(item["unit_price"])
      discount_amount = to_decimal(item["discount_amount"])
      tax_amount = to_decimal(item["tax_amount"])
      tax_rate = to_decimal(item["tax_rate"])
      subtotal = Decimal.mult(unit_price, quantity)
      line_total = subtotal |> Decimal.sub(discount_amount) |> Decimal.add(tax_amount)

      {:ok,
       %{
         target: target,
         quantity: quantity,
         name_snapshot: name_snapshot(target),
         unit_price: unit_price,
         tax_rate: tax_rate,
         discount_amount: discount_amount,
         subtotal: subtotal,
         tax_amount: tax_amount,
         line_total: line_total
       }}
    end
  end

  defp insert_historical_invoice(business, user, lines, attrs) do
    subtotal = Enum.reduce(lines, Decimal.new(0), &Decimal.add(&1.subtotal, &2))
    discount_amount = Enum.reduce(lines, Decimal.new(0), &Decimal.add(&1.discount_amount, &2))
    tax_amount = Enum.reduce(lines, Decimal.new(0), &Decimal.add(&1.tax_amount, &2))
    total_amount = Enum.reduce(lines, Decimal.new(0), &Decimal.add(&1.line_total, &2))

    %Invoice{}
    |> Invoice.build_changeset(%{
      business_id: business.id,
      customer_id: attrs["customer_id"],
      created_by_id: user.id,
      invoice_number: attrs["invoice_number"],
      source: "migrated",
      currency: business.currency,
      subtotal: subtotal,
      discount_amount: discount_amount,
      tax_amount: tax_amount,
      total_amount: total_amount,
      notes: attrs["notes"],
      issued_at: attrs["issued_at"]
    })
    |> Repo.insert()
  end

  defp authorize_discounts(membership, lines) do
    any_discount? = Enum.any?(lines, fn l -> Decimal.positive?(l.discount_amount) end)

    if any_discount? and not Roles.can?(membership, "billing.discount") do
      {:error, :unauthorized}
    else
      :ok
    end
  end

  # ---- line pricing (the centralized money math) ----------------------

  defp build_lines(_scope, items) when items in [nil, []],
    do: {:error, %{message: "Invoice must have at least one item"}}

  defp build_lines(scope, items) do
    items
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
      case build_line(scope, item) do
        {:ok, line} -> {:cont, {:ok, [line | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, lines} -> {:ok, Enum.reverse(lines)}
      error -> error
    end
  end

  defp build_line(scope, item) do
    with {:ok, target} <- fetch_target(scope, item),
         {:ok, quantity} <- fetch_quantity(item) do
      %{unit_price: unit_price} = Pricing.price_for(scope, target, quantity)
      tax_rate = target.tax_rate
      requested_discount = to_decimal(item["discount_amount"])

      line_subtotal = Decimal.mult(unit_price, quantity)
      discount = requested_discount |> Decimal.min(line_subtotal) |> Decimal.max(Decimal.new(0))
      taxable = Decimal.sub(line_subtotal, discount)
      tax_amount = taxable |> Decimal.mult(tax_rate) |> Decimal.div(100) |> Decimal.round(2)
      line_total = Decimal.add(taxable, tax_amount)

      {:ok,
       %{
         target: target,
         quantity: quantity,
         name_snapshot: name_snapshot(target),
         unit_price: unit_price,
         tax_rate: tax_rate,
         discount_amount: discount,
         subtotal: line_subtotal,
         tax_amount: tax_amount,
         line_total: line_total
       }}
    end
  end

  defp fetch_target(scope, %{"product_id" => id}) when is_binary(id) and id != "" do
    case Repo.get_by(Product, id: id, business_id: scope.business.id) do
      nil -> {:error, %{message: "Product #{id} not found"}}
      product -> {:ok, product}
    end
  end

  defp fetch_target(scope, %{"variant_id" => id}) when is_binary(id) and id != "" do
    ProductVariant
    |> Repo.get_by(id: id, business_id: scope.business.id)
    |> case do
      nil -> {:error, %{message: "Variant #{id} not found"}}
      variant -> {:ok, Repo.preload(variant, attribute_values: :attribute)}
    end
  end

  defp fetch_target(_scope, _item),
    do: {:error, %{message: "Each item needs a product_id or variant_id"}}

  defp fetch_quantity(%{"quantity" => qty}) when is_integer(qty) and qty > 0, do: {:ok, qty}

  defp fetch_quantity(%{"quantity" => qty}) when is_binary(qty) do
    case Integer.parse(qty) do
      {n, _} when n > 0 -> {:ok, n}
      _ -> {:error, %{message: "quantity must be a positive integer"}}
    end
  end

  defp fetch_quantity(_item), do: {:error, %{message: "quantity must be a positive integer"}}

  defp name_snapshot(%Product{} = p), do: p.name

  defp name_snapshot(%ProductVariant{} = v) do
    attrs = Enum.map_join(v.attribute_values, ", ", & &1.value)
    if attrs == "", do: v.sku || "Variant", else: attrs
  end

  defp to_decimal(nil), do: Decimal.new(0)
  defp to_decimal(""), do: Decimal.new(0)
  defp to_decimal(%Decimal{} = d), do: d
  defp to_decimal(value) when is_binary(value), do: Decimal.new(value)
  defp to_decimal(value) when is_integer(value), do: Decimal.new(value)
  defp to_decimal(value) when is_float(value), do: Decimal.from_float(value)

  # ---- persistence -------------------------------------------------------

  defp compute_totals(lines) do
    %{
      subtotal: Enum.reduce(lines, Decimal.new(0), &Decimal.add(&1.subtotal, &2)),
      discount_amount: Enum.reduce(lines, Decimal.new(0), &Decimal.add(&1.discount_amount, &2)),
      tax_amount: Enum.reduce(lines, Decimal.new(0), &Decimal.add(&1.tax_amount, &2)),
      total_amount: Enum.reduce(lines, Decimal.new(0), &Decimal.add(&1.line_total, &2))
    }
  end

  defp insert_invoice(business, user, totals, offer_resolution, loyalty, attrs) do
    total_amount =
      totals.total_amount
      |> Decimal.sub(offer_resolution.discount_amount)
      |> Decimal.sub(loyalty.redemption_value)

    with {:ok, invoice_number} <- next_invoice_number(business) do
      %Invoice{}
      |> Invoice.build_changeset(%{
        business_id: business.id,
        customer_id: attrs["customer_id"],
        created_by_id: user.id,
        invoice_number: invoice_number,
        currency: business.currency,
        subtotal: totals.subtotal,
        discount_amount: totals.discount_amount,
        tax_amount: totals.tax_amount,
        total_amount: total_amount,
        offer_id: offer_resolution.offer && offer_resolution.offer.id,
        offer_discount_amount: offer_resolution.discount_amount,
        loyalty_points_redeemed: loyalty.points_to_redeem,
        loyalty_points_earned: loyalty.points_to_earn,
        loyalty_discount_amount: loyalty.redemption_value,
        notes: attrs["notes"],
        idempotency_key: attrs["idempotency_key"],
        issued_at: DateTime.utc_now()
      })
      |> Repo.insert()
    end
  end

  defp apply_offer_redemption(_business, _invoice, %{offer: nil}), do: :ok

  defp apply_offer_redemption(business, invoice, %{offer: offer, discount_amount: discount_amount}) do
    case Marketing.record_redemption(
           business,
           offer,
           invoice.customer_id,
           invoice.id,
           discount_amount
         ) do
      {:ok, _redemption} -> :ok
      {:error, _} = error -> error
    end
  end

  defp resolve_customer(_business, id) when id in [nil, ""], do: nil
  defp resolve_customer(business, id), do: Repo.get_by(Customer, id: id, business_id: business.id)

  defp next_invoice_number(business) do
    # `select` (not a `:returning` opt - update_all has none) is what makes
    # Postgres append RETURNING, giving us the post-increment value in one
    # atomic round trip so concurrent billing requests can't collide.
    {1, [number]} =
      from(b in Business, where: b.id == ^business.id, select: b.next_invoice_number)
      |> Repo.update_all(inc: [next_invoice_number: 1])

    padded = number |> Integer.to_string() |> String.pad_leading(6, "0")
    {:ok, business.invoice_prefix <> padded}
  end

  defp insert_items(invoice, lines) do
    Enum.reduce_while(lines, {:ok, []}, fn line, {:ok, acc} ->
      {product_id, variant_id} =
        case line.target do
          %Product{id: id} -> {id, nil}
          %ProductVariant{id: id} -> {nil, id}
        end

      fields = %{
        invoice_id: invoice.id,
        product_id: product_id,
        variant_id: variant_id,
        name_snapshot: line.name_snapshot,
        quantity: line.quantity,
        unit_price: line.unit_price,
        tax_rate: line.tax_rate,
        discount_amount: line.discount_amount,
        tax_amount: line.tax_amount,
        line_total: line.line_total
      }

      case %InvoiceItem{} |> InvoiceItem.build_changeset(fields) |> Repo.insert() do
        {:ok, item} -> {:cont, {:ok, [item | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, items} -> {:ok, Enum.reverse(items)}
      error -> error
    end
  end

  defp insert_payments(invoice, user, payments, received_at \\ nil)
  defp insert_payments(_invoice, _user, [], _received_at), do: {:ok, []}

  defp insert_payments(invoice, user, payments, received_at) do
    now = received_at || DateTime.utc_now()

    Enum.reduce_while(payments, {:ok, []}, fn payment, {:ok, acc} ->
      fields = %{
        invoice_id: invoice.id,
        recorded_by_id: user.id,
        method: payment["method"],
        amount: to_decimal(payment["amount"]),
        reference: payment["reference"],
        received_at: now
      }

      case %Payment{} |> Payment.build_changeset(fields) |> Repo.insert() do
        {:ok, p} -> {:cont, {:ok, [p | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, ps} -> {:ok, Enum.reverse(ps)}
      error -> error
    end
  end

  defp apply_payment_status(invoice, payments) do
    amount_paid = Enum.reduce(payments, Decimal.new(0), &Decimal.add(&1.amount, &2))

    payment_status =
      cond do
        Decimal.compare(amount_paid, invoice.total_amount) != :lt -> "paid"
        Decimal.positive?(amount_paid) -> "partial"
        true -> "unpaid"
      end

    invoice
    |> Invoice.payment_recorded_changeset(amount_paid, payment_status)
    |> Repo.update()
  end

  defp reduce_inventory(scope, lines, invoice_number) do
    Enum.reduce_while(lines, :ok, fn line, :ok ->
      case Inventory.record_movement(scope, line.target, %{
             "movement_type" => "sale",
             "direction" => "out",
             "quantity" => line.quantity,
             "reference" => invoice_number
           }) do
        {:ok, _} -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  # ---- reads / additional payments / cancel ------------------------------

  def list_invoices(%Scope{business: business}, params \\ %{}) do
    page = max(to_integer(params[:page] || params["page"], 1), 1)
    page_size = min(to_integer(params[:page_size] || params["page_size"], 25), 100)

    base_query =
      Invoice
      |> where([i], i.business_id == ^business.id)
      |> maybe_filter_customer(params[:customer_id] || params["customer_id"])
      |> maybe_filter_status(params[:status] || params["status"])

    total_count = base_query |> select(count()) |> Repo.one()

    invoices =
      base_query
      |> order_by([i], desc: i.issued_at)
      |> limit(^page_size)
      |> offset(^((page - 1) * page_size))
      |> preload([:customer])
      |> Repo.all()

    %{data: invoices, page: page, page_size: page_size, total_count: total_count}
  end

  defp maybe_filter_customer(query, nil), do: query
  defp maybe_filter_customer(query, ""), do: query
  defp maybe_filter_customer(query, id), do: where(query, [i], i.customer_id == ^id)

  defp maybe_filter_status(query, nil), do: query
  defp maybe_filter_status(query, ""), do: query
  defp maybe_filter_status(query, status), do: where(query, [i], i.status == ^status)

  defp to_integer(nil, default), do: default

  defp to_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> default
    end
  end

  defp to_integer(value, _default) when is_integer(value), do: value

  def get_invoice(%Scope{business: business}, id) do
    case Repo.get_by(Invoice, id: id, business_id: business.id) do
      nil -> nil
      invoice -> preload_invoice(invoice)
    end
  end

  defp preload_invoice(invoice) do
    Repo.preload(invoice, [
      :customer,
      :payments,
      items: [:product, variant: [attribute_values: :attribute]]
    ])
  end

  @doc "Records an additional payment against an existing invoice (settling a partial/credit sale)."
  def add_payment(%Scope{business: business, user: user}, %Invoice{} = invoice, attrs) do
    if invoice.status == "cancelled" do
      {:error, %{message: "Cannot record a payment against a cancelled invoice"}}
    else
      result =
        Repo.transact(fn ->
          with {:ok, payment} <-
                 %Payment{}
                 |> Payment.build_changeset(%{
                   invoice_id: invoice.id,
                   recorded_by_id: user.id,
                   method: attrs["method"],
                   amount: to_decimal(attrs["amount"]),
                   reference: attrs["reference"],
                   received_at: DateTime.utc_now()
                 })
                 |> Repo.insert(),
               new_total <- Decimal.add(invoice.amount_paid, payment.amount),
               payment_status <-
                 if(Decimal.compare(new_total, invoice.total_amount) != :lt,
                   do: "paid",
                   else: "partial"
                 ),
               {:ok, invoice} <-
                 invoice
                 |> Invoice.payment_recorded_changeset(new_total, payment_status)
                 |> Repo.update() do
            {:ok, {preload_invoice(invoice), payment}}
          end
        end)

      case result do
        {:ok, {invoice, payment}} ->
          Whatsapp.notify_payment_recorded(business, invoice, payment)
          {:ok, invoice}

        error ->
          error
      end
    end
  end

  @doc """
  Cancels/voids an invoice and reverses the stock it took out (a "return"
  movement per item), matching AGENTS.md §14 (invoice cancellation/void).
  Payments already received are left as-is; a refund is a separate,
  future concern.
  """
  def cancel_invoice(%Scope{} = scope, %Invoice{} = invoice) do
    if invoice.status == "cancelled" do
      {:error, %{message: "Invoice is already cancelled"}}
    else
      invoice = preload_invoice(invoice)

      result =
        Repo.transact(fn ->
          with :ok <- restore_inventory(scope, invoice),
               {:ok, invoice} <- invoice |> Invoice.status_changeset("cancelled") |> Repo.update() do
            {:ok, preload_invoice(invoice)}
          end
        end)

      case result do
        {:ok, cancelled} = ok ->
          AuditLogs.record(scope, "invoice.cancelled", "Invoice", cancelled.id, %{
            invoice_number: cancelled.invoice_number
          })

          ok

        error ->
          error
      end
    end
  end

  # A migrated (historical) invoice never touched live inventory when it
  # was imported - the stock it represents is already reflected in
  # whatever opening stock figure was imported separately - so cancelling
  # one must never add stock back either, or the current count would be
  # inflated.
  defp restore_inventory(_scope, %Invoice{source: "migrated"}), do: :ok

  defp restore_inventory(scope, invoice) do
    Enum.reduce_while(invoice.items, :ok, fn item, :ok ->
      case item.product || item.variant do
        # The product/variant was deleted after the sale (FK nilified) -
        # there's nothing left to restore stock to, so just skip it.
        nil ->
          {:cont, :ok}

        target ->
          case Inventory.record_movement(scope, target, %{
                 "movement_type" => "return",
                 "direction" => "in",
                 "quantity" => item.quantity,
                 "reference" => invoice.invoice_number
               }) do
            {:ok, _} -> {:cont, :ok}
            error -> {:halt, error}
          end
      end
    end)
  end
end
