defmodule Posbd.InventoryTest do
  use Posbd.DataCase, async: true

  alias Posbd.{Inventory, Products}

  import Posbd.BusinessesFixtures
  import Posbd.ProductsFixtures

  setup do
    %{scope: full_scope_fixture()}
  end

  describe "record_movement/3 against a simple product" do
    test "opening stock increases stock_quantity", %{scope: scope} do
      product = product_fixture(scope)
      assert product.stock_quantity == 0

      assert {:ok, transaction} =
               Inventory.record_movement(scope, product, %{
                 "movement_type" => "opening_stock",
                 "direction" => "in",
                 "quantity" => 50,
                 "reference" => "Opening balance"
               })

      assert transaction.quantity == 50
      assert transaction.performed_by.id == scope.user.id

      reloaded = Products.get_product(scope, product.id)
      assert reloaded.stock_quantity == 50
    end

    test "a sale (direction out) decreases stock_quantity", %{scope: scope} do
      product = product_fixture(scope)

      {:ok, _} =
        Inventory.record_movement(scope, product, %{
          "movement_type" => "opening_stock",
          "direction" => "in",
          "quantity" => 20
        })

      {:ok, _} =
        Inventory.record_movement(scope, product, %{
          "movement_type" => "sale",
          "direction" => "out",
          "quantity" => 3
        })

      assert Products.get_product(scope, product.id).stock_quantity == 17
    end

    test "rejects a non-positive quantity", %{scope: scope} do
      product = product_fixture(scope)

      assert {:error, changeset} =
               Inventory.record_movement(scope, product, %{
                 "movement_type" => "adjustment",
                 "direction" => "in",
                 "quantity" => 0
               })

      assert "must be greater than 0" in errors_on(changeset).quantity
    end

    test "rejects an unknown movement_type", %{scope: scope} do
      product = product_fixture(scope)

      assert {:error, changeset} =
               Inventory.record_movement(scope, product, %{
                 "movement_type" => "teleportation",
                 "direction" => "in",
                 "quantity" => 1
               })

      assert "is invalid" in errors_on(changeset).movement_type
    end

    test "a failed movement does not change stock_quantity (all-or-nothing)", %{scope: scope} do
      product = product_fixture(scope)

      assert {:error, _} =
               Inventory.record_movement(scope, product, %{
                 "movement_type" => "sale",
                 "direction" => "out",
                 "quantity" => -1
               })

      assert Products.get_product(scope, product.id).stock_quantity == 0
    end
  end

  describe "record_movement/3 against a variant" do
    test "adjusts the variant's own stock_quantity, not the product's", %{scope: scope} do
      product = product_fixture(scope, has_variants: true)
      variant = variant_fixture(scope, product)

      {:ok, _} =
        Inventory.record_movement(scope, variant, %{
          "movement_type" => "opening_stock",
          "direction" => "in",
          "quantity" => 12
        })

      reloaded = Products.get_product(scope, product.id)
      [reloaded_variant] = reloaded.variants

      assert reloaded_variant.stock_quantity == 12
      assert reloaded.stock_quantity == 0
    end
  end

  describe "list_movements/3" do
    test "returns movements newest first, scoped to the item and business", %{scope: scope} do
      product = product_fixture(scope)
      other_product = product_fixture(scope)

      {:ok, _} =
        Inventory.record_movement(scope, product, %{
          "movement_type" => "opening_stock",
          "direction" => "in",
          "quantity" => 10
        })

      {:ok, _} =
        Inventory.record_movement(scope, product, %{
          "movement_type" => "sale",
          "direction" => "out",
          "quantity" => 2
        })

      {:ok, _} =
        Inventory.record_movement(scope, other_product, %{
          "movement_type" => "opening_stock",
          "direction" => "in",
          "quantity" => 99
        })

      result = Inventory.list_movements(scope, %{product_id: product.id})
      assert result.total_count == 2
      assert Enum.map(result.data, & &1.movement_type) == ["sale", "opening_stock"]
    end
  end
end
