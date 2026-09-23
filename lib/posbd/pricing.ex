defmodule Posbd.Pricing do
  @moduledoc """
  Quantity-break / wholesale / date-scheduled pricing on top of a
  product's or variant's base `selling_price` (see AGENTS.md §8).

  `price_for/4` is the single place unit price gets resolved - billing,
  reports, and any future PDF/print flow must all call through here
  rather than re-implementing the "which price applies" logic, per
  AGENTS.md §53 (centralize financial calculations).
  """

  import Ecto.Query, warn: false

  alias Posbd.Repo
  alias Posbd.Accounts.Scope
  alias Posbd.Pricing.PriceTier

  def list_price_tiers(%Scope{business: business}, %{product_id: product_id}) do
    from(t in PriceTier,
      where: t.business_id == ^business.id and t.product_id == ^product_id,
      order_by: [asc: t.min_quantity]
    )
    |> Repo.all()
  end

  def list_price_tiers(%Scope{business: business}, %{variant_id: variant_id}) do
    from(t in PriceTier,
      where: t.business_id == ^business.id and t.variant_id == ^variant_id,
      order_by: [asc: t.min_quantity]
    )
    |> Repo.all()
  end

  def get_price_tier(%Scope{business: business}, id) do
    Repo.get_by(PriceTier, id: id, business_id: business.id)
  end

  def create_price_tier(%Scope{business: business}, attrs) do
    %PriceTier{business_id: business.id}
    |> PriceTier.changeset(attrs)
    |> Repo.insert()
  end

  def update_price_tier(%PriceTier{} = tier, attrs) do
    tier
    |> PriceTier.changeset(attrs)
    |> Repo.update()
  end

  def delete_price_tier(%PriceTier{} = tier) do
    Repo.delete(tier)
  end

  @doc """
  Resolves the unit price for `quantity` units of a product or variant on
  `date` (defaults to today). Picks the highest-`min_quantity` tier that
  is `<= quantity` and whose effective date window (if any) covers
  `date`; falls back to the item's own `selling_price` when no tier
  matches or the item has none.

  `target` is a `%Product{}` or `%ProductVariant{}` struct (both have a
  `selling_price` field, which is why this works uniformly for either).
  """
  def price_for(%Scope{business: business}, target, quantity, date \\ Date.utc_today()) do
    tier =
      target
      |> tier_query(business)
      |> where([t], t.min_quantity <= ^quantity)
      |> where([t], is_nil(t.effective_from) or t.effective_from <= ^date)
      |> where([t], is_nil(t.effective_to) or t.effective_to >= ^date)
      |> order_by([t], desc: t.min_quantity)
      |> limit(1)
      |> Repo.one()

    %{
      unit_price: (tier && tier.price) || target.selling_price,
      tier: tier
    }
  end

  defp tier_query(%Posbd.Products.Product{id: id}, business) do
    from t in PriceTier, where: t.business_id == ^business.id and t.product_id == ^id
  end

  defp tier_query(%Posbd.Products.ProductVariant{id: id}, business) do
    from t in PriceTier, where: t.business_id == ^business.id and t.variant_id == ^id
  end
end
