defmodule Posbd.BusinessesFixtures do
  alias Posbd.Accounts.Scope
  alias Posbd.Businesses

  @doc """
  Registers a user, creates a business for them, and returns a fully
  populated `%Scope{}` (user + business + membership) - the shape every
  tenant-scoped context function expects.
  """
  def full_scope_fixture(attrs \\ %{}) do
    user = Posbd.AccountsFixtures.user_fixture()
    business = business_fixture(Scope.for_user(user), attrs)
    membership = Businesses.get_membership(Scope.for_user(user), business.id)
    Scope.put_business(Scope.for_user(user), business, membership)
  end

  def valid_business_attrs(attrs \\ %{}) do
    Enum.into(attrs, %{
      name: "Test Business #{System.unique_integer()}",
      business_type: "general",
      country: "IN",
      currency: "INR",
      timezone: "Asia/Kolkata",
      language: "en"
    })
  end

  def business_fixture(%Scope{} = scope, attrs \\ %{}) do
    {:ok, business} = Businesses.create_business(scope, valid_business_attrs(attrs))
    business
  end
end
