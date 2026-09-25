defmodule Posbd.Payments.RazorpayTest do
  use ExUnit.Case, async: true

  alias Posbd.Payments.Razorpay

  # Matches the fixed test-only secrets in config/test.exs.
  @key_secret "fake_key_secret"
  @webhook_secret "fake_webhook_secret"

  defp hmac(secret, data),
    do: :crypto.mac(:hmac, :sha256, secret, data) |> Base.encode16(case: :lower)

  describe "verify_payment_signature/3" do
    test "accepts a correctly signed order_id|payment_id pair" do
      signature = hmac(@key_secret, "order_1|pay_1")
      assert Razorpay.verify_payment_signature("order_1", "pay_1", signature)
    end

    test "rejects a tampered or missing signature" do
      refute Razorpay.verify_payment_signature("order_1", "pay_1", "not-the-real-signature")
      refute Razorpay.verify_payment_signature("order_1", "pay_1", nil)
    end

    test "rejects a signature computed for different ids" do
      signature = hmac(@key_secret, "order_1|pay_1")
      refute Razorpay.verify_payment_signature("order_2", "pay_1", signature)
    end
  end

  describe "verify_webhook_signature/2" do
    test "accepts a body signed with the separate webhook secret" do
      body = ~s({"event":"payment.captured"})
      assert Razorpay.verify_webhook_signature(body, hmac(@webhook_secret, body))
    end

    test "a checkout signature does not also validate as a webhook signature" do
      body = ~s({"event":"payment.captured"})
      refute Razorpay.verify_webhook_signature(body, hmac(@key_secret, body))
    end
  end

  describe "create_order/3" do
    test "converts the amount to paise and returns the order id" do
      Req.Test.stub(Razorpay, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)

        assert Jason.decode!(body) == %{
                 "amount" => 99900,
                 "currency" => "INR",
                 "receipt" => "receipt-1"
               }

        Req.Test.json(conn, %{"id" => "order_abc123"})
      end)

      assert {:ok, "order_abc123"} =
               Razorpay.create_order(Decimal.new("999.00"), "INR", "receipt-1")
    end

    test "surfaces a non-200 response as an error" do
      Req.Test.stub(Razorpay, fn conn ->
        conn
        |> Plug.Conn.put_status(400)
        |> Req.Test.json(%{"error" => %{"description" => "bad request"}})
      end)

      assert {:error, %{message: message}} =
               Razorpay.create_order(Decimal.new("10.00"), "INR", "r2")

      assert message =~ "400"
    end
  end

  describe "configured?/0" do
    test "true when both key id and secret are set (as they are in test config)" do
      assert Razorpay.configured?()
    end
  end
end
