defmodule PosbdWeb.Api.WhatsappTemplateJSON do
  alias Posbd.Whatsapp.WhatsappTemplate

  def index(%{templates: templates}), do: %{data: Enum.map(templates, &template_json/1)}
  def show(%{template: template}), do: %{data: template_json(template)}

  def template_json(%WhatsappTemplate{} = template) do
    %{
      id: template.id,
      name: template.name,
      purpose: template.purpose,
      category: template.category,
      language: template.language,
      body: template.body,
      variable_count: template.variable_count,
      status: template.status,
      provider_template_name: template.provider_template_name,
      rejected_reason: template.rejected_reason,
      inserted_at: template.inserted_at
    }
  end
end
