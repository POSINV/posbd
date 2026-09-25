defmodule Posbd.Whatsapp.SendMessageWorkerTest do
  use Posbd.DataCase, async: true

  alias Posbd.Whatsapp
  alias Posbd.Whatsapp.{Provider, SendMessageWorker, WhatsappMessage}

  import Posbd.BusinessesFixtures
  import Posbd.CustomersFixtures
  import Posbd.WhatsappFixtures

  setup do
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
    %{message: message, job: job}
  end

  test "a successful send marks the message sent with the provider message id", %{
    job: job,
    message: message
  } do
    Req.Test.stub(Provider, fn conn ->
      Req.Test.json(conn, %{"messages" => [%{"id" => "wamid.SUCCESS"}]})
    end)

    assert :ok = perform_job(SendMessageWorker, job.args)

    reloaded = Repo.get!(WhatsappMessage, message.id)
    assert reloaded.status == "sent"
    assert reloaded.provider_message_id == "wamid.SUCCESS"
  end

  test "a failed send marks the message failed and asks Oban to retry", %{
    job: job,
    message: message
  } do
    Req.Test.stub(Provider, fn conn ->
      conn |> Plug.Conn.put_status(500) |> Req.Test.json(%{"error" => "boom"})
    end)

    assert {:error, _reason} = perform_job(SendMessageWorker, job.args)

    reloaded = Repo.get!(WhatsappMessage, message.id)
    assert reloaded.status == "failed"
  end

  test "a message that no longer exists is a no-op" do
    assert :ok =
             perform_job(SendMessageWorker, %{
               "message_id" => Ecto.UUID.generate(),
               "phone" => "1",
               "provider_template_name" => "x",
               "language" => "en",
               "variables" => []
             })
  end
end
