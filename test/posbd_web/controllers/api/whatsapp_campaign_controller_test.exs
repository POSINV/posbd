defmodule PosbdWeb.Api.WhatsappCampaignControllerTest do
  use PosbdWeb.ConnCase, async: true

  import Posbd.BusinessesFixtures
  import Posbd.WhatsappFixtures

  setup do
    %{scope: full_scope_fixture()}
  end

  test "creating a campaign with no scheduled_at dispatches it immediately", %{scope: scope} do
    template = approved_template_fixture(scope, %{"purpose" => "offer"})

    conn =
      post(authed_conn(scope), ~p"/api/v1/whatsapp/campaigns",
        campaign: %{
          "name" => "Flash Sale",
          "audience_segment" => "all",
          "template_id" => template.id
        }
      )

    assert %{"data" => %{"status" => "sent", "id" => id}} = json_response(conn, 201)

    show_resp = get(authed_conn(scope), ~p"/api/v1/whatsapp/campaigns/#{id}")
    assert %{"data" => %{"status" => "sent"}} = json_response(show_resp, 200)
  end

  test "creating a campaign with a future scheduled_at marks it scheduled, and it can be cancelled",
       %{
         scope: scope
       } do
    template = approved_template_fixture(scope, %{"purpose" => "offer"})
    future = DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.to_iso8601()

    conn =
      post(authed_conn(scope), ~p"/api/v1/whatsapp/campaigns",
        campaign: %{
          "name" => "Flash Sale",
          "audience_segment" => "all",
          "template_id" => template.id,
          "scheduled_at" => future
        }
      )

    assert %{"data" => %{"status" => "scheduled", "id" => id}} = json_response(conn, 201)

    cancel_resp = post(authed_conn(scope), ~p"/api/v1/whatsapp/campaigns/#{id}/cancel")
    assert %{"data" => %{"status" => "cancelled"}} = json_response(cancel_resp, 200)
  end

  test "cannot create a campaign against an unapproved template", %{scope: scope} do
    template = template_fixture(scope)

    conn =
      post(authed_conn(scope), ~p"/api/v1/whatsapp/campaigns",
        campaign: %{
          "name" => "Flash Sale",
          "audience_segment" => "all",
          "template_id" => template.id
        }
      )

    assert %{"error" => %{"message" => message}} = json_response(conn, 422)
    assert message =~ "not approved"
  end
end
