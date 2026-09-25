defmodule PosbdWeb.Api.Admin.SubscriptionJSON do
  alias PosbdWeb.Api.ProductJSON
  alias PosbdWeb.Api.SubscriptionJSON, as: PlanJSON

  def activated(%{result: %{subscription: subscription, payment: payment}}) do
    %{
      data: %{
        subscription: subscription_json(subscription),
        payment: %{
          id: payment.id,
          amount: ProductJSON.money(payment.amount),
          currency: payment.currency,
          status: payment.status
        }
      }
    }
  end

  def cancelled(%{subscription: subscription}) do
    %{data: subscription_json(subscription)}
  end

  defp subscription_json(subscription) do
    %{
      id: subscription.id,
      business_id: subscription.business_id,
      status: subscription.status,
      plan: subscription.plan && PlanJSON.plan_json(subscription.plan),
      current_period_start: subscription.current_period_start,
      current_period_end: subscription.current_period_end,
      cancelled_at: subscription.cancelled_at
    }
  end
end
