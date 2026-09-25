defmodule PosbdWeb.Api.SubscriptionJSON do
  alias Posbd.Subscriptions.{SubscriptionPayment, SubscriptionPlan}
  alias PosbdWeb.Api.ProductJSON

  def show(%{summary: summary, plans: plans}) do
    %{
      data: %{
        status: summary.status,
        entitled: summary.entitled,
        trial_ends_at: summary.trial_ends_at,
        days_remaining: summary.days_remaining,
        plan: summary.plan && plan_json(summary.plan),
        plans: Enum.map(plans, &plan_json/1)
      }
    }
  end

  def payments(%{payments: payments}) do
    %{data: Enum.map(payments, &payment_json/1)}
  end

  def checkout(%{checkout: checkout}) do
    %{
      data: %{
        order_id: checkout.order_id,
        key_id: checkout.key_id,
        amount: ProductJSON.money(checkout.amount),
        currency: checkout.currency
      }
    }
  end

  def activated(%{result: %{subscription: subscription, payment: payment}}) do
    %{
      data: %{
        status: subscription.status,
        plan: subscription.plan && plan_json(subscription.plan),
        current_period_end: subscription.current_period_end,
        payment: payment_json(payment)
      }
    }
  end

  def plan_json(%SubscriptionPlan{} = plan) do
    %{
      id: plan.id,
      name: plan.name,
      slug: plan.slug,
      description: plan.description,
      price: ProductJSON.money(plan.price),
      currency: plan.currency,
      billing_period: plan.billing_period,
      features: plan.features,
      is_active: plan.is_active
    }
  end

  defp payment_json(%SubscriptionPayment{} = payment) do
    %{
      id: payment.id,
      plan_name: payment.plan_name_snapshot,
      amount: ProductJSON.money(payment.amount),
      currency: payment.currency,
      period_start: payment.period_start,
      period_end: payment.period_end,
      status: payment.status,
      payment_provider: payment.payment_provider,
      provider_reference: payment.provider_reference,
      paid_at: payment.paid_at,
      inserted_at: payment.inserted_at
    }
  end
end
