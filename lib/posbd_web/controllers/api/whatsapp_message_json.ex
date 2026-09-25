defmodule PosbdWeb.Api.WhatsappMessageJSON do
  alias Posbd.Whatsapp.WhatsappMessage

  def index(%{data: messages, page: page, page_size: page_size, total_count: total_count}) do
    %{
      data: Enum.map(messages, &message_json/1),
      pagination: %{page: page, page_size: page_size, total_count: total_count}
    }
  end

  defp message_json(%WhatsappMessage{} = message) do
    %{
      id: message.id,
      kind: message.kind,
      phone: message.phone,
      body: message.body,
      status: message.status,
      error_message: message.error_message,
      sent_at: message.sent_at,
      delivered_at: message.delivered_at,
      read_at: message.read_at,
      customer: customer(message),
      template_name: template_name(message),
      inserted_at: message.inserted_at
    }
  end

  defp customer(%WhatsappMessage{customer: %Ecto.Association.NotLoaded{}}), do: nil
  defp customer(%WhatsappMessage{customer: nil}), do: nil
  defp customer(%WhatsappMessage{customer: c}), do: %{id: c.id, name: c.name}

  defp template_name(%WhatsappMessage{template: %Ecto.Association.NotLoaded{}}), do: nil
  defp template_name(%WhatsappMessage{template: nil}), do: nil
  defp template_name(%WhatsappMessage{template: t}), do: t.name
end
