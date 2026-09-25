defmodule PosbdWeb.Api.WhatsappWebhookControllerTest do
  use PosbdWeb.ConnCase, async: true

  import Posbd.BusinessesFixtures
  import Posbd.CustomersFixtures
  import Posbd.WhatsappFixtures

  alias Posbd.Whatsapp.{WhatsappMessage}

  defp hmac(secret, data),
    do: :crypto.mac(:hmac, :sha256, secret, data) |> Base.encode16(case: :lower)

  defp signed_post(body_map, signature) do
    body = Jason.encode!(body_map)

    build_conn()
    |> put_req_header("content-type", "application/json")
    |> put_req_header("x-hub-signature-256", signature)
    |> post(~p"/api/v1/webhooks/whatsapp", body)
  end

  test "GET verification handshake echoes the challenge when the verify token matches" do
    conn =
      get(
        build_conn(),
        ~p"/api/v1/webhooks/whatsapp?hub.mode=subscribe&hub.verify_token=fake_verify_token&hub.challenge=12345"
      )

    assert response(conn, 200) == "12345"
  end

  test "GET verification handshake rejects the wrong token" do
    conn =
      get(
        build_conn(),
        ~p"/api/v1/webhooks/whatsapp?hub.mode=subscribe&hub.verify_token=wrong&hub.challenge=12345"
      )

    assert response(conn, 403)
  end

  test "a validly signed status callback updates the matching message" do
    scope = full_scope_fixture()
    approved_template_fixture(scope)
    customer = customer_fixture(scope)

    {:ok, message} =
      Posbd.Whatsapp.notify_invoice_created(scope.business, %{
        customer: customer,
        invoice_number: "INV-1",
        currency: "INR",
        total_amount: Decimal.new("50.00"),
        loyalty_points_earned: 0
      })

    message = message |> WhatsappMessage.sent_changeset("wamid.WEBHOOK1") |> Posbd.Repo.update!()

    body = %{
      "entry" => [
        %{
          "changes" => [
            %{"value" => %{"statuses" => [%{"id" => "wamid.WEBHOOK1", "status" => "delivered"}]}}
          ]
        }
      ]
    }

    signature = "sha256=" <> hmac("fake_app_secret", Jason.encode!(body))
    conn = signed_post(body, signature)

    assert response(conn, 200)
    assert Posbd.Repo.get!(WhatsappMessage, message.id).status == "delivered"
  end

  test "an invalid signature is rejected" do
    conn = signed_post(%{"entry" => []}, "sha256=wrong")
    assert json_response(conn, 401)
  end
end
