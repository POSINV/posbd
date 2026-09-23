defmodule Posbd.ProductsTest do
  use Posbd.DataCase, async: true

  alias Posbd.Products

  import Posbd.BusinessesFixtures
  import Posbd.ProductsFixtures

  setup do
    %{scope: full_scope_fixture()}
  end

  describe "create_product/2" do
    test "creates a simple (non-variant) product", %{scope: scope} do
      assert {:ok, product} =
               Products.create_product(scope, valid_product_attrs(name: "Plain T-Shirt"))

      assert product.business_id == scope.business.id
      assert Decimal.equal?(product.selling_price, Decimal.new("199.00"))
    end

    test "requires a name", %{scope: scope} do
      assert {:error, changeset} = Products.create_product(scope, %{})
      assert "can't be blank" in errors_on(changeset).name
    end

    test "rejects a negative price", %{scope: scope} do
      assert {:error, changeset} =
               Products.create_product(scope, valid_product_attrs(selling_price: "-5"))

      assert "must be greater than or equal to 0" in errors_on(changeset).selling_price
    end

    test "enforces unique SKU per business", %{scope: scope} do
      _existing = product_fixture(scope, sku: "SKU-1")

      assert {:error, changeset} =
               Products.create_product(scope, valid_product_attrs(sku: "SKU-1"))

      assert "has already been taken" in errors_on(changeset).sku
    end
  end

  describe "variants" do
    test "create_variant/3 finds-or-creates attributes and links them", %{scope: scope} do
      product = product_fixture(scope, name: "T-Shirt", has_variants: true)

      assert {:ok, _variant} =
               Products.create_variant(scope, product, %{
                 "sku" => "TSHIRT-RED-M",
                 "selling_price" => "299.00",
                 "attributes" => %{"Size" => "M", "Color" => "Red"}
               })

      loaded = Products.get_product(scope, product.id)
      [variant] = loaded.variants
      attrs = Map.new(variant.attribute_values, &{&1.attribute.name, &1.value})

      assert attrs == %{"Size" => "M", "Color" => "Red"}
    end

    test "reuses an existing attribute value across variants instead of duplicating it", %{
      scope: scope
    } do
      product = product_fixture(scope, has_variants: true)

      {:ok, _v1} =
        Products.create_variant(scope, product, %{
          "sku" => "A",
          "attributes" => %{"Size" => "M"}
        })

      {:ok, _v2} =
        Products.create_variant(scope, product, %{
          "sku" => "B",
          "attributes" => %{"Size" => "M"}
        })

      assert [%{name: "Size", attribute_values: [%{value: "M"}]}] =
               Products.list_attributes(scope)
    end

    test "update_variant/3 replaces attribute links", %{scope: scope} do
      product = product_fixture(scope, has_variants: true)
      variant = variant_fixture(scope, product, attributes: %{"Size" => "S"})

      assert {:ok, updated} =
               Products.update_variant(scope, variant, %{"attributes" => %{"Size" => "L"}})

      attrs = Map.new(updated.attribute_values, &{&1.attribute.name, &1.value})
      assert attrs == %{"Size" => "L"}
    end

    test "delete_variant/1 removes it from the product", %{scope: scope} do
      product = product_fixture(scope, has_variants: true)
      variant = variant_fixture(scope, product)

      assert {:ok, _} = Products.delete_variant(variant)
      assert Products.get_product(scope, product.id).variants == []
    end
  end

  describe "list_products/2" do
    test "paginates and searches by name", %{scope: scope} do
      product_fixture(scope, name: "Blue Jeans")
      product_fixture(scope, name: "Red Jeans")
      product_fixture(scope, name: "White Shirt")

      result = Products.list_products(scope, %{"search" => "jeans"})
      assert result.total_count == 2
      assert Enum.all?(result.data, &String.contains?(&1.name, "Jeans"))
    end

    test "only returns the scope's own business's products", %{scope: scope} do
      other_scope = full_scope_fixture()
      product_fixture(other_scope, name: "Not Mine")

      result = Products.list_products(scope)
      assert result.data == []
      assert result.total_count == 0
    end

    test "preloads variant attributes, not just the variants", %{scope: scope} do
      product = product_fixture(scope, has_variants: true)
      variant_fixture(scope, product, attributes: %{"Size" => "M"})

      [listed] = Products.list_products(scope).data
      [variant] = listed.variants

      assert Enum.map(variant.attribute_values, & &1.value) == ["M"]
    end
  end
end
