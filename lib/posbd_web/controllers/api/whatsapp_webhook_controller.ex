defmodule PosbdWeb.Api.WhatsappWebhookController do
  @moduledoc """
  Receives the Meta Cloud API's webhook (Phase 2 §27) - the delivery
  status source of truth for message history (sent/delivered/read/failed).
  `verify/2` is Meta's one-time subscription handshake; `create/2` is
  signature-verified against the raw request body before anything in
  the payload is trusted.
  """

  use PosbdWeb, :controller

  alias Posbd.Whatsapp

  def verify(conn, %{
        "hub.mode" => "subscribe",
        "hub.verify_token" => token,
        "hub.challenge" => challenge
      }) do
    expected = Whatsapp.Provider.webhook_verify_token() || ""

    if is_binary(token) and Plug.Crypto.secure_compare(token, expected) do
      send_resp(conn, 200, challenge)
    else
      send_resp(conn, 403, "")
    end
  end

  def verify(conn, _params), do: send_resp(conn, 403, "")

  def create(conn, params) do
    raw_body = conn.assigns[:raw_body] || ""

    case get_req_header(conn, "x-hub-signature-256") do
      [signature] when is_binary(signature) ->
        if Whatsapp.Provider.verify_webhook_signature(raw_body, signature) do
          Enum.each(statuses_from(params), fn status ->
            Whatsapp.process_status_update(status["id"], status["status"])
          end)

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

  defp statuses_from(%{"entry" => entries}) when is_list(entries) do
    for entry <- entries,
        change <- entry["changes"] || [],
        status <- get_in(change, ["value", "statuses"]) || [] do
      status
    end
  end

  defp statuses_from(_params), do: []
end
