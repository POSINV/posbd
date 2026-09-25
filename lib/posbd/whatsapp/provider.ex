defmodule Posbd.Whatsapp.Provider do
  @moduledoc """
  Thin client for the official WhatsApp Business Platform (Meta Cloud
  API) - Phase 2 §23 is explicit that this must be the real, approved
  API, never an unofficial/browser-automation integration.

  Sends go through `Req` (per AGENTS.md - always Req, never
  httpoison/tesla/httpc); tests swap in `Req.Test` via `:req_options`
  instead of hitting the real API. `verify_webhook_signature/2` is the
  security boundary for inbound delivery-status callbacks - Meta signs
  the raw request body with the app secret over HMAC-SHA256, and that's
  the only thing allowed to turn a webhook delivery into a status update.
  """

  defp config, do: Application.get_env(:posbd, :whatsapp, [])

  def configured? do
    cfg = config()
    is_binary(cfg[:access_token]) and is_binary(cfg[:phone_number_id])
  end

  @doc "The token Meta's webhook verification handshake (`GET .../webhooks/whatsapp`) must present back to us."
  def webhook_verify_token, do: config()[:webhook_verify_token]

  @doc """
  Sends an approved template message to `to` (a phone number, digits
  only, with country code - no `+` or spaces) rendering `provider_template_name`
  in `language_code` (e.g. `"en_US"`) with `variables` (a list of strings
  substituted for `{{1}}`, `{{2}}`, ... in order).
  """
  def send_template_message(to, provider_template_name, language_code, variables) do
    body = %{
      messaging_product: "whatsapp",
      to: to,
      type: "template",
      template: %{
        name: provider_template_name,
        language: %{code: language_code},
        components: template_components(variables)
      }
    }

    req()
    |> Req.post(url: messages_path(), json: body)
    |> case do
      {:ok, %{status: 200, body: %{"messages" => [%{"id" => message_id} | _]}}} ->
        {:ok, message_id}

      {:ok, %{status: status, body: body}} ->
        {:error, %{message: "WhatsApp send failed (HTTP #{status})", body: body}}

      {:error, reason} ->
        {:error, %{message: "Could not reach WhatsApp", reason: inspect(reason)}}
    end
  end

  defp template_components([]), do: []

  defp template_components(variables) do
    [%{type: "body", parameters: Enum.map(variables, &%{type: "text", text: to_string(&1)})}]
  end

  defp messages_path do
    cfg = config()
    "https://graph.facebook.com/#{cfg[:api_version] || "v21.0"}/#{cfg[:phone_number_id]}/messages"
  end

  defp req do
    cfg = config()
    Req.new([auth: {:bearer, cfg[:access_token]}] ++ (cfg[:req_options] || []))
  end

  @doc "Verifies the `X-Hub-Signature-256` header on an inbound webhook delivery against the *raw* request body."
  def verify_webhook_signature(raw_body, "sha256=" <> signature) do
    expected =
      :crypto.mac(:hmac, :sha256, config()[:app_secret] || "", raw_body)
      |> Base.encode16(case: :lower)

    secure_compare(expected, signature)
  end

  def verify_webhook_signature(_raw_body, _signature), do: false

  defp secure_compare(a, b) when is_binary(a) and is_binary(b),
    do: Plug.Crypto.secure_compare(a, b)

  defp secure_compare(_a, _b), do: false
end
