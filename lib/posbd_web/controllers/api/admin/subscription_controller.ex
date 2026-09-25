defmodule PosbdWeb.Api.Admin.SubscriptionController do
  use PosbdWeb, :controller

  alias Posbd.{Businesses, Subscriptions}
  alias Posbd.Businesses.Business
  alias Posbd.Subscriptions.SubscriptionPlan
  alias PosbdWeb.Api.Admin.Authorize

  action_fallback PosbdWeb.Api.FallbackController

  @doc """
  Activates a plan for a business and records the payment that funded it
  (Phase 2 §12). This is the manual stand-in for automated checkout until
  a payment provider is wired up - only an "admin"-role platform admin
  can call it, so a business can never grant itself access.
  """
  def activate_plan(
        %{assigns: %{current_platform_admin: admin}} = conn,
        %{"business_id" => business_id, "plan_id" => plan_id} = params
      ) do
    with :ok <- Authorize.require_admin_role(admin),
         %Business{} = business <- Businesses.get_business(business_id),
         %SubscriptionPlan{} = plan <- Subscriptions.get_plan(plan_id),
         {:ok, result} <-
           Subscriptions.activate_plan(
             business,
             plan,
             %{
               payment_provider: params["payment_provider"],
               provider_reference: params["provider_reference"],
               notes: params["notes"]
             },
             admin
           ) do
      render(conn, :activated, result: result)
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  def cancel(
        %{assigns: %{current_platform_admin: admin}} = conn,
        %{"business_id" => business_id}
      ) do
    with :ok <- Authorize.require_admin_role(admin),
         %Business{} = business <- Businesses.get_business(business_id),
         {:ok, subscription} <- Subscriptions.cancel_subscription(business) do
      render(conn, :cancelled, subscription: subscription)
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end
end
