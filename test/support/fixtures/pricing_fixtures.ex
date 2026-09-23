defmodule Posbd.PricingFixtures do
  alias Posbd.Accounts.Scope
  alias Posbd.Pricing

  def valid_price_tier_attrs(attrs \\ %{}) do
    Enum.into(attrs, %{label: "Wholesale", min_quantity: 10, price: "90.00"})
  end

  def price_tier_fixture(%Scope{} = scope, attrs \\ %{}) do
    {:ok, tier} = Pricing.create_price_tier(scope, valid_price_tier_attrs(attrs))
    tier
  end
end
