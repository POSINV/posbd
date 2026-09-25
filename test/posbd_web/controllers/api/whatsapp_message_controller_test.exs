defmodule PosbdWeb.Api.WhatsappMessageControllerTest do
  use PosbdWeb.ConnCase, async: true

  import Posbd.BusinessesFixtures
  import Posbd.CustomersFixtures
  import Posbd.WhatsappFixtures

  test "GET /whatsapp/messages lists message history for the business" do
    scope = full_scope_fixture()
    approved_template_fixture(scope)
    customer = customer_fixture(scope)

    {:ok, _message} =
      Posbd.Whatsapp.notify_invoice_created(scope.business, %{
        customer: customer,
        invoice_number: "INV-1",
        currency: "INR",
        total_amount: Decimal.new("50.00"),
        loyalty_points_earned: 0
      })

    conn = get(authed_conn(scope), ~p"/api/v1/whatsapp/messages")

    assert %{
             "data" => [%{"status" => "queued", "kind" => "transactional"}],
             "pagination" => %{"total_count" => 1}
           } =
             json_response(conn, 200)
  end
end
