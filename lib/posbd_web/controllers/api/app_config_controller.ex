defmodule PosbdWeb.Api.AppConfigController do
  @moduledoc """
  Public, unauthenticated runtime settings for the frontend: which
  environment this backend is running as and which integrations are
  switched on, so the UI can hide or disable email/WhatsApp/Razorpay
  features in local development instead of letting them fail. Never
  returns any key or secret.
  """

  use PosbdWeb, :controller

  def show(conn, _params) do
    json(conn, %{data: Posbd.Integrations.status()})
  end
end
