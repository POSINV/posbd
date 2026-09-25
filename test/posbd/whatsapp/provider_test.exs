defmodule Posbd.Whatsapp.ProviderTest do
  use ExUnit.Case, async: true

  alias Posbd.Whatsapp.Provider

  # Matches the fixed test-only app secret in config/test.exs.
  @app_secret "fake_app_secret"

  defp hmac(secret, data),
    do: :crypto.mac(:hmac, :sha256, secret, data) |> Base.encode16(case: :lower)

  describe "send_template_message/4" do
    test "posts the template + variables and returns the provider message id" do
      Req.Test.stub(Provider, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)

        assert Jason.decode!(body) == %{
                 "messaging_product" => "whatsapp",
                 "to" => "919990001111",
                 "type" => "template",
                 "template" => %{
                   "name" => "bill_ready",
                   "language" => %{"code" => "en_US"},
                   "components" => [
                     %{
                       "type" => "body",
                       "parameters" => [%{"type" => "text", "text" => "Priya"}]
                     }
                   ]
                 }
               }

        Req.Test.json(conn, %{"messages" => [%{"id" => "wamid.ABC123"}]})
      end)

      assert {:ok, "wamid.ABC123"} =
               Provider.send_template_message("919990001111", "bill_ready", "en_US", ["Priya"])
    end

    test "surfaces a non-200 response as an error" do
      Req.Test.stub(Provider, fn conn ->
        conn |> Plug.Conn.put_status(400) |> Req.Test.json(%{"error" => %{"message" => "bad"}})
      end)

      assert {:error, %{message: message}} =
               Provider.send_template_message("919990001111", "bill_ready", "en_US", [])

      assert message =~ "400"
    end
  end

  describe "verify_webhook_signature/2" do
    test "accepts a body signed with the app secret" do
      body = ~s({"entry":[]})
      assert Provider.verify_webhook_signature(body, "sha256=" <> hmac(@app_secret, body))
    end

    test "rejects a tampered body or missing signature" do
      refute Provider.verify_webhook_signature(~s({"entry":[]}), "sha256=not-real")
      refute Provider.verify_webhook_signature(~s({"entry":[]}), nil)
    end
  end

  describe "configured?/0" do
    test "true when both an access token and phone_number_id are set" do
      assert Provider.configured?()
    end
  end
end
