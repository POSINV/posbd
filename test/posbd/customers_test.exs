defmodule Posbd.CustomersTest do
  use Posbd.DataCase, async: true

  alias Posbd.{AuditLogs, Billing, Customers, Inventory}

  import Posbd.BusinessesFixtures
  import Posbd.CustomersFixtures
  import Posbd.ProductsFixtures

  setup do
    %{scope: full_scope_fixture()}
  end

  defp seed_stock(scope, product, quantity) do
    Inventory.record_movement(scope, product, %{
      "movement_type" => "opening_stock",
      "direction" => "in",
      "quantity" => quantity
    })
  end

  defp buy(scope, customer, product, quantity, opts \\ []) do
    {:ok, invoice} =
      Billing.create_invoice(scope, %{
        "customer_id" => customer.id,
        "items" => [%{"product_id" => product.id, "quantity" => quantity}]
      })

    if amount_paid = opts[:amount_paid] do
      {:ok, _} =
        Billing.add_payment(scope, invoice, %{"method" => "cash", "amount" => amount_paid})
    end

    invoice
  end

  describe "create_customer/2, update_customer/3, delete_customer/2" do
    test "each leaves an audit trail", %{scope: scope} do
      {:ok, customer} = Customers.create_customer(scope, valid_customer_attrs(name: "Asha"))
      {:ok, updated} = Customers.update_customer(scope, customer, %{email: "asha@example.com"})
      {:ok, _} = Customers.delete_customer(scope, updated)

      actions = scope |> AuditLogs.list() |> Map.fetch!(:data) |> Enum.map(& &1.action)
      assert actions == ["customer.deleted", "customer.updated", "customer.created"]
    end
  end

  describe "purchase_summary/2" do
    test "aggregates spend, visits, last purchase, outstanding balance, and top products", %{
      scope: scope
    } do
      customer = customer_fixture(scope)
      product = product_fixture(scope, selling_price: "100.00", tax_rate: "0")
      {:ok, _} = seed_stock(scope, product, 10)

      buy(scope, customer, product, 2, amount_paid: "200.00")
      buy(scope, customer, product, 1, amount_paid: "50.00")

      summary = Customers.purchase_summary(scope, customer)

      assert summary.visit_count == 2
      assert Decimal.equal?(summary.total_spent, Decimal.new("300.00"))
      assert Decimal.equal?(summary.average_bill, Decimal.new("150.00"))
      assert Decimal.equal?(summary.outstanding_balance, Decimal.new("50.00"))
      assert summary.last_purchase_at
      assert [%{name: name, quantity: 3}] = summary.top_products
      assert name == product.name
    end

    test "a cancelled invoice does not count toward the summary", %{scope: scope} do
      customer = customer_fixture(scope)
      product = product_fixture(scope, selling_price: "50.00")
      {:ok, _} = seed_stock(scope, product, 5)

      invoice = buy(scope, customer, product, 1)
      {:ok, _} = Billing.cancel_invoice(scope, invoice)

      summary = Customers.purchase_summary(scope, customer)
      assert summary.visit_count == 0
      assert Decimal.equal?(summary.total_spent, Decimal.new(0))
    end

    test "a customer with no purchases has zeroed-out stats", %{scope: scope} do
      customer = customer_fixture(scope)
      summary = Customers.purchase_summary(scope, customer)

      assert summary.visit_count == 0
      assert Decimal.equal?(summary.total_spent, Decimal.new(0))
      assert summary.last_purchase_at == nil
      assert summary.top_products == []
    end
  end

  describe "segment/2" do
    test "a big spender is classified vip regardless of visit count", %{scope: scope} do
      customer = customer_fixture(scope)
      product = product_fixture(scope, selling_price: "12000.00")
      {:ok, _} = seed_stock(scope, product, 5)
      buy(scope, customer, product, 1)

      assert Customers.purchase_summary(scope, customer).segment == :vip
    end

    test "a brand-new customer with no purchases yet is classified new", %{scope: scope} do
      customer = customer_fixture(scope)
      assert Customers.purchase_summary(scope, customer).segment == :new
    end

    test "a customer whose last purchase was long ago is classified inactive", %{scope: scope} do
      customer = customer_fixture(scope)
      product = product_fixture(scope, selling_price: "50.00")
      {:ok, _} = seed_stock(scope, product, 5)
      invoice = buy(scope, customer, product, 1)

      old_date = DateTime.utc_now() |> DateTime.add(-120, :day) |> DateTime.truncate(:microsecond)
      invoice |> Ecto.Changeset.change(issued_at: old_date) |> Posbd.Repo.update!()

      assert Customers.purchase_summary(scope, customer).segment == :inactive
    end
  end

  describe "list_customers/2" do
    test "includes each customer's stats and segment, filterable by segment", %{scope: scope} do
      vip = customer_fixture(scope, name: "Big Spender")
      newcomer = customer_fixture(scope, name: "Newcomer")
      product = product_fixture(scope, selling_price: "15000.00")
      {:ok, _} = seed_stock(scope, product, 5)
      buy(scope, vip, product, 1)

      all_rows = Customers.list_customers(scope)
      assert length(all_rows) == 2

      vip_row = Enum.find(all_rows, &(&1.customer.id == vip.id))
      assert vip_row.stats.segment == :vip
      assert Decimal.equal?(vip_row.stats.total_spent, Decimal.new("15000.00"))

      new_row = Enum.find(all_rows, &(&1.customer.id == newcomer.id))
      assert new_row.stats.segment == :new
      assert new_row.stats.visit_count == 0

      assert [%{customer: %{id: id}}] = Customers.list_customers(scope, %{"segment" => "vip"})
      assert id == vip.id
    end
  end
end
