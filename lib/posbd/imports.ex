defmodule Posbd.Imports do
  @moduledoc """
  Bulk import for products and opening stock (AGENTS.md §11, §27, §28).

  Every import is two calls: `preview_*` parses the uploaded file and
  validates every row *without writing anything*, returning per-row
  errors in the same `%{field => [messages]}` shape the rest of the API
  uses; `commit_*` takes back exactly the rows the frontend marked valid
  and creates them through the same `Categories`/`Products`/`Inventory`
  contexts the regular API uses - so an imported product is validated
  and created identically to one entered by hand, no separate code path
  to drift out of sync (§52).

  Scope: simple (non-variant) products only for now - a variant CSV
  needs a different column scheme (one row per variant with attribute
  columns) and is a deliberate follow-up, not built here.

  Historical bill import (AGENTS.md §14) follows the same two-call shape
  but groups CSV rows by `invoice_number` into one invoice per group
  (a row is one line item), since a historical bill is created or
  rejected as a whole through `Billing.import_historical_invoice/2` -
  never partially. It never touches inventory (see AGENTS.md §27 - a
  migration must not corrupt current stock) and requires every SKU to
  already exist, so run the product and opening stock imports first.
  """

  import Ecto.Query, warn: false

  alias Posbd.AuditLogs
  alias Posbd.Billing
  alias Posbd.Billing.{Invoice, Payment}
  alias Posbd.Customers
  alias Posbd.Repo
  alias Posbd.Accounts.Scope
  alias Posbd.Categories.Category
  alias Posbd.Imports.{CSV, ImportLog}
  alias Posbd.Inventory
  alias Posbd.Products
  alias Posbd.Products.Product

  ## Templates

  def products_template do
    CSV.to_csv([
      ~w(name category sku barcode brand unit purchase_price selling_price mrp tax_rate reorder_level opening_stock),
      [
        "Cotton T-Shirt",
        "Men's Wear",
        "TS-001",
        "8901234500001",
        "Acme",
        "pcs",
        "150.00",
        "299.00",
        "349.00",
        "5",
        "10",
        "25"
      ]
    ])
  end

  def opening_stock_template do
    CSV.to_csv([
      ~w(sku quantity purchase_price selling_price reference),
      ["TS-001", "50", "150.00", "299.00", "Opening balance"]
    ])
  end

  def historical_bills_template do
    CSV.to_csv([
      ~w(invoice_number date customer_name customer_phone sku quantity unit_price
         discount_amount tax_amount amount_paid payment_method notes),
      [
        "OLD-1001",
        "2025-01-15",
        "Ramesh Kumar",
        "9876500000",
        "TS-001",
        "2",
        "299.00",
        "0",
        "0",
        "598.00",
        "cash",
        "Migrated from old system"
      ],
      ["OLD-1001", "", "", "", "MED-01", "1", "45.00", "0", "0", "", "", ""],
      [
        "OLD-1002",
        "2025-01-16",
        "",
        "",
        "GRO-05",
        "5",
        "60.00",
        "0",
        "0",
        "150.00",
        "upi",
        "Partially paid"
      ]
    ])
  end

  ## Products

  def preview_products(%Scope{business: business}, binary) do
    with {:ok, rows} <- CSV.parse(binary) do
      categories = categories_by_name(business)
      existing_skus = existing_skus(business)

      {results, _seen} =
        Enum.map_reduce(rows, MapSet.new(), fn row, seen ->
          {result, seen} = validate_product_row(row, categories, existing_skus, seen)
          {result, seen}
        end)

      {:ok, summarize(results)}
    end
  end

  def commit_products(%Scope{business: business} = scope, rows) when is_list(rows) do
    categories = categories_by_name(business)
    existing_skus = existing_skus(business)

    {outcomes, _seen} =
      Enum.map_reduce(rows, MapSet.new(), fn attrs, seen ->
        row = %{row_number: attrs["row_number"] || attrs[:row_number], fields: attrs}
        {validated, seen} = validate_product_row(row, categories, existing_skus, seen)

        outcome =
          if validated.valid do
            create_product_from_row(scope, validated)
          else
            {:error, %{row_number: validated.row_number, errors: validated.errors}}
          end

        {outcome, seen}
      end)

    {created, failed} = split_outcomes(outcomes)
    log_import(scope, "products", length(rows), created, length(failed))
    %{created: created, failed: failed}
  end

  defp create_product_from_row(%Scope{} = scope, %{data: data}) do
    with {:ok, product} <-
           Products.create_product(scope, %{
             name: data.name,
             category_id: data.category_id,
             sku: data.sku,
             barcode: data.barcode,
             brand: data.brand,
             unit: data.unit,
             purchase_price: data.purchase_price,
             selling_price: data.selling_price,
             mrp: data.mrp,
             tax_rate: data.tax_rate,
             reorder_level: data.reorder_level
           }) do
      if data.opening_stock && data.opening_stock > 0 do
        Inventory.record_movement(scope, product, %{
          "movement_type" => "opening_stock",
          "direction" => "in",
          "quantity" => data.opening_stock,
          "reference" => "Bulk import"
        })
      end

      :ok
    else
      {:error, changeset} ->
        {:error, %{row_number: data.row_number, errors: changeset_errors(changeset)}}
    end
  end

  defp validate_product_row(row, categories, existing_skus, seen_skus) do
    f = row.fields
    sku = blank_to_nil(f["sku"])
    category_name = blank_to_nil(f["category"])

    data = %{
      row_number: row.row_number,
      name: blank_to_nil(f["name"]),
      category_id: nil,
      sku: sku,
      barcode: blank_to_nil(f["barcode"]),
      brand: blank_to_nil(f["brand"]),
      unit: blank_to_nil(f["unit"]) || "pcs",
      purchase_price: blank_to_nil(f["purchase_price"]),
      selling_price: blank_to_nil(f["selling_price"]),
      mrp: blank_to_nil(f["mrp"]),
      tax_rate: blank_to_nil(f["tax_rate"]) || "0",
      reorder_level: to_int(f["reorder_level"]) || 0,
      opening_stock: to_int(f["opening_stock"] || f["quantity"])
    }

    errors = %{}

    {data, errors} =
      case category_name do
        nil ->
          {data, errors}

        name ->
          case Map.get(categories, String.downcase(name)) do
            nil -> {data, Map.put(errors, "category", ["Unknown category '#{name}'"])}
            category -> {%{data | category_id: category.id}, errors}
          end
      end

    errors =
      case {sku, seen_skus} do
        {nil, _} ->
          errors

        {sku, seen} ->
          cond do
            MapSet.member?(seen, sku) ->
              Map.put(errors, "sku", ["Duplicate SKU '#{sku}' in this file"])

            MapSet.member?(existing_skus, sku) ->
              Map.put(errors, "sku", ["SKU '#{sku}' already exists"])

            true ->
              errors
          end
      end

    seen_skus = if sku, do: MapSet.put(seen_skus, sku), else: seen_skus

    changeset =
      %Product{}
      |> Product.changeset(%{
        name: data.name,
        sku: data.sku,
        barcode: data.barcode,
        brand: data.brand,
        unit: data.unit,
        purchase_price: data.purchase_price,
        selling_price: data.selling_price,
        mrp: data.mrp,
        tax_rate: data.tax_rate,
        reorder_level: data.reorder_level
      })
      |> Map.put(:action, :insert)

    errors = Map.merge(changeset_errors(changeset), errors)

    result = %{
      row_number: row.row_number,
      fields: f,
      data: data,
      errors: errors,
      valid: errors == %{}
    }

    {result, seen_skus}
  end

  ## Opening stock (existing simple products only)

  def preview_opening_stock(%Scope{business: business}, binary) do
    with {:ok, rows} <- CSV.parse(binary) do
      results = Enum.map(rows, &validate_opening_stock_row(business, &1))
      {:ok, summarize(results)}
    end
  end

  def commit_opening_stock(%Scope{business: business} = scope, rows)
      when is_list(rows) do
    outcomes =
      Enum.map(rows, fn attrs ->
        row = %{row_number: attrs["row_number"] || attrs[:row_number], fields: attrs}

        case validate_opening_stock_row(business, row) do
          %{valid: true} = validated -> apply_opening_stock_row(scope, validated)
          validated -> {:error, %{row_number: validated.row_number, errors: validated.errors}}
        end
      end)

    {created, failed} = split_outcomes(outcomes)
    log_import(scope, "opening_stock", length(rows), created, length(failed))
    %{created: created, failed: failed}
  end

  defp apply_opening_stock_row(scope, %{data: data}) do
    product = data.product

    with {:ok, _txn} <-
           Inventory.record_movement(scope, product, %{
             "movement_type" => "opening_stock",
             "direction" => "in",
             "quantity" => data.quantity,
             "reference" => data.reference || "Bulk import"
           }) do
      update_attrs =
        %{}
        |> maybe_put(:purchase_price, data.purchase_price)
        |> maybe_put(:selling_price, data.selling_price)

      if map_size(update_attrs) > 0, do: Products.update_product(scope, product, update_attrs)

      :ok
    else
      {:error, changeset} ->
        {:error, %{row_number: data.row_number, errors: changeset_errors(changeset)}}
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp validate_opening_stock_row(business, row) do
    f = row.fields
    identifier = blank_to_nil(f["sku"]) || blank_to_nil(f["barcode"])
    quantity = to_int(f["quantity"])

    errors = %{}

    errors =
      if identifier, do: errors, else: Map.put(errors, "sku", ["sku or barcode is required"])

    errors =
      if quantity && quantity > 0,
        do: errors,
        else: Map.put(errors, "quantity", ["must be a positive integer"])

    product = identifier && find_product(business, identifier)

    errors =
      if identifier && !product,
        do: Map.put(errors, "sku", ["No product found for '#{identifier}'"]),
        else: errors

    data = %{
      row_number: row.row_number,
      product: product,
      identifier: identifier,
      quantity: quantity,
      purchase_price: blank_to_nil(f["purchase_price"]),
      selling_price: blank_to_nil(f["selling_price"]),
      reference: blank_to_nil(f["reference"])
    }

    %{row_number: row.row_number, fields: f, data: data, errors: errors, valid: errors == %{}}
  end

  defp find_product(business, identifier) do
    Repo.one(
      from p in Product,
        where:
          p.business_id == ^business.id and (p.sku == ^identifier or p.barcode == ^identifier),
        limit: 1
    )
  end

  ## Historical bills (AGENTS.md §14, §27)
  #
  # Rows are grouped by `invoice_number` - one group is one invoice, and
  # every row in the group must be valid for the group to be valid, since
  # `Billing.import_historical_invoice/2` creates it all-or-nothing. A row
  # whose own fields are fine but whose sibling failed is still marked
  # invalid, with an "invoice" error pointing at the sibling, so the UI
  # never shows a clean-looking row that silently can't be imported.

  def preview_historical_bills(%Scope{business: business}, binary) do
    with {:ok, rows} <- CSV.parse(binary) do
      products = products_by_sku(business)
      existing_numbers = existing_invoice_numbers(business)
      results = validate_bill_groups(rows, products, existing_numbers)
      {:ok, summarize(results)}
    end
  end

  def commit_historical_bills(%Scope{business: business} = scope, rows) when is_list(rows) do
    products = products_by_sku(business)
    existing_numbers = existing_invoice_numbers(business)

    wrapped_rows =
      Enum.map(rows, fn attrs ->
        %{row_number: attrs["row_number"] || attrs[:row_number], fields: attrs}
      end)

    grouped =
      Enum.group_by(wrapped_rows, fn row -> blank_to_nil(row.fields["invoice_number"]) end)

    missing_number_outcomes =
      grouped
      |> Map.get(nil, [])
      |> Enum.map(fn row ->
        {:error, %{row_number: row.row_number, errors: %{"invoice_number" => ["is required"]}}}
      end)

    groups = Map.delete(grouped, nil)

    group_outcomes =
      Enum.map(groups, fn {invoice_number, group_rows} ->
        header_row = hd(group_rows)
        header_errors = validate_bill_header(invoice_number, header_row, existing_numbers)
        item_errors_list = Enum.map(group_rows, &validate_bill_item(&1, products))
        group_valid? = header_errors == %{} and Enum.all?(item_errors_list, &(&1 == %{}))

        if group_valid? do
          create_historical_invoice(scope, invoice_number, header_row, group_rows, products)
        else
          errors = Enum.find(item_errors_list, &(&1 != %{})) || header_errors
          {:error, %{row_number: header_row.row_number, errors: errors}}
        end
      end)

    outcomes = missing_number_outcomes ++ group_outcomes
    {created, failed} = split_outcomes(outcomes)
    total = length(missing_number_outcomes) + map_size(groups)
    log_import(scope, "historical_bills", total, created, length(failed))
    %{created: created, failed: failed}
  end

  defp validate_bill_groups(rows, products, existing_numbers) do
    rows
    |> Enum.group_by(fn row -> blank_to_nil(row.fields["invoice_number"]) end)
    |> Enum.flat_map(fn
      {nil, group_rows} ->
        Enum.map(group_rows, fn row ->
          %{
            row_number: row.row_number,
            fields: row.fields,
            errors: %{"invoice_number" => ["is required"]},
            valid: false
          }
        end)

      {invoice_number, group_rows} ->
        validate_bill_group(invoice_number, group_rows, products, existing_numbers)
    end)
    |> Enum.sort_by(& &1.row_number)
  end

  defp validate_bill_group(invoice_number, group_rows, products, existing_numbers) do
    header_row = hd(group_rows)
    header_errors = validate_bill_header(invoice_number, header_row, existing_numbers)
    item_errors_list = Enum.map(group_rows, &validate_bill_item(&1, products))
    group_valid? = header_errors == %{} and Enum.all?(item_errors_list, &(&1 == %{}))

    Enum.zip(group_rows, item_errors_list)
    |> Enum.map(fn {row, item_errors} ->
      errors =
        cond do
          item_errors != %{} ->
            item_errors

          header_errors != %{} ->
            header_errors

          not group_valid? ->
            %{"invoice" => ["Fix the other line(s) in this invoice to import it"]}

          true ->
            %{}
        end

      %{row_number: row.row_number, fields: row.fields, errors: errors, valid: group_valid?}
    end)
  end

  defp validate_bill_header(invoice_number, header_row, existing_numbers) do
    f = header_row.fields
    errors = %{}

    errors =
      if MapSet.member?(existing_numbers, invoice_number) do
        Map.put(errors, "invoice_number", ["Invoice '#{invoice_number}' already exists"])
      else
        errors
      end

    date_string = blank_to_nil(f["date"])

    errors =
      case parse_date(date_string) do
        {:ok, _} ->
          errors

        :error ->
          Map.put(errors, "date", ["Invalid or missing date '#{date_string}' (use YYYY-MM-DD)"])
      end

    errors =
      case parse_optional_decimal(blank_to_nil(f["amount_paid"]), Decimal.new(0)) do
        {:ok, _} -> errors
        :error -> Map.put(errors, "amount_paid", ["Invalid amount '#{f["amount_paid"]}'"])
      end

    payment_method = blank_to_nil(f["payment_method"])

    if is_nil(payment_method) or payment_method in Payment.methods() do
      errors
    else
      Map.put(errors, "payment_method", ["Must be one of: #{Enum.join(Payment.methods(), ", ")}"])
    end
  end

  defp validate_bill_item(row, products) do
    f = row.fields
    sku = blank_to_nil(f["sku"])
    errors = %{}

    errors =
      cond do
        is_nil(sku) -> Map.put(errors, "sku", ["sku is required"])
        !Map.has_key?(products, sku) -> Map.put(errors, "sku", ["SKU '#{sku}' not found"])
        true -> errors
      end

    quantity = to_int(f["quantity"])

    errors =
      if quantity && quantity > 0,
        do: errors,
        else: Map.put(errors, "quantity", ["must be a positive integer"])

    errors =
      case parse_decimal(f["unit_price"]) do
        {:ok, _} -> errors
        :error -> Map.put(errors, "unit_price", ["Invalid price '#{f["unit_price"]}'"])
      end

    errors =
      case parse_optional_decimal(f["discount_amount"], Decimal.new(0)) do
        {:ok, _} -> errors
        :error -> Map.put(errors, "discount_amount", ["Invalid amount '#{f["discount_amount"]}'"])
      end

    case parse_optional_decimal(f["tax_amount"], Decimal.new(0)) do
      {:ok, _} -> errors
      :error -> Map.put(errors, "tax_amount", ["Invalid amount '#{f["tax_amount"]}'"])
    end
  end

  defp create_historical_invoice(scope, invoice_number, header_row, group_rows, products) do
    f = header_row.fields
    {:ok, date} = parse_date(blank_to_nil(f["date"]))
    issued_at = DateTime.new!(date, ~T[00:00:00])

    items =
      Enum.map(group_rows, fn row ->
        rf = row.fields
        product = Map.fetch!(products, blank_to_nil(rf["sku"]))

        %{
          "product_id" => product.id,
          "quantity" => to_int(rf["quantity"]),
          "unit_price" => rf["unit_price"],
          "discount_amount" => rf["discount_amount"],
          "tax_amount" => rf["tax_amount"],
          "tax_rate" => rf["tax_rate"]
        }
      end)

    with {:ok, customer_id} <-
           resolve_customer(
             scope,
             blank_to_nil(f["customer_name"]),
             blank_to_nil(f["customer_phone"])
           ) do
      {:ok, amount_paid} = parse_optional_decimal(blank_to_nil(f["amount_paid"]), Decimal.new(0))

      payments =
        if Decimal.positive?(amount_paid) do
          [
            %{
              "method" => blank_to_nil(f["payment_method"]) || "cash",
              "amount" => amount_paid,
              "reference" => nil
            }
          ]
        else
          []
        end

      case Billing.import_historical_invoice(scope, %{
             "invoice_number" => invoice_number,
             "issued_at" => issued_at,
             "customer_id" => customer_id,
             "items" => items,
             "payments" => payments,
             "notes" => blank_to_nil(f["notes"])
           }) do
        {:ok, _invoice} ->
          :ok

        {:error, changeset} ->
          {:error, %{row_number: header_row.row_number, errors: changeset_errors(changeset)}}
      end
    else
      {:error, changeset} ->
        {:error, %{row_number: header_row.row_number, errors: changeset_errors(changeset)}}
    end
  end

  defp resolve_customer(_scope, nil, nil), do: {:ok, nil}

  defp resolve_customer(scope, name, phone) do
    case phone && Customers.find_by_phone(scope, phone) do
      %Customers.Customer{id: id} ->
        {:ok, id}

      _ ->
        case name do
          nil ->
            {:ok, nil}

          name ->
            case Customers.create_customer(scope, %{name: name, phone: phone}) do
              {:ok, customer} -> {:ok, customer.id}
              {:error, changeset} -> {:error, changeset}
            end
        end
    end
  end

  defp existing_invoice_numbers(business) do
    from(i in Invoice, where: i.business_id == ^business.id, select: i.invoice_number)
    |> Repo.all()
    |> MapSet.new()
  end

  defp parse_date(nil), do: :error

  defp parse_date(date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} -> {:ok, date}
      {:error, _} -> :error
    end
  end

  defp parse_decimal(nil), do: :error
  defp parse_decimal(""), do: :error

  defp parse_decimal(value) do
    case Decimal.parse(value) do
      {decimal, ""} -> {:ok, decimal}
      _ -> :error
    end
  end

  defp parse_optional_decimal(nil, default), do: {:ok, default}
  defp parse_optional_decimal("", default), do: {:ok, default}
  defp parse_optional_decimal(value, _default), do: parse_decimal(value)

  ## History

  def list_import_logs(%Scope{business: business}) do
    from(l in ImportLog,
      where: l.business_id == ^business.id,
      order_by: [desc: l.inserted_at],
      limit: 20
    )
    |> Repo.all()
  end

  ## Shared helpers

  defp categories_by_name(business) do
    from(c in Category, where: c.business_id == ^business.id)
    |> Repo.all()
    |> Map.new(fn c -> {String.downcase(c.name), c} end)
  end

  defp existing_skus(business) do
    from(p in Product, where: p.business_id == ^business.id and not is_nil(p.sku), select: p.sku)
    |> Repo.all()
    |> MapSet.new()
  end

  defp products_by_sku(business) do
    from(p in Product, where: p.business_id == ^business.id and not is_nil(p.sku))
    |> Repo.all()
    |> Map.new(fn p -> {p.sku, p} end)
  end

  defp summarize(results) do
    valid_count = Enum.count(results, & &1.valid)

    %{
      total: length(results),
      valid: valid_count,
      invalid: length(results) - valid_count,
      rows: results
    }
  end

  defp split_outcomes(outcomes) do
    Enum.reduce(outcomes, {0, []}, fn
      :ok, {created, failed} -> {created + 1, failed}
      {:error, error}, {created, failed} -> {created, [error | failed]}
    end)
    |> then(fn {created, failed} -> {created, Enum.reverse(failed)} end)
  end

  defp log_import(
         %Scope{business: business, user: user} = scope,
         type,
         total,
         success,
         error_count
       ) do
    %ImportLog{}
    |> ImportLog.changeset(%{
      business_id: business.id,
      performed_by_id: user.id,
      import_type: type,
      total_rows: total,
      success_count: success,
      error_count: error_count
    })
    |> Repo.insert()

    AuditLogs.record(scope, "import.performed", "Business", business.id, %{
      import_type: type,
      total_rows: total,
      success_count: success,
      error_count: error_count
    })
  end

  defp changeset_errors(%Ecto.Changeset{valid?: true}), do: %{}

  defp changeset_errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", stringify(value))
      end)
    end)
    |> Map.new(fn {k, v} -> {to_string(k), v} end)
  end

  defp stringify(value) when is_list(value), do: Enum.join(value, ", ")
  defp stringify(value), do: to_string(value)

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value) when is_binary(value), do: String.trim(value)

  defp to_int(nil), do: nil
  defp to_int(""), do: nil

  defp to_int(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {n, _} -> n
      :error -> nil
    end
  end
end
