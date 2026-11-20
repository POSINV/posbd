defmodule PosbdWeb.Plugs.RequireFeature do
  @moduledoc """
  Blocks a request unless the current business's plan includes `feature`
  (see `Posbd.Subscriptions.has_feature?/2` - a business still in its
  trial gets every feature). Hiding a menu item in Vue is never the
  enforcement; the backend has to refuse the call itself.

      plug PosbdWeb.Plugs.RequireFeature, "offers" when action in [:create, :update]
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias Posbd.Subscriptions

  def init(feature) when is_binary(feature), do: feature

  def call(conn, feature) do
    if Subscriptions.has_feature?(conn.assigns.current_scope.business, feature) do
      conn
    else
      conn
      |> put_status(:forbidden)
      |> json(%{
        error: %{
          message: "Your current plan doesn't include this feature. Upgrade your plan to use it.",
          feature: feature
        }
      })
      |> halt()
    end
  end
end
