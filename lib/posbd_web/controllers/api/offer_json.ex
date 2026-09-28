defmodule PosbdWeb.Api.OfferJSON do
  alias Posbd.Marketing.Offer
  alias PosbdWeb.Api.ProductJSON

  def index(%{offers: offers}), do: %{data: Enum.map(offers, &offer_json/1)}

  def show(%{offer: offer, performance: performance}) do
    data = offer_json(offer)
    data = if performance, do: Map.merge(data, performance_json(performance)), else: data
    %{data: data}
  end

  defp offer_json(%Offer{} = offer) do
    %{
      id: offer.id,
      name: offer.name,
      code: offer.code,
      discount_type: offer.discount_type,
      discount_value: ProductJSON.money(offer.discount_value),
      starts_at: offer.starts_at,
      ends_at: offer.ends_at,
      min_purchase_amount: ProductJSON.money(offer.min_purchase_amount),
      eligible_segment: offer.eligible_segment,
      usage_limit_total: offer.usage_limit_total,
      usage_limit_per_customer: offer.usage_limit_per_customer,
      status: offer.status,
      inserted_at: offer.inserted_at
    }
  end

  defp performance_json(%{redemption_count: count, total_discount: total}) do
    %{redemption_count: count, total_discount: ProductJSON.money(total)}
  end
end
