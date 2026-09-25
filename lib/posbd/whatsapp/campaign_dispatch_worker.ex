defmodule Posbd.Whatsapp.CampaignDispatchWorker do
  @moduledoc """
  Fans a campaign out to its audience (Phase 2 §28/§35). Runs entirely in
  the background - queuing every recipient's `SendMessageWorker` job is
  the only work done here, so a campaign of any size can never turn into
  a slow or blocking HTTP request.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias Posbd.Whatsapp

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"campaign_id" => campaign_id}}) do
    Whatsapp.dispatch_campaign(campaign_id)
  end
end
