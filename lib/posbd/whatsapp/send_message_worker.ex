defmodule Posbd.Whatsapp.SendMessageWorker do
  @moduledoc """
  Actually calls the WhatsApp provider for one already-created
  `WhatsappMessage` row (Phase 2 §26 - sending is async and never blocks
  the request that decided to send, e.g. the billing transaction).
  Retries transient failures up to `max_attempts`; each attempt updates
  the message row so history always reflects the latest outcome.
  """

  use Oban.Worker, queue: :whatsapp, max_attempts: 5

  alias Posbd.Repo
  alias Posbd.Whatsapp.{Provider, WhatsappMessage}

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    case Repo.get(WhatsappMessage, args["message_id"]) do
      nil ->
        :ok

      message ->
        send_and_record(message, args)
    end
  end

  defp send_and_record(message, args) do
    case Provider.send_template_message(
           args["phone"],
           args["provider_template_name"],
           args["language"],
           args["variables"] || []
         ) do
      {:ok, provider_message_id} ->
        message |> WhatsappMessage.sent_changeset(provider_message_id) |> Repo.update()
        :ok

      {:error, %{message: reason}} ->
        message |> WhatsappMessage.failed_changeset(reason) |> Repo.update()
        {:error, reason}
    end
  end
end
