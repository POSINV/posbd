defmodule Posbd.BillingTest do
  use Posbd.DataCase, async: true

  alias Posbd.{Billing, Products}
  alias Posbd.Businesses.Roles

  import Posbd.BusinessesFixtures
  import Posbd.ProductsFixtures
  import Posbd.CustomersFixtures
  import Posbd.PricingFixtures
  import Posbd.AccountsFixtures

  setup do
    %{scope: full_scope_fixture()}
  end

  describe "create_invoice/2" do
    test "computes subtotal/tax/total server-side and decrements stock", %{scope: scope} do
      product = product_fixture(scope, selling_price: "100.00", tax_rate: "10")
      {:ok, _} = seed_stock(scope, product, 10)

      assert {:ok, invoice} =
               Billing.create_invoice(scope, %{
                 "items" => [%{"product_id" => product.id, "quantity" => 2}]
               })

      assert Decimal.equal?(invoice.subtotal, Decimal.new("200.00"))
      assert Decimal.equal?(invoice.tax_amount, Decimal.new("20.00"))
      assert Decimal.equal?(invoice.total_amount, Decimal.new("220.00"))
      assert invoice.payment_status == "unpaid"
      assert invoice.status == "completed"
      assert String.starts_with?(invoice.invoice_number, "INV-")

      assert Products.get_product(scope, product.id).stock_quantity == 8
    end

    test "generates sequential invoice numbers per business", %{scope: scope} do
      product = product_fixture(scope, selling_price: "10.00")

      {:ok, i1} =
        Billing.create_invoice(scope, %{
          "items" => [%{"product_id" => product.id, "quantity" => 1}]
        })

      {:ok, i2} =
        Billing.create_invoice(scope, %{
          "items" => [%{"product_id" => product.id, "quantity" => 1}]
        })

      [_, n1] = String.split(i1.invoice_number, "-")
      [_, n2] = String.split(i2.invoice_number, "-")
      assert String.to_integer(n2) == String.to_integer(n1) + 1
    end

    test "applies a quantity-break price tier instead of the base price", %{scope: scope} do
      product = product_fixture(scope, selling_price: "100.00", tax_rate: "0")
      price_tier_fixture(scope, product_id: product.id, min_quantity: 5, price: "80.00")
      {:ok, _} = seed_stock(scope, product, 20)

      assert {:ok, invoice} =
               Billing.create_invoice(scope, %{
                 "items" => [%{"product_id" => product.id, "quantity" => 5}]
               })

      assert Decimal.equal?(invoice.total_amount, Decimal.new("400.00"))
    end

    test "applies a per-item discount and reduces the taxable base", %{scope: scope} do
      product = product_fixture(scope, selling_price: "100.00", tax_rate: "10")
      {:ok, _} = seed_stock(scope, product, 10)

      assert {:ok, invoice} =
               Billing.create_invoice(scope, %{
                 "items" => [
                   %{"product_id" => product.id, "quantity" => 2, "discount_amount" => "20.00"}
                 ]
               })

      assert Decimal.equal?(invoice.discount_amount, Decimal.new("20.00"))
      assert Decimal.equal?(invoice.tax_amount, Decimal.new("18.00"))
      assert Decimal.equal?(invoice.total_amount, Decimal.new("198.00"))
    end

    test "rejects a discount from a member without billing.discount permission", %{scope: scope} do
      cashier_scope = member_scope(scope, "cashier")
      product = product_fixture(scope, selling_price: "100.00")

      assert {:error, :unauthorized} =
               Billing.create_invoice(cashier_scope, %{
                 "items" => [
                   %{"product_id" => product.id, "quantity" => 1, "discount_amount" => "5.00"}
                 ]
               })
    end

    test "bills a variant using its own price/tax and snapshots its attributes as the name", %{
      scope: scope
    } do
      product = product_fixture(scope, has_variants: true)

      variant =
        variant_fixture(scope, product,
          selling_price: "299.00",
          tax_rate: "5",
          attributes: %{"Size" => "M"}
        )

      {:ok, _} = seed_stock(scope, variant, 5)

      assert {:ok, invoice} =
               Billing.create_invoice(scope, %{
                 "items" => [%{"variant_id" => variant.id, "quantity" => 1}]
               })

      [item] = invoice.items
      assert item.name_snapshot == "M"
      assert Decimal.equal?(item.unit_price, Decimal.new("299.00"))

      reloaded = Products.get_product(scope, product.id)
      [reloaded_variant] = reloaded.variants
      assert reloaded_variant.stock_quantity == 4
    end

    test "records payments and sets payment_status", %{scope: scope} do
      product = product_fixture(scope, selling_price: "100.00", tax_rate: "0")
      {:ok, _} = seed_stock(scope, product, 10)

      assert {:ok, partial} =
               Billing.create_invoice(scope, %{
                 "items" => [%{"product_id" => product.id, "quantity" => 1}],
                 "payments" => [%{"method" => "cash", "amount" => "50.00"}]
               })

      assert partial.payment_status == "partial"

      assert {:ok, paid} =
               Billing.create_invoice(scope, %{
                 "items" => [%{"product_id" => product.id, "quantity" => 1}],
                 "payments" => [%{"method" => "cash", "amount" => "100.00"}]
               })

      assert paid.payment_status == "paid"
    end

    test "rejects an empty item list", %{scope: scope} do
      assert {:error, %{message: message}} = Billing.create_invoice(scope, %{"items" => []})
      assert message =~ "at least one item"
    end

    test "rejects an item referencing a product from another business", %{scope: scope} do
      other_product = product_fixture(full_scope_fixture())

      assert {:error, %{message: _}} =
               Billing.create_invoice(scope, %{
                 "items" => [%{"product_id" => other_product.id, "quantity" => 1}]
               })
    end

    test "an idempotency_key replay returns the same invoice without double-billing stock", %{
      scope: scope
    } do
      product = product_fixture(scope, selling_price: "50.00")
      {:ok, _} = seed_stock(scope, product, 10)

      attrs = %{
        "items" => [%{"product_id" => product.id, "quantity" => 1}],
        "idempotency_key" => "client-token-123"
      }

      assert {:ok, first} = Billing.create_invoice(scope, attrs)
      assert {:ok, second} = Billing.create_invoice(scope, attrs)

      assert first.id == second.id
      assert Products.get_product(scope, product.id).stock_quantity == 9
    end

    test "attaches the given customer", %{scope: scope} do
      customer = customer_fixture(scope)
      product = product_fixture(scope, selling_price: "10.00")

      assert {:ok, invoice} =
               Billing.create_invoice(scope, %{
                 "customer_id" => customer.id,
                 "items" => [%{"product_id" => product.id, "quantity" => 1}]
               })

      assert invoice.customer.id == customer.id
    end
  end

  describe "add_payment/3" do
    test "settles a partial invoice to paid", %{scope: scope} do
      product = product_fixture(scope, selling_price: "100.00", tax_rate: "0")
      {:ok, _} = seed_stock(scope, product, 5)

      {:ok, invoice} =
        Billing.create_invoice(scope, %{
          "items" => [%{"product_id" => product.id, "quantity" => 1}],
          "payments" => [%{"method" => "cash", "amount" => "40.00"}]
        })

      assert invoice.payment_status == "partial"

      assert {:ok, updated} =
               Billing.add_payment(scope, invoice, %{"method" => "cash", "amount" => "60.00"})

      assert updated.payment_status == "paid"
      assert Decimal.equal?(updated.amount_paid, Decimal.new("100.00"))
    end
  end

  describe "cancel_invoice/2" do
    test "reverses stock and marks the invoice cancelled", %{scope: scope} do
      product = product_fixture(scope, selling_price: "50.00")
      {:ok, _} = seed_stock(scope, product, 10)

      {:ok, invoice} =
        Billing.create_invoice(scope, %{
          "items" => [%{"product_id" => product.id, "quantity" => 3}]
        })

      assert Products.get_product(scope, product.id).stock_quantity == 7

      assert {:ok, cancelled} = Billing.cancel_invoice(scope, invoice)
      assert cancelled.status == "cancelled"
      assert Products.get_product(scope, product.id).stock_quantity == 10
    end

    test "cannot cancel an already-cancelled invoice", %{scope: scope} do
      product = product_fixture(scope, selling_price: "50.00")
      {:ok, _} = seed_stock(scope, product, 10)

      {:ok, invoice} =
        Billing.create_invoice(scope, %{
          "items" => [%{"product_id" => product.id, "quantity" => 1}]
        })

      {:ok, cancelled} = Billing.cancel_invoice(scope, invoice)
      assert {:error, %{message: _}} = Billing.cancel_invoice(scope, cancelled)
    end

    test "cancelling a migrated invoice never restores stock", %{scope: scope} do
      product = product_fixture(scope, selling_price: "50.00")
      {:ok, _} = seed_stock(scope, product, 10)

      {:ok, invoice} =
        Billing.import_historical_invoice(scope, %{
          "invoice_number" => "OLD-1",
          "issued_at" => ~U[2025-01-01 00:00:00Z],
          "items" => [
            %{"product_id" => product.id, "quantity" => 3, "unit_price" => "50.00"}
          ]
        })

      assert Products.get_product(scope, product.id).stock_quantity == 10

      assert {:ok, cancelled} = Billing.cancel_invoice(scope, invoice)
      assert cancelled.status == "cancelled"
      assert Products.get_product(scope, product.id).stock_quantity == 10
    end
  end

  describe "import_historical_invoice/2" do
    test "creates a completed, migrated invoice without touching inventory", %{scope: scope} do
      product = product_fixture(scope, selling_price: "999.00")
      {:ok, _} = seed_stock(scope, product, 5)

      assert {:ok, invoice} =
               Billing.import_historical_invoice(scope, %{
                 "invoice_number" => "OLD-2001",
                 "issued_at" => ~U[2024-06-10 00:00:00Z],
                 "items" => [
                   %{
                     "product_id" => product.id,
                     "quantity" => 2,
                     "unit_price" => "40.00",
                     "discount_amount" => "5.00",
                     "tax_amount" => "3.50"
                   }
                 ]
               })

      assert invoice.source == "migrated"
      assert invoice.invoice_number == "OLD-2001"
      assert invoice.issued_at == ~U[2024-06-10 00:00:00.000000Z]
      # 2 * 40.00 - 5.00 + 3.50, using the historical price, not the
      # product's current selling_price of 999.00.
      assert Decimal.equal?(invoice.total_amount, Decimal.new("78.50"))
      assert invoice.payment_status == "unpaid"

      # No sale movement was recorded and stock is untouched.
      assert Products.get_product(scope, product.id).stock_quantity == 5
    end

    test "records a payment and marks the invoice paid when amount_paid covers the total", %{
      scope: scope
    } do
      product = product_fixture(scope, selling_price: "100.00")

      assert {:ok, invoice} =
               Billing.import_historical_invoice(scope, %{
                 "invoice_number" => "OLD-2002",
                 "issued_at" => ~U[2024-06-11 00:00:00Z],
                 "items" => [
                   %{"product_id" => product.id, "quantity" => 1, "unit_price" => "80.00"}
                 ],
                 "payments" => [%{"method" => "cash", "amount" => "80.00"}]
               })

      assert invoice.payment_status == "paid"
      assert Decimal.equal?(invoice.amount_paid, Decimal.new("80.00"))
    end

    test "rejects a duplicate invoice_number for the business", %{scope: scope} do
      product = product_fixture(scope, selling_price: "10.00")

      attrs = %{
        "invoice_number" => "OLD-DUP",
        "issued_at" => ~U[2024-01-01 00:00:00Z],
        "items" => [%{"product_id" => product.id, "quantity" => 1, "unit_price" => "10.00"}]
      }

      assert {:ok, _} = Billing.import_historical_invoice(scope, attrs)
      assert {:error, changeset} = Billing.import_historical_invoice(scope, attrs)
      assert "has already been taken" in errors_on(changeset).invoice_number
    end
  end

  defp seed_stock(scope, target, quantity) do
    Posbd.Inventory.record_movement(scope, target, %{
      "movement_type" => "opening_stock",
      "direction" => "in",
      "quantity" => quantity
    })
  end

  defp member_scope(%Posbd.Accounts.Scope{business: business} = scope, role) do
    user = user_fixture()

    {:ok, membership} =
      %Posbd.Businesses.Membership{}
      |> Posbd.Businesses.Membership.owner_changeset(business.id, user.id)
      |> Ecto.Changeset.change(role: role, permissions: Roles.default_permissions_for(role))
      |> Posbd.Repo.insert()

    scope
    |> Map.put(:user, user)
    |> Map.put(:membership, membership)
  end
end
