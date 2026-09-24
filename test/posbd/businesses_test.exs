defmodule Posbd.BusinessesTest do
  use Posbd.DataCase, async: true

  alias Posbd.Accounts.Scope
  alias Posbd.Businesses

  import Posbd.AccountsFixtures
  import Posbd.BusinessesFixtures

  setup do
    user = user_fixture()
    %{scope: Scope.for_user(user), user: user}
  end

  describe "create_business/2" do
    test "creates the business and makes the scope's user its owner", %{scope: scope} do
      assert {:ok, business} = Businesses.create_business(scope, valid_business_attrs())

      assert [{^business, "owner"}] = Businesses.list_businesses_for_user(scope)
    end

    test "rejects an unsupported business type", %{scope: scope} do
      assert {:error, changeset} =
               Businesses.create_business(scope, valid_business_attrs(business_type: "spaceship"))

      assert "is not a supported business type" in errors_on(changeset).business_type
    end

    test "requires a name", %{scope: scope} do
      assert {:error, changeset} =
               Businesses.create_business(scope, valid_business_attrs(name: nil))

      assert "can't be blank" in errors_on(changeset).name
    end
  end

  describe "tenant isolation" do
    test "a user cannot fetch another user's business", %{scope: scope} do
      other_scope = Scope.for_user(user_fixture())
      business = business_fixture(other_scope)

      refute Businesses.get_business_for_user(scope, business.id)
    end

    test "list_businesses_for_user/1 only returns the scope's own businesses", %{scope: scope} do
      _mine = business_fixture(scope, name: "Mine")
      _other = business_fixture(Scope.for_user(user_fixture()), name: "Theirs")

      names =
        scope |> Businesses.list_businesses_for_user() |> Enum.map(fn {b, _role} -> b.name end)

      assert names == ["Mine"]
    end
  end

  describe "update_business/3" do
    test "updates invoice header/printing fields" do
      scope = full_scope_fixture()

      assert {:ok, updated} =
               Businesses.update_business(scope, scope.business, %{
                 address: "12 MG Road, Bengaluru",
                 phone: "9876543210",
                 email: "shop@example.com",
                 tax_number: "29ABCDE1234F1Z5",
                 invoice_footer: "Thank you for shopping with us!",
                 invoice_terms: "Goods once sold will not be taken back."
               })

      assert updated.address == "12 MG Road, Bengaluru"
      assert updated.tax_number == "29ABCDE1234F1Z5"
      assert updated.invoice_footer == "Thank you for shopping with us!"
    end

    test "updates printer settings and rejects an unsupported paper width" do
      scope = full_scope_fixture()

      assert {:ok, updated} =
               Businesses.update_business(scope, scope.business, %{
                 printer_paper_width: "58mm",
                 printer_header_align: "left",
                 default_print_layout: "a4"
               })

      assert updated.printer_paper_width == "58mm"
      assert updated.default_print_layout == "a4"

      assert {:error, changeset} =
               Businesses.update_business(scope, updated, %{printer_paper_width: "poster-size"})

      assert "is invalid" in errors_on(changeset).printer_paper_width
    end

    test "logs a business.settings_updated audit entry when fields change" do
      scope = full_scope_fixture()

      assert {:ok, _updated} =
               Businesses.update_business(scope, scope.business, %{address: "12 MG Road"})

      assert [log] = Posbd.AuditLogs.list(scope).data
      assert log.action == "business.settings_updated"
      assert "address" in log.metadata["fields"]
    end
  end

  describe "complete_onboarding/2" do
    test "stamps onboarding_completed_at" do
      scope = full_scope_fixture()
      assert is_nil(scope.business.onboarding_completed_at)

      assert {:ok, updated} = Businesses.complete_onboarding(scope, scope.business)
      assert updated.onboarding_completed_at
    end
  end
end
