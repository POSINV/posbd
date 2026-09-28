defmodule PosbdWeb.Api.WhatsappCampaignJSON do
  alias Posbd.Whatsapp.WhatsappCampaign
  alias PosbdWeb.Api.WhatsappTemplateJSON

  def index(%{campaigns: campaigns}), do: %{data: Enum.map(campaigns, &campaign_json/1)}

  def show(%{campaign: campaign} = assigns) do
    data = campaign_json(campaign)
    data = if stats = assigns[:stats], do: Map.put(data, :stats, stats), else: data
    %{data: data}
  end

  defp campaign_json(%WhatsappCampaign{} = campaign) do
    %{
      id: campaign.id,
      name: campaign.name,
      audience_segment: campaign.audience_segment,
      status: campaign.status,
      scheduled_at: campaign.scheduled_at,
      template: template(campaign),
      inserted_at: campaign.inserted_at
    }
  end

  defp template(%WhatsappCampaign{template: %Ecto.Association.NotLoaded{}}), do: nil
  defp template(%WhatsappCampaign{template: nil}), do: nil

  defp template(%WhatsappCampaign{template: template}),
    do: WhatsappTemplateJSON.template_json(template)
end
