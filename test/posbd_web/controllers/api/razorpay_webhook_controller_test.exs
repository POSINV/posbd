defmodule PosbdWeb.Api.RazorpayWebhookControllerTest do
  use PosbdWeb.ConnCase, async: true

  import Posbd.BusinessesFixtures
  import Posbd.SubscriptionsFixtures

  defp hmac(secret, data),
    do: :crypto.mac(:hmac, :sha256, secret, data) |> Base.encode16(case: :lower)

  defp signed_post(body_map, signature) do
    body = Jason.encode!(body_map)

    build_conn()
    |> put_req_header("content-type", "application/json")
    |> put_req_header("x-razorpay-signature", signature)
    |> post(~p"/api/v1/webhooks/razorpay", body)
  end

  test "a validly signed payment.captured webhook activates the matching subscription" do
    scope = full_scope_fixture()
    plan = plan_fixture()

    Req.Test.stub(Posbd.Payments.Razorpay, fn conn ->
      Req.Test.json(conn, %{"id" => "order_hook1"})
    end)

    {:ok, _} = Posbd.Subscriptions.create_checkout_order(scope, plan)

    body = %{
      "event" => "payment.captured",
      "payload" => %{
        "payment" => %{"entity" => %{"id" => "pay_hook1", "order_id" => "order_hook1"}}
      }
    }

    signature = hmac("fake_webhook_secret", Jason.encode!(body))
    conn = signed_post(body, signature)

    assert response(conn, 200)
    assert Posbd.Subscriptions.status_summary(scope).status == :active
  end

  test "a request with an invalid signature is rejected and changes nothing" do
    scope = full_scope_fixture()
    plan = plan_fixture()

    Req.Test.stub(Posbd.Payments.Razorpay, fn conn ->
      Req.Test.json(conn, %{"id" => "order_hook2"})
    end)

    {:ok, _} = Posbd.Subscriptions.create_checkout_order(scope, plan)

    body = %{
      "event" => "payment.captured",
      "payload" => %{
        "payment" => %{"entity" => %{"id" => "pay_hook2", "order_id" => "order_hook2"}}
      }
    }

    conn = signed_post(body, "wrong-signature")

    assert json_response(conn, 401)
    assert Posbd.Subscriptions.status_summary(scope).status == :trialing
  end

  test "a missing signature header is rejected" do
    conn =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/v1/webhooks/razorpay", Jason.encode!(%{"event" => "payment.captured"}))

    assert json_response(conn, 401)
  end
end
