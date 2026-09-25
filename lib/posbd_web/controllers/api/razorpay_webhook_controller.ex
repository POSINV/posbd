defmodule PosbdWeb.Api.RazorpayWebhookController do
  @moduledoc """
  Receives Razorpay webhook deliveries (Phase 2 §11) - the durable,
  authoritative confirmation path for subscription payments, independent
  of whether the customer's browser made it back to the checkout-verify
  call. Every delivery is signature-verified against the raw request
  body and recorded idempotently via `Posbd.Subscriptions.process_webhook_event/3`.
  """

  use PosbdWeb, :controller

  alias Posbd.Payments.Razorpay
  alias Posbd.Subscriptions

  def create(conn, params) do
    raw_body = conn.assigns[:raw_body] || ""

    case get_req_header(conn, "x-razorpay-signature") do
      [signature] when is_binary(signature) ->
        if Razorpay.verify_webhook_signature(raw_body, signature) do
          :ok =
            Subscriptions.process_webhook_event(
              params["event"],
              event_id_for(conn, params),
              params
            )

          send_resp(conn, :ok, "")
        else
          conn
          |> put_status(:unauthorized)
          |> json(%{error: %{message: "Invalid webhook signature"}})
        end

      _ ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: %{message: "Missing webhook signature"}})
    end
  end

  # Razorpay sends an X-Razorpay-Event-Id header on newer webhook setups;
  # fall back to a deterministic composite key so idempotency still holds
  # even without it (a genuine retry of the same delivery carries the same
  # event/payment id/timestamp, so it still collides on the unique index).
  defp event_id_for(conn, params) do
    case get_req_header(conn, "x-razorpay-event-id") do
      [id | _] -> id
      [] -> fallback_event_id(params)
    end
  end

  defp fallback_event_id(params) do
    payment_id = get_in(params, ["payload", "payment", "entity", "id"])
    "#{params["event"]}-#{payment_id}-#{params["created_at"]}"
  end
end
