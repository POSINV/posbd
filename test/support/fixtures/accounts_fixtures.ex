defmodule Posbd.AccountsFixtures do
  alias Posbd.Accounts

  def valid_user_email, do: "user#{System.unique_integer()}@example.com"
  def valid_user_password, do: "supersecret1"

  def valid_user_attrs(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: valid_user_email(),
      password: valid_user_password(),
      full_name: "Test User"
    })
  end

  def user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> valid_user_attrs()
      |> Accounts.register_user()

    user
  end
end
