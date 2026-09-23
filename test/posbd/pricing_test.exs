defmodule Posbd.PricingTest do
  use Posbd.DataCase, async: true

  alias Posbd.Pricing

  import Posbd.BusinessesFixtures
  import Posbd.ProductsFixtures
  import Posbd.PricingFixtures

  setup do
    %{scope: full_scope_fixture()}
  end

  describe "create_price_tier/2" do
    test "requires exactly one of product_id/variant_id", %{scope: scope} do
      assert {:error, changeset} =
               Pricing.create_price_tier(scope, valid_price_tier_attrs())

      assert "must set either product_id or variant_id" in errors_on(changeset).product_id
    end

    test "rejects setting both product_id and variant_id", %{scope: scope} do
      product = product_fixture(scope, has_variants: true)
      variant = variant_fixture(scope, product)

      assert {:error, changeset} =
               Pricing.create_price_tier(
                 scope,
                 valid_price_tier_attrs(product_id: product.id, variant_id: variant.id)
               )

      assert "cannot set both product_id and variant_id" in errors_on(changeset).variant_id
    end

    test "creates a tier for a simple product", %{scope: scope} do
      product = product_fixture(scope, selling_price: "100.00")

      assert {:ok, tier} =
               Pricing.create_price_tier(scope, valid_price_tier_attrs(product_id: product.id))

      assert tier.business_id == scope.business.id
      assert Decimal.equal?(tier.price, Decimal.new("90.00"))
    end

    test "rejects an effective_to before effective_from", %{scope: scope} do
      product = product_fixture(scope)

      assert {:error, changeset} =
               Pricing.create_price_tier(
                 scope,
                 valid_price_tier_attrs(
                   product_id: product.id,
                   effective_from: ~D[2026-06-01],
                   effective_to: ~D[2026-05-01]
                 )
               )

      assert "must be on or after the start date" in errors_on(changeset).effective_to
    end
  end

  describe "price_for/4" do
    test "falls back to the item's own selling_price with no tiers", %{scope: scope} do
      product = product_fixture(scope, selling_price: "199.00")
      assert %{unit_price: price, tier: nil} = Pricing.price_for(scope, product, 1)
      assert Decimal.equal?(price, Decimal.new("199.00"))
    end

    test "picks the highest matching quantity-break tier", %{scope: scope} do
      product = product_fixture(scope, selling_price: "100.00")

      price_tier_fixture(scope,
        product_id: product.id,
        min_quantity: 5,
        price: "90.00",
        label: "Bulk 5+"
      )

      price_tier_fixture(scope,
        product_id: product.id,
        min_quantity: 10,
        price: "80.00",
        label: "Bulk 10+"
      )

      assert %{unit_price: p1} = Pricing.price_for(scope, product, 1)
      assert Decimal.equal?(p1, Decimal.new("100.00"))

      assert %{unit_price: p5, tier: t5} = Pricing.price_for(scope, product, 7)
      assert Decimal.equal?(p5, Decimal.new("90.00"))
      assert t5.label == "Bulk 5+"

      assert %{unit_price: p10} = Pricing.price_for(scope, product, 12)
      assert Decimal.equal?(p10, Decimal.new("80.00"))
    end

    test "ignores a tier outside its effective date window", %{scope: scope} do
      product = product_fixture(scope, selling_price: "100.00")

      price_tier_fixture(scope,
        product_id: product.id,
        min_quantity: 1,
        price: "50.00",
        label: "Festival Sale",
        effective_from: ~D[2020-01-01],
        effective_to: ~D[2020-01-31]
      )

      assert %{unit_price: price, tier: nil} =
               Pricing.price_for(scope, product, 1, ~D[2026-06-01])

      assert Decimal.equal?(price, Decimal.new("100.00"))
    end

    test "prices a variant independently from its product", %{scope: scope} do
      product = product_fixture(scope, has_variants: true)
      variant = variant_fixture(scope, product, selling_price: "299.00")

      price_tier_fixture(scope, variant_id: variant.id, min_quantity: 3, price: "270.00")

      assert %{unit_price: price} = Pricing.price_for(scope, variant, 3)
      assert Decimal.equal?(price, Decimal.new("270.00"))
    end
  end
end
