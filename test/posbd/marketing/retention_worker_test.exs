defmodule Posbd.Marketing.RetentionWorkerTest do
  use Posbd.DataCase, async: true

  alias Posbd.Marketing.RetentionWorker
  alias Posbd.Whatsapp.WhatsappMessage

  import Posbd.BusinessesFixtures
  import Posbd.CustomersFixtures
  import Posbd.WhatsappFixtures

  test "runs retention for every business" do
    scope = full_scope_fixture()
    approved_template_fixture(scope, %{"purpose" => "birthday"})
    today = Date.utc_today()
    birthday = %{today | year: today.year - 30}
    customer_fixture(scope, date_of_birth: birthday, accepts_promotional_messages: true)

    assert :ok = perform_job(RetentionWorker, %{})
    assert [_message] = Repo.all(WhatsappMessage)
  end
end
