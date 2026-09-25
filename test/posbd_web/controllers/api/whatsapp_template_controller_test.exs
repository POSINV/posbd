defmodule PosbdWeb.Api.WhatsappTemplateControllerTest do
  use PosbdWeb.ConnCase, async: true

  alias Posbd.Businesses.Roles

  import Posbd.AccountsFixtures
  import Posbd.BusinessesFixtures
  import Posbd.WhatsappFixtures

  setup do
    %{scope: full_scope_fixture()}
  end

  defp member_scope(%Posbd.Accounts.Scope{business: business} = scope, role) do
    user = user_fixture()

    {:ok, membership} =
      %Posbd.Businesses.Membership{}
      |> Posbd.Businesses.Membership.owner_changeset(business.id, user.id)
      |> Ecto.Changeset.change(role: role, permissions: Roles.default_permissions_for(role))
      |> Posbd.Repo.insert()

    scope |> Map.put(:user, user) |> Map.put(:membership, membership)
  end

  test "full create/list/show/update round-trip", %{scope: scope} do
    create_resp =
      post(authed_conn(scope), ~p"/api/v1/whatsapp/templates", template: valid_template_attrs())

    assert %{"data" => %{"id" => id, "status" => "pending_approval"}} =
             json_response(create_resp, 201)

    index_resp = get(authed_conn(scope), ~p"/api/v1/whatsapp/templates")
    assert %{"data" => [%{"id" => ^id}]} = json_response(index_resp, 200)

    show_resp = get(authed_conn(scope), ~p"/api/v1/whatsapp/templates/#{id}")
    assert %{"data" => %{"id" => ^id}} = json_response(show_resp, 200)

    update_resp =
      patch(authed_conn(scope), ~p"/api/v1/whatsapp/templates/#{id}",
        template: %{"body" => "Updated body"}
      )

    assert %{"data" => %{"body" => "Updated body", "status" => "pending_approval"}} =
             json_response(update_resp, 200)
  end

  test "a cashier cannot manage templates", %{scope: scope} do
    cashier_scope = member_scope(scope, "cashier")

    resp =
      post(authed_conn(cashier_scope), ~p"/api/v1/whatsapp/templates",
        template: valid_template_attrs()
      )

    assert json_response(resp, 403)
  end
end
