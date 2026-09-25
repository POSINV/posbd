defmodule Posbd.PlatformAdminsTest do
  use Posbd.DataCase, async: true

  alias Posbd.PlatformAdmins

  import Posbd.SubscriptionsFixtures

  describe "get_by_email_and_password/2" do
    test "returns the admin for correct credentials" do
      admin = platform_admin_fixture(email: "ops@example.com", password: "supersecret1")

      assert %{id: id} =
               PlatformAdmins.get_by_email_and_password("ops@example.com", "supersecret1")

      assert id == admin.id
    end

    test "returns nil for a wrong password without leaking whether the email exists" do
      platform_admin_fixture(email: "ops2@example.com", password: "supersecret1")

      refute PlatformAdmins.get_by_email_and_password("ops2@example.com", "wrongpass")
      refute PlatformAdmins.get_by_email_and_password("nobody@example.com", "wrongpass")
    end
  end

  describe "API tokens" do
    test "create/fetch/revoke round-trip" do
      admin = platform_admin_fixture()
      token = PlatformAdmins.create_api_token(admin)

      assert %{id: id} = PlatformAdmins.fetch_admin_by_api_token(token)
      assert id == admin.id

      :ok = PlatformAdmins.revoke_api_token(token)
      refute PlatformAdmins.fetch_admin_by_api_token(token)
    end

    test "an invalid token fetches nothing" do
      refute PlatformAdmins.fetch_admin_by_api_token("not-a-real-token")
    end
  end
end
