defmodule PosbdWeb.Api.WhatsappCampaignController do
  use PosbdWeb, :controller

  alias Posbd.Whatsapp
  alias PosbdWeb.Api.Authorize

  action_fallback PosbdWeb.Api.FallbackController

  def index(%{assigns: %{current_scope: scope}} = conn, _params) do
    with :ok <- Authorize.require(scope, "whatsapp.manage") do
      render(conn, :index, campaigns: Whatsapp.list_campaigns(scope))
    end
  end

  def show(%{assigns: %{current_scope: scope}} = conn, %{"id" => id}) do
    with :ok <- Authorize.require(scope, "whatsapp.manage") do
      case Whatsapp.get_campaign(scope, id) do
        nil ->
          {:error, :not_found}

        campaign ->
          render(conn, :show, campaign: campaign, stats: Whatsapp.campaign_stats(scope, campaign))
      end
    end
  end

  @doc "Creates a draft campaign and, unless `scheduled_at` is given, dispatches it immediately (Phase 2 §28)."
  def create(%{assigns: %{current_scope: scope}} = conn, %{"campaign" => attrs} = params) do
    with :ok <- Authorize.require(scope, "whatsapp.manage"),
         {:ok, campaign} <- Whatsapp.create_campaign(scope, attrs),
         {:ok, scheduled_at} <- parse_scheduled_at(params["campaign"]["scheduled_at"]),
         {:ok, campaign} <- Whatsapp.schedule_campaign(scope, campaign, scheduled_at) do
      conn |> put_status(:created) |> render(:show, campaign: campaign)
    end
  end

  def cancel(%{assigns: %{current_scope: scope}} = conn, %{"id" => id}) do
    with :ok <- Authorize.require(scope, "whatsapp.manage"),
         campaign when not is_nil(campaign) <- Whatsapp.get_campaign(scope, id),
         {:ok, updated} <- Whatsapp.cancel_campaign(scope, campaign) do
      render(conn, :show, campaign: updated)
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  defp parse_scheduled_at(nil), do: {:ok, nil}
  defp parse_scheduled_at(""), do: {:ok, nil}

  defp parse_scheduled_at(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} -> {:ok, DateTime.truncate(dt, :second)}
      _ -> {:error, %{message: "invalid scheduled_at: #{value}"}}
    end
  end
end
