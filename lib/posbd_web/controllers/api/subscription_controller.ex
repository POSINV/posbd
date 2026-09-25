defmodule PosbdWeb.Api.SubscriptionController do
  use PosbdWeb, :controller

  alias Posbd.Subscriptions
  alias PosbdWeb.Api.Authorize

  action_fallback PosbdWeb.Api.FallbackController

  @doc "Public plan listing for the marketing/signup pages, reached before a user has an account (Phase 2 §47 - pricing comes from the backend, never hardcoded in Vue)."
  def public_plans(conn, _params) do
    json(conn, %{
      data: Enum.map(Subscriptions.list_plans(), &PosbdWeb.Api.SubscriptionJSON.plan_json/1)
    })
  end

  @doc "Current subscription status + the plans a business can choose from. Never gated by SubscriptionGate - a blocked business must always be able to see this and fix it."
  def show(%{assigns: %{current_scope: scope}} = conn, _params) do
    render(conn, :show,
      summary: Subscriptions.status_summary(scope),
      plans: Subscriptions.list_plans()
    )
  end

  def payments(%{assigns: %{current_scope: scope}} = conn, _params) do
    render(conn, :payments, payments: Subscriptions.list_payments(scope.business))
  end

  @doc "Checkout step 1 (Phase 2 §10) - creates a Razorpay Order for `plan_id` and returns what the frontend needs to open Razorpay Checkout."
  def create_checkout(%{assigns: %{current_scope: scope}} = conn, %{"plan_id" => plan_id}) do
    with :ok <- Authorize.require(scope, "settings.manage"),
         %Subscriptions.SubscriptionPlan{} = plan <- Subscriptions.get_plan(plan_id),
         {:ok, checkout} <- Subscriptions.create_checkout_order(scope, plan) do
      render(conn, :checkout, checkout: checkout)
    else
      nil -> {:error, %{message: "Unknown plan"}}
      error -> error
    end
  end

  @doc "Checkout step 2 - verifies the Razorpay Checkout signature and activates the subscription. Never trusts the frontend's 'payment succeeded' callback on its own (Phase 2 §10)."
  def verify_checkout(%{assigns: %{current_scope: scope}} = conn, params) do
    with :ok <- Authorize.require(scope, "settings.manage"),
         {:ok, result} <-
           Subscriptions.verify_and_activate_checkout(
             scope,
             params["razorpay_order_id"],
             params["razorpay_payment_id"],
             params["razorpay_signature"]
           ) do
      render(conn, :activated, result: result)
    end
  end
end
