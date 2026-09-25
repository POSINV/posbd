defmodule Posbd.WhatsappFixtures do
  alias Posbd.Accounts.Scope
  alias Posbd.SubscriptionsFixtures
  alias Posbd.Whatsapp

  def valid_template_attrs(attrs \\ %{}) do
    Enum.into(attrs, %{
      "name" => "Bill Ready #{System.unique_integer()}",
      "purpose" => "billing",
      "category" => "utility",
      "language" => "en",
      "body" => "Hi {{1}}, your bill {{2}} for {{3}} is ready."
    })
  end

  def template_fixture(%Scope{} = scope, attrs \\ %{}) do
    {:ok, template} = Whatsapp.create_template(scope, valid_template_attrs(attrs))
    template
  end

  @doc "A template that has already been approved by a platform admin, ready to actually send with."
  def approved_template_fixture(%Scope{} = scope, attrs \\ %{}) do
    template = template_fixture(scope, attrs)
    admin = SubscriptionsFixtures.platform_admin_fixture()

    provider_name =
      attrs[:provider_template_name] || attrs["provider_template_name"] || template.name

    {:ok, template} = Whatsapp.approve_template(admin, template, provider_name)
    template
  end
end
