defmodule PosbdWeb.Api.OfferControllerTest do
  use PosbdWeb.ConnCase, async: true

  import Posbd.BusinessesFixtures
  import Posbd.MarketingFixtures

  setup do
    %{scope: full_scope_fixture()}
  end

  test "full create/list/show/update round-trip", %{scope: scope} do
    create_resp =
      post(authed_conn(scope), ~p"/api/v1/offers",
        offer: %{
          "name" => "Festival Sale",
          "code" => "FEST20",
          "discount_type" => "percentage",
          "discount_value" => "20"
        }
      )

    assert %{"data" => %{"id" => id, "code" => "FEST20"}} = json_response(create_resp, 201)

    index_resp = get(authed_conn(scope), ~p"/api/v1/offers")
    assert %{"data" => [%{"id" => ^id}]} = json_response(index_resp, 200)

    show_resp = get(authed_conn(scope), ~p"/api/v1/offers/#{id}")
    assert %{"data" => %{"id" => ^id, "redemption_count" => 0}} = json_response(show_resp, 200)

    update_resp =
      patch(authed_conn(scope), ~p"/api/v1/offers/#{id}", offer: %{"status" => "inactive"})

    assert %{"data" => %{"status" => "inactive"}} = json_response(update_resp, 200)
  end

  test "rejects a duplicate code", %{scope: scope} do
    offer_fixture(scope, %{"code" => "DUP10"})

    resp =
      post(authed_conn(scope), ~p"/api/v1/offers",
        offer: %{
          "name" => "Another",
          "code" => "dup10",
          "discount_type" => "percentage",
          "discount_value" => "5"
        }
      )

    assert %{"errors" => %{"code" => [_]}} = json_response(resp, 422)
  end
end
