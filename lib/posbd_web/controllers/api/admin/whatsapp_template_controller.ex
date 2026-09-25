defmodule PosbdWeb.Api.Admin.WhatsappTemplateController do
  use PosbdWeb, :controller

  alias Posbd.Whatsapp
  alias PosbdWeb.Api.Admin.Authorize
  alias PosbdWeb.Api.WhatsappTemplateJSON

  action_fallback PosbdWeb.Api.FallbackController

  @doc "Lists templates awaiting review by default (`?status=` to see any other status, e.g. `approved`/`rejected`/`all`)."
  def index(conn, params) do
    status_filter = if params["status"] in [nil, "", "all"], do: nil, else: params["status"]
    templates = Whatsapp.list_templates_for_review(status_filter || "pending_approval")
    json(conn, %{data: Enum.map(templates, &business_template_json/1)})
  end

  def approve(
        %{assigns: %{current_platform_admin: admin}} = conn,
        %{"id" => id, "provider_template_name" => provider_template_name}
      ) do
    with :ok <- Authorize.require_admin_role(admin),
         %Whatsapp.WhatsappTemplate{} = template <- Whatsapp.get_template_for_review(id),
         {:ok, updated} <- Whatsapp.approve_template(admin, template, provider_template_name) do
      json(conn, %{data: business_template_json(updated)})
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  def reject(
        %{assigns: %{current_platform_admin: admin}} = conn,
        %{"id" => id, "reason" => reason}
      ) do
    with :ok <- Authorize.require_admin_role(admin),
         %Whatsapp.WhatsappTemplate{} = template <- Whatsapp.get_template_for_review(id),
         {:ok, updated} <- Whatsapp.reject_template(admin, template, reason) do
      json(conn, %{data: business_template_json(updated)})
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  defp business_template_json(template) do
    template
    |> WhatsappTemplateJSON.template_json()
    |> Map.put(:business, %{id: template.business.id, name: template.business.name})
  end
end
