defmodule Posbd.AuditLogsTest do
  use Posbd.DataCase, async: true

  alias Posbd.{AuditLogs, Billing, Inventory, Products}

  import Posbd.BusinessesFixtures
  import Posbd.ProductsFixtures

  setup do
    %{scope: full_scope_fixture()}
  end

  defp seed_stock(scope, target, quantity) do
    Inventory.record_movement(scope, target, %{
      "movement_type" => "opening_stock",
      "direction" => "in",
      "quantity" => quantity
    })
  end

  describe "record/5 and list/2" do
    test "records and lists an entry for the scope's business", %{scope: scope} do
      assert {:ok, _log} =
               AuditLogs.record(scope, "product.created", "Product", Ecto.UUID.generate(), %{
                 name: "Test"
               })

      assert %{data: [log], total_count: 1} = AuditLogs.list(scope)
      assert log.action == "product.created"
      assert log.entity_type == "Product"
      assert log.metadata["name"] == "Test"
      assert log.user.id == scope.user.id
    end

    test "never mixes entries across tenants", %{scope: scope} do
      other_scope = full_scope_fixture()

      {:ok, _} =
        AuditLogs.record(other_scope, "product.created", "Product", Ecto.UUID.generate())

      assert AuditLogs.list(scope).data == []
    end

    test "newest first, and filterable by action/entity_type", %{scope: scope} do
      {:ok, _} = AuditLogs.record(scope, "product.created", "Product", Ecto.UUID.generate())
      {:ok, _} = AuditLogs.record(scope, "invoice.created", "Invoice", Ecto.UUID.generate())

      assert [%{action: "invoice.created"}, %{action: "product.created"}] =
               AuditLogs.list(scope).data

      assert [%{action: "invoice.created"}] =
               AuditLogs.list(scope, %{"action" => "invoice.created"}).data

      assert [%{entity_type: "Product"}] =
               AuditLogs.list(scope, %{"entity_type" => "Product"}).data
    end
  end

  describe "integration with other contexts" do
    test "product create/update/delete each leave a trail", %{scope: scope} do
      {:ok, product} = Products.create_product(scope, valid_product_attrs())
      {:ok, _} = Products.update_product(scope, product, %{selling_price: "999.00"})
      {:ok, _} = Products.delete_product(scope, product)

      actions = scope |> AuditLogs.list() |> Map.fetch!(:data) |> Enum.map(& &1.action)
      assert actions == ["product.deleted", "product.price_changed", "product.created"]
    end

    test "updating a non-price field logs product.updated, not product.price_changed", %{
      scope: scope
    } do
      product = product_fixture(scope)
      {:ok, _} = Products.update_product(scope, product, %{name: "Renamed"})

      assert [%{action: "product.updated"}, %{action: "product.created"}] =
               AuditLogs.list(scope).data
    end

    test "billing.create_invoice and cancel_invoice are logged", %{scope: scope} do
      product = product_fixture(scope, selling_price: "100.00")
      {:ok, _} = seed_stock(scope, product, 10)

      {:ok, invoice} =
        Billing.create_invoice(scope, %{
          "items" => [%{"product_id" => product.id, "quantity" => 1}]
        })

      {:ok, _} = Billing.cancel_invoice(scope, invoice)

      actions =
        scope
        |> AuditLogs.list(%{"entity_type" => "Invoice"})
        |> Map.fetch!(:data)
        |> Enum.map(& &1.action)

      assert actions == ["invoice.cancelled", "invoice.created"]
    end

    test "a manual stock adjustment is logged, but opening stock and sale movements are not", %{
      scope: scope
    } do
      product = product_fixture(scope, selling_price: "50.00")
      {:ok, _} = seed_stock(scope, product, 10)

      {:ok, _} =
        Inventory.record_movement(scope, product, %{
          "movement_type" => "adjustment",
          "direction" => "out",
          "quantity" => 1,
          "notes" => "Damaged stock"
        })

      assert [
               %{action: "inventory.adjusted", metadata: %{"quantity" => 1}},
               %{action: "product.created"}
             ] = scope |> AuditLogs.list(%{"entity_type" => "Product"}) |> Map.fetch!(:data)
    end
  end
end
