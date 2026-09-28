defmodule Posbd.MarketingFixtures do
  alias Posbd.Accounts.Scope
  alias Posbd.Marketing

  def valid_offer_attrs(attrs \\ %{}) do
    Enum.into(attrs, %{
      "name" => "Offer #{System.unique_integer()}",
      "discount_type" => "percentage",
      "discount_value" => "10"
    })
  end

  def offer_fixture(%Scope{} = scope, attrs \\ %{}) do
    {:ok, offer} = Marketing.create_offer(scope, valid_offer_attrs(attrs))
    offer
  end
end
