defmodule Posbd.BillingTest do
  use Posbd.DataCase, async: true

  alias Posbd.{Billing, Products}
  alias Posbd.Businesses.Roles

  import Posbd.BusinessesFixtures
  import Posbd.ProductsFixtures
  import Posbd.CustomersFixtures
  import Posbd.MarketingFixtures
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

  describe "create_invoice/2 offers (Phase 2 §21/§30)" do
    test "applies an eligible automatic offer with no code needed", %{scope: scope} do
      offer_fixture(scope, %{"discount_type" => "percentage", "discount_value" => "10"})
      product = product_fixture(scope, selling_price: "100.00", tax_rate: "0")

      assert {:ok, invoice} =
               Billing.create_invoice(scope, %{
                 "items" => [%{"product_id" => product.id, "quantity" => 2}]
               })

      assert invoice.offer_id
      assert Decimal.equal?(invoice.offer_discount_amount, Decimal.new("20.00"))
      assert Decimal.equal?(invoice.total_amount, Decimal.new("180.00"))
    end

    test "applies a coded offer only when the code is supplied and valid", %{scope: scope} do
      offer_fixture(scope, %{
        "code" => "SAVE50",
        "discount_type" => "fixed_amount",
        "discount_value" => "50"
      })

      product = product_fixture(scope, selling_price: "100.00", tax_rate: "0")

      assert {:ok, without_code} =
               Billing.create_invoice(scope, %{
                 "items" => [%{"product_id" => product.id, "quantity" => 2}]
               })

      refute without_code.offer_id

      assert {:ok, with_code} =
               Billing.create_invoice(scope, %{
                 "offer_code" => "save50",
                 "items" => [%{"product_id" => product.id, "quantity" => 2}]
               })

      assert with_code.offer_id
      assert Decimal.equal?(with_code.total_amount, Decimal.new("150.00"))
    end

    test "rejects an invalid code without creating the invoice", %{scope: scope} do
      product = product_fixture(scope, selling_price: "100.00")

      assert {:error, %{message: message}} =
               Billing.create_invoice(scope, %{
                 "offer_code" => "NOPE",
                 "items" => [%{"product_id" => product.id, "quantity" => 1}]
               })

      assert message =~ "not found"
    end

    test "loyalty points are earned on the offer-discounted total, not the original one", %{
      scope: scope
    } do
      {:ok, _} =
        Posbd.Loyalty.upsert_program(scope, %{"enabled" => true, "earn_amount_per_point" => "100"})

      offer_fixture(scope, %{"discount_type" => "fixed_amount", "discount_value" => "100"})
      customer = customer_fixture(scope)
      product = product_fixture(scope, selling_price: "100.00", tax_rate: "0")

      assert {:ok, invoice} =
               Billing.create_invoice(scope, %{
                 "customer_id" => customer.id,
                 "items" => [%{"product_id" => product.id, "quantity" => 3}]
               })

      # 300 subtotal - 100 offer = 200 net -> 2 points earned (not 3)
      assert Decimal.equal?(invoice.offer_discount_amount, Decimal.new("100"))
      assert invoice.loyalty_points_earned == 2
    end
  end

  describe "create_invoice/2 loyalty (Phase 2 §17-§20)" do
    setup %{scope: scope} do
      {:ok, _program} =
        Posbd.Loyalty.upsert_program(scope, %{
          "enabled" => true,
          "earn_amount_per_point" => "100",
          "redeem_value_per_point" => "0.5",
          "min_redeem_points" => "10",
          "max_redemption_percentage" => "50"
        })

      %{customer: customer_fixture(scope)}
    end

    test "earns points on the final payable amount when the program is enabled", %{
      scope: scope,
      customer: customer
    } do
      product = product_fixture(scope, selling_price: "100.00", tax_rate: "0")

      assert {:ok, invoice} =
               Billing.create_invoice(scope, %{
                 "customer_id" => customer.id,
                 "items" => [%{"product_id" => product.id, "quantity" => 3}]
               })

      # 300.00 spent / 100 per point = 3 points earned
      assert invoice.loyalty_points_earned == 3
      assert invoice.loyalty_points_redeemed == 0
      assert Posbd.Customers.get_customer(scope, customer.id).loyalty_points_balance == 3
    end

    test "does not earn points for a walk-in sale with no customer", %{scope: scope} do
      product = product_fixture(scope, selling_price: "100.00", tax_rate: "0")

      assert {:ok, invoice} =
               Billing.create_invoice(scope, %{
                 "items" => [%{"product_id" => product.id, "quantity" => 3}]
               })

      assert invoice.loyalty_points_earned == 0
    end

    test "redeems points for a discount, and only earns on the reduced total", %{
      scope: scope,
      customer: customer
    } do
      product = product_fixture(scope, selling_price: "100.00", tax_rate: "0")

      {:ok, _} =
        Posbd.Loyalty.record_entry(scope, %{
          "customer_id" => customer.id,
          "entry_type" => "bonus",
          "points" => 100
        })

      assert {:ok, invoice} =
               Billing.create_invoice(scope, %{
                 "customer_id" => customer.id,
                 "redeem_points" => 40,
                 "items" => [%{"product_id" => product.id, "quantity" => 3}]
               })

      # 40 points * 0.5 = 20.00 discount off a 300.00 bill
      assert invoice.loyalty_points_redeemed == 40
      assert Decimal.equal?(invoice.loyalty_discount_amount, Decimal.new("20.00"))
      assert Decimal.equal?(invoice.total_amount, Decimal.new("280.00"))
      # earns on the net 280.00, not the original 300.00
      assert invoice.loyalty_points_earned == 2

      # balance: 100 (bonus) - 40 (redeemed) + 2 (earned) = 62
      assert Posbd.Customers.get_customer(scope, customer.id).loyalty_points_balance == 62
    end

    test "rejects redeeming more points than the customer has", %{
      scope: scope,
      customer: customer
    } do
      product = product_fixture(scope, selling_price: "1000.00", tax_rate: "0")

      assert {:error, %{message: message}} =
               Billing.create_invoice(scope, %{
                 "customer_id" => customer.id,
                 "redeem_points" => 999,
                 "items" => [%{"product_id" => product.id, "quantity" => 1}]
               })

      assert message =~ "only has 0 points"
    end

    test "rejects redeeming loyalty points without selecting a customer", %{scope: scope} do
      product = product_fixture(scope, selling_price: "100.00", tax_rate: "0")

      assert {:error, %{message: message}} =
               Billing.create_invoice(scope, %{
                 "redeem_points" => 10,
                 "items" => [%{"product_id" => product.id, "quantity" => 1}]
               })

      assert message =~ "customer must be selected"
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
