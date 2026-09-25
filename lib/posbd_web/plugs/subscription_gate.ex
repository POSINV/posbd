defmodule PosbdWeb.Plugs.SubscriptionGate do
  @moduledoc """
  Blocks tenant-scoped API access once a business's subscription is no
  longer entitled - trial expired without converting, suspended, or
  cancelled (Phase 2 §8/§9). Checked on every gated request; hiding menu
  items in Vue is a UX nicety only, never the actual enforcement - the
  backend must reject the request itself.

  Deliberately not applied to the subscription status/plan endpoints
  themselves (see the router), since a blocked business must always be
  able to see why and pick a plan to fix it.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias Posbd.Subscriptions

  def init(opts), do: opts

  def call(conn, _opts) do
    summary = Subscriptions.status_summary(conn.assigns.current_scope.business)

    if summary.entitled do
      conn
    else
      conn
      |> put_status(:payment_required)
      |> json(%{
        error: %{
          message: "This business's subscription is not active.",
          subscription_status: summary.status
        }
      })
      |> halt()
    end
  end
end
