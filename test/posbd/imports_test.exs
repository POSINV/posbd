defmodule Posbd.ImportsTest do
  use Posbd.DataCase, async: true

  alias Posbd.{Billing, Customers, Imports, Products}

  import Posbd.BusinessesFixtures
  import Posbd.ProductsFixtures

  setup do
    %{scope: full_scope_fixture()}
  end

  defp csv(rows) do
    Enum.map_join(rows, "\n", fn row -> Enum.join(row, ",") end)
  end

  describe "preview_products/2" do
    test "flags valid and invalid rows without creating anything", %{scope: scope} do
      category = category_fixture(scope, name: "Men's Wear")

      body =
        csv([
          ~w(name category sku selling_price),
          ["Cotton T-Shirt", "Men's Wear", "TS-1", "299.00"],
          ["", "Men's Wear", "TS-2", "199.00"],
          ["Broken Category Item", "Nonexistent", "TS-3", "99.00"]
        ])

      assert {:ok, preview} = Imports.preview_products(scope, body)

      assert preview.total == 3
      assert preview.valid == 1
      assert preview.invalid == 2

      [row1, row2, row3] = preview.rows
      assert row1.valid
      assert row1.fields["category"] == "Men's Wear"

      refute row2.valid
      assert Map.has_key?(row2.errors, "name")

      refute row3.valid
      assert row3.errors["category"] == ["Unknown category 'Nonexistent'"]

      assert Products.list_products(scope).total_count == 0
      assert category.name == "Men's Wear"
    end

    test "flags a SKU that already exists and a duplicate within the file", %{scope: scope} do
      product_fixture(scope, sku: "EXIST-1")

      body =
        csv([
          ~w(name sku selling_price),
          ["Existing SKU Row", "EXIST-1", "10.00"],
          ["First New Item", "NEW-1", "10.00"],
          ["Duplicate Of Above", "NEW-1", "20.00"]
        ])

      assert {:ok, preview} = Imports.preview_products(scope, body)
      [row1, row2, row3] = preview.rows

      assert row1.errors["sku"] == ["SKU 'EXIST-1' already exists"]
      assert row2.valid
      assert row3.errors["sku"] == ["Duplicate SKU 'NEW-1' in this file"]
    end
  end

  describe "commit_products/2" do
    test "creates only valid rows, records opening stock, and logs the import", %{scope: scope} do
      category = category_fixture(scope, name: "Grocery")

      body =
        csv([
          ~w(name category sku selling_price purchase_price opening_stock),
          ["Rice 5kg", "Grocery", "RICE-5", "450.00", "380.00", "20"],
          ["", "Grocery", "BAD-1", "10.00", "8.00", "5"]
        ])

      {:ok, preview} = Imports.preview_products(scope, body)

      valid_rows =
        Enum.filter(preview.rows, & &1.valid)
        |> Enum.map(&Map.put(&1.fields, "row_number", &1.row_number))

      result = Imports.commit_products(scope, valid_rows)

      assert result.created == 1
      assert result.failed == []

      listed = Products.list_products(scope)
      assert listed.total_count == 1
      [product] = listed.data
      assert product.name == "Rice 5kg"
      assert product.category_id == category.id
      assert product.stock_quantity == 20

      [log] = Imports.list_import_logs(scope)
      assert log.import_type == "products"
      assert log.success_count == 1
      assert log.total_rows == 1
    end
  end

  describe "preview_opening_stock/2 and commit_opening_stock/2" do
    test "resolves by SKU, records stock, and updates prices", %{scope: scope} do
      product =
        product_fixture(scope, sku: "OS-1", selling_price: "100.00", purchase_price: "60.00")

      body =
        csv([
          ~w(sku quantity purchase_price selling_price),
          ["OS-1", "30", "65.00", "110.00"],
          ["MISSING-SKU", "10", "", ""]
        ])

      assert {:ok, preview} = Imports.preview_opening_stock(scope, body)
      [row1, row2] = preview.rows
      assert row1.valid
      refute row2.valid
      assert row2.errors["sku"] == ["No product found for 'MISSING-SKU'"]

      valid_rows = [Map.put(row1.fields, "row_number", row1.row_number)]
      result = Imports.commit_opening_stock(scope, valid_rows)

      assert result.created == 1
      assert result.failed == []

      reloaded = Products.get_product(scope, product.id)
      assert reloaded.stock_quantity == 30
      assert Decimal.equal?(reloaded.selling_price, Decimal.new("110.00"))
    end

    test "rejects a non-positive quantity", %{scope: scope} do
      product_fixture(scope, sku: "OS-2")

      body = csv([~w(sku quantity), ["OS-2", "0"]])
      assert {:ok, preview} = Imports.preview_opening_stock(scope, body)
      [row] = preview.rows
      refute row.valid
      assert row.errors["quantity"] == ["must be a positive integer"]
    end
  end

  describe "templates" do
    test "products_template/0 and opening_stock_template/0 produce parseable CSV" do
      assert {:ok, [row]} = Posbd.Imports.CSV.parse(Imports.products_template())
      assert row.fields["name"] == "Cotton T-Shirt"

      assert {:ok, [row]} = Posbd.Imports.CSV.parse(Imports.opening_stock_template())
      assert row.fields["sku"] == "TS-001"
    end

    test "historical_bills_template/0 produces parseable CSV" do
      assert {:ok, rows} = Posbd.Imports.CSV.parse(Imports.historical_bills_template())
      assert Enum.any?(rows, &(&1.fields["invoice_number"] == "OLD-1001"))
    end
  end

  describe "preview_historical_bills/2 and commit_historical_bills/2" do
    @header ~w(invoice_number date customer_name customer_phone sku quantity
                unit_price discount_amount tax_amount amount_paid payment_method notes)

    test "groups rows by invoice_number, resolves/creates the customer, and never touches stock",
         %{scope: scope} do
      product1 = product_fixture(scope, sku: "TS-1")
      product2 = product_fixture(scope, sku: "TS-2")

      body =
        csv([
          @header,
          [
            "OLD-1",
            "2025-01-15",
            "Ramesh Kumar",
            "9876500000",
            "TS-1",
            "2",
            "100.00",
            "0",
            "0",
            "250.00",
            "cash",
            "Migrated"
          ],
          ["OLD-1", "", "", "", "TS-2", "1", "50.00", "0", "0", "", "", ""],
          [
            "OLD-2",
            "2025-01-16",
            "",
            "",
            "TS-1",
            "1",
            "60.00",
            "0",
            "0",
            "30.00",
            "upi",
            "Partial"
          ]
        ])

      assert {:ok, preview} = Imports.preview_historical_bills(scope, body)
      assert preview.total == 3
      assert preview.valid == 3
      assert preview.invalid == 0

      valid_rows = Enum.map(preview.rows, &Map.put(&1.fields, "row_number", &1.row_number))
      result = Imports.commit_historical_bills(scope, valid_rows)

      assert result.created == 2
      assert result.failed == []

      # Historical sales never deduct current live stock - it's already
      # reflected in whatever opening stock figure was imported separately.
      assert Products.get_product(scope, product1.id).stock_quantity == 0
      assert Products.get_product(scope, product2.id).stock_quantity == 0

      invoices = Billing.list_invoices(scope).data
      old1 = Enum.find(invoices, &(&1.invoice_number == "OLD-1"))
      old2 = Enum.find(invoices, &(&1.invoice_number == "OLD-2"))

      assert old1.source == "migrated"
      assert Decimal.equal?(old1.total_amount, Decimal.new("250.00"))
      assert old1.payment_status == "paid"
      assert old1.customer.name == "Ramesh Kumar"
      assert old1.customer.phone == "9876500000"

      assert Decimal.equal?(old2.total_amount, Decimal.new("60.00"))
      assert old2.payment_status == "partial"
      assert Decimal.equal?(old2.amount_paid, Decimal.new("30.00"))
      assert is_nil(old2.customer_id)

      assert [%{customer: customer}] = Customers.list_customers(scope)
      assert customer.name == "Ramesh Kumar"

      [log] = Imports.list_import_logs(scope)
      assert log.import_type == "historical_bills"
      assert log.success_count == 2
    end

    test "an unknown SKU invalidates the whole invoice, including its valid sibling line", %{
      scope: scope
    } do
      product_fixture(scope, sku: "GOOD-1")

      body =
        csv([
          @header,
          ["BAD-1", "2025-01-15", "", "", "GOOD-1", "1", "10.00", "0", "0", "", "", ""],
          ["BAD-1", "", "", "", "MISSING-SKU", "1", "5.00", "0", "0", "", "", ""]
        ])

      assert {:ok, preview} = Imports.preview_historical_bills(scope, body)
      assert preview.valid == 0
      assert preview.invalid == 2

      [row1, row2] = preview.rows
      refute row1.valid
      assert row1.errors["invoice"] != nil
      refute row2.valid
      assert row2.errors["sku"] == ["SKU 'MISSING-SKU' not found"]
    end

    test "a row missing invoice_number is rejected on its own", %{scope: scope} do
      product_fixture(scope, sku: "SOLO-1")

      body =
        csv([@header, ["", "2025-01-15", "", "", "SOLO-1", "1", "10.00", "0", "0", "", "", ""]])

      assert {:ok, preview} = Imports.preview_historical_bills(scope, body)
      [row] = preview.rows
      refute row.valid
      assert row.errors["invoice_number"] == ["is required"]
    end

    test "rejects re-importing an invoice_number that already exists", %{scope: scope} do
      product = product_fixture(scope, sku: "DUP-1")

      {:ok, _} =
        Billing.import_historical_invoice(scope, %{
          "invoice_number" => "OLD-DUP",
          "issued_at" => ~U[2024-01-01 00:00:00Z],
          "items" => [%{"product_id" => product.id, "quantity" => 1, "unit_price" => "10.00"}]
        })

      body =
        csv([
          @header,
          ["OLD-DUP", "2025-01-15", "", "", "DUP-1", "1", "10.00", "0", "0", "", "", ""]
        ])

      assert {:ok, preview} = Imports.preview_historical_bills(scope, body)
      [row] = preview.rows
      refute row.valid
      assert row.errors["invoice_number"] == ["Invoice 'OLD-DUP' already exists"]
    end
  end
end
