defmodule PosbdWeb.Api.Admin.WhatsappTemplateControllerTest do
  use PosbdWeb.ConnCase, async: true

  import Posbd.BusinessesFixtures
  import Posbd.SubscriptionsFixtures
  import Posbd.WhatsappFixtures

  defp admin_conn(role \\ "admin") do
    admin = platform_admin_fixture(role: role)
    token = Posbd.PlatformAdmins.create_api_token(admin)
    build_conn() |> put_req_header("authorization", "Bearer #{token}")
  end

  test "GET /admin/whatsapp/templates lists templates pending review by default" do
    scope = full_scope_fixture()
    pending = template_fixture(scope)

    conn = get(admin_conn(), ~p"/api/v1/admin/whatsapp/templates")

    assert %{"data" => [%{"id" => id, "business" => %{"id" => business_id}}]} =
             json_response(conn, 200)

    assert id == pending.id
    assert business_id == scope.business.id
  end

  test "an admin can approve a template" do
    scope = full_scope_fixture()
    template = template_fixture(scope)

    conn =
      post(admin_conn(), ~p"/api/v1/admin/whatsapp/templates/#{template.id}/approve", %{
        "provider_template_name" => "bill_ready_v1"
      })

    assert %{"data" => %{"status" => "approved", "provider_template_name" => "bill_ready_v1"}} =
             json_response(conn, 200)
  end

  test "an admin can reject a template with a reason" do
    scope = full_scope_fixture()
    template = template_fixture(scope)

    conn =
      post(admin_conn(), ~p"/api/v1/admin/whatsapp/templates/#{template.id}/reject", %{
        "reason" => "Contains discouraged wording"
      })

    assert %{
             "data" => %{
               "status" => "rejected",
               "rejected_reason" => "Contains discouraged wording"
             }
           } =
             json_response(conn, 200)
  end

  test "a support-role admin cannot approve a template" do
    scope = full_scope_fixture()
    template = template_fixture(scope)

    conn =
      post(admin_conn("support"), ~p"/api/v1/admin/whatsapp/templates/#{template.id}/approve", %{
        "provider_template_name" => "x"
      })

    assert json_response(conn, 403)
  end
end
