defmodule Posbd.AccountsTest do
  use Posbd.DataCase, async: true

  alias Posbd.Accounts
  alias Posbd.Accounts.Scope

  import Posbd.AccountsFixtures

  describe "register_user/1" do
    test "creates a user with a hashed password" do
      attrs = valid_user_attrs()
      assert {:ok, user} = Accounts.register_user(attrs)
      assert user.email == String.downcase(attrs.email)
      assert user.hashed_password != attrs.password
      assert is_nil(user.password)
    end

    test "requires email, password, full_name" do
      assert {:error, changeset} = Accounts.register_user(%{})

      assert %{
               email: ["can't be blank"],
               password: ["can't be blank"],
               full_name: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "enforces a minimum password length" do
      assert {:error, changeset} = Accounts.register_user(valid_user_attrs(password: "short"))
      assert "should be at least 8 character(s)" in errors_on(changeset).password
    end

    test "enforces unique, case-insensitive email" do
      %{email: email} = user_fixture()

      assert {:error, changeset} =
               Accounts.register_user(valid_user_attrs(email: String.upcase(email)))

      assert "has already been taken" in errors_on(changeset).email
    end
  end

  describe "get_user_by_email_and_password/2" do
    test "returns the user when credentials are valid" do
      user = user_fixture()

      assert %{id: id} =
               Accounts.get_user_by_email_and_password(user.email, valid_user_password())

      assert id == user.id
    end

    test "returns nil for an invalid password" do
      user = user_fixture()
      refute Accounts.get_user_by_email_and_password(user.email, "wrong-password")
    end

    test "returns nil for an unknown email" do
      refute Accounts.get_user_by_email_and_password("nobody@example.com", "whatever1")
    end
  end

  describe "API tokens" do
    test "create_api_token/1 issues a token that resolves back to a scope for that user" do
      user = user_fixture()
      token = Accounts.create_api_token(user)

      assert %Scope{user: %{id: id}} = Accounts.fetch_scope_by_api_token(token)
      assert id == user.id
    end

    test "fetch_scope_by_api_token/1 returns nil for a bogus token" do
      refute Accounts.fetch_scope_by_api_token("not-a-real-token")
    end

    test "revoke_api_token/1 invalidates the token" do
      user = user_fixture()
      token = Accounts.create_api_token(user)

      assert :ok = Accounts.revoke_api_token(token)
      refute Accounts.fetch_scope_by_api_token(token)
    end
  end
end
