defmodule PosbdWeb.Api.PriceTierJSON do
  alias Posbd.Pricing.PriceTier
  alias PosbdWeb.Api.ProductJSON

  def index(%{price_tiers: price_tiers}), do: %{data: Enum.map(price_tiers, &tier_json/1)}
  def show(%{price_tier: price_tier}), do: %{data: tier_json(price_tier)}

  def quote(%{unit_price: unit_price, tier: tier}) do
    %{data: %{unit_price: ProductJSON.money(unit_price), tier: tier && tier_json(tier)}}
  end

  defp tier_json(%PriceTier{} = tier) do
    %{
      id: tier.id,
      label: tier.label,
      product_id: tier.product_id,
      variant_id: tier.variant_id,
      min_quantity: tier.min_quantity,
      price: ProductJSON.money(tier.price),
      effective_from: tier.effective_from,
      effective_to: tier.effective_to
    }
  end
end
