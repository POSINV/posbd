defmodule Posbd.SubscriptionsFixtures do
  alias Posbd.PlatformAdmins
  alias Posbd.Subscriptions

  def valid_plan_attrs(attrs \\ %{}) do
    Enum.into(attrs, %{
      name: "Growth #{System.unique_integer()}",
      slug: "growth-#{System.unique_integer()}",
      price: "999.00",
      currency: "INR",
      billing_period: "yearly",
      features: %{"loyalty" => true, "whatsapp" => true}
    })
  end

  def plan_fixture(attrs \\ %{}) do
    {:ok, plan} = attrs |> valid_plan_attrs() |> Subscriptions.create_plan()
    plan
  end

  def valid_platform_admin_attrs(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: "admin#{System.unique_integer()}@example.com",
      password: "supersecret1",
      full_name: "Platform Admin",
      role: "admin"
    })
  end

  def platform_admin_fixture(attrs \\ %{}) do
    {:ok, admin} = attrs |> valid_platform_admin_attrs() |> PlatformAdmins.create_admin()
    admin
  end
end
