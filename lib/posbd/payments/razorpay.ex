defmodule Posbd.Payments.Razorpay do
  @moduledoc """
  Thin client for Razorpay's Orders API plus the two signature checks
  that are the actual security boundary of checkout (Phase 2 §10/§11):

  - `verify_payment_signature/3` is the only thing allowed to turn a
    Razorpay Checkout "success" callback into an activated subscription -
    the frontend saying "payment succeeded" is never trusted on its own.
  - `verify_webhook_signature/2` does the same for asynchronous webhook
    deliveries, using a *separate* secret from the checkout signature.

  Order creation goes through `Req` (per AGENTS.md - always Req, never
  httpoison/tesla/httpc); tests swap in `Req.Test` via the `:req_options`
  config instead of hitting the real API.
  """

  @orders_url "https://api.razorpay.com/v1/orders"

  defp config, do: Application.get_env(:posbd, :razorpay, [])

  def key_id, do: config()[:key_id]

  def configured? do
    cfg = config()
    is_binary(cfg[:key_id]) and is_binary(cfg[:key_secret])
  end

  @doc """
  Creates a Razorpay Order for `amount` (a `Decimal` in the plan's major
  currency unit, e.g. rupees) and `currency` (e.g. `"INR"`). Razorpay
  wants the amount in the smallest currency unit (paise), so it's
  converted here rather than asking every caller to remember that.
  """
  def create_order(%Decimal{} = amount, currency, receipt) do
    paise = amount |> Decimal.mult(100) |> Decimal.round(0) |> Decimal.to_integer()

    req()
    |> Req.post(url: @orders_url, json: %{amount: paise, currency: currency, receipt: receipt})
    |> case do
      {:ok, %{status: 200, body: %{"id" => order_id}}} ->
        {:ok, order_id}

      {:ok, %{status: status, body: body}} ->
        {:error, %{message: "Razorpay order creation failed (HTTP #{status})", body: body}}

      {:error, reason} ->
        {:error, %{message: "Could not reach Razorpay", reason: inspect(reason)}}
    end
  end

  defp req do
    cfg = config()
    Req.new([auth: {:basic, "#{cfg[:key_id]}:#{cfg[:key_secret]}"}] ++ (cfg[:req_options] || []))
  end

  @doc """
  Verifies a Razorpay Checkout success payload. Razorpay signs
  `"order_id|payment_id"` with HMAC-SHA256 using the account's key
  secret; this recomputes it and compares in constant time.
  """
  def verify_payment_signature(order_id, payment_id, signature) do
    expected = hmac(config()[:key_secret], "#{order_id}|#{payment_id}")
    secure_compare(expected, signature)
  end

  @doc "Verifies a webhook delivery's `X-Razorpay-Signature` header against the *raw* request body, using the separate webhook secret configured in the Razorpay dashboard."
  def verify_webhook_signature(raw_body, signature) do
    expected = hmac(config()[:webhook_secret], raw_body)
    secure_compare(expected, signature)
  end

  defp hmac(secret, data) do
    :crypto.mac(:hmac, :sha256, secret || "", data) |> Base.encode16(case: :lower)
  end

  defp secure_compare(a, b) when is_binary(a) and is_binary(b),
    do: Plug.Crypto.secure_compare(a, b)

  defp secure_compare(_a, _b), do: false
end
