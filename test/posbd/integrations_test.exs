defmodule Posbd.IntegrationsTest do
  # Flips global application env, so it can't run alongside async tests.
  use Posbd.DataCase, async: false

  alias Posbd.Integrations
  alias Posbd.Payments.Razorpay
  alias Posbd.Whatsapp
  alias Posbd.Whatsapp.{Provider, SendMessageWorker, WhatsappMessage}

  import Posbd.BusinessesFixtures
  import Posbd.CustomersFixtures
  import Posbd.WhatsappFixtures

  setup do
    Application.put_env(:posbd, :app_env, "local")
    Application.put_env(:posbd, :integrations_enabled, false)

    on_exit(fn ->
      Application.put_env(:posbd, :app_env, "test")
      Application.put_env(:posbd, :integrations_enabled, true)
    end)
  end

  test "every integration reports disabled in local" do
    status = Integrations.status()
    assert status.app_env == "local"

    for name <- [:email, :whatsapp, :razorpay] do
      refute Integrations.enabled?(name)
      refute status.integrations[name].enabled
    end
  end

  test "Razorpay order creation never calls the API in local" do
    Req.Test.stub(Razorpay, fn _conn -> flunk("Razorpay API must not be called in local") end)

    assert {:error, %{message: message, integration_disabled: true}} =
             Razorpay.create_order(Decimal.new("499.00"), "INR", "receipt-1")

    assert message =~ "Razorpay is disabled in the local environment"
  end

  test "a queued WhatsApp message is marked failed and not retried in local" do
    Req.Test.stub(Provider, fn _conn -> flunk("WhatsApp API must not be called in local") end)

    scope = full_scope_fixture()
    approved_template_fixture(scope)
    customer = customer_fixture(scope)

    {:ok, message} =
      Whatsapp.notify_invoice_created(scope.business, %{
        customer: customer,
        invoice_number: "INV-1",
        currency: "INR",
        total_amount: Decimal.new("100.00"),
        loyalty_points_earned: 0
      })

    job = Repo.get_by!(Oban.Job, worker: "Posbd.Whatsapp.SendMessageWorker")

    assert {:cancel, _reason} = perform_job(SendMessageWorker, job.args)

    reloaded = Repo.get!(WhatsappMessage, message.id)
    assert reloaded.status == "failed"
    assert reloaded.error_message =~ "WhatsApp is disabled in the local environment"
  end
end
