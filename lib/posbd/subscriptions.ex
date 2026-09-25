defmodule Posbd.Subscriptions do
  @moduledoc """
  SaaS subscription domain (Phase 2 §1-§14): plans, trials, the
  subscription lifecycle, and the platform-level payments businesses make
  to us. Deliberately separate from `Posbd.Billing` (retail payments the
  business's own customers make) - see Phase 2 §2/§36.
  """

  import Ecto.Query, warn: false

  alias Posbd.Payments.Razorpay
  alias Posbd.Repo
  alias Posbd.Accounts.Scope
  alias Posbd.Businesses.Business

  alias Posbd.Subscriptions.{
    Lifecycle,
    Subscription,
    SubscriptionPayment,
    SubscriptionPlan,
    SubscriptionWebhookEvent
  }

  ## Plans

  @doc "Lists active plans in display order. `include_inactive?` is for the platform admin dashboard."
  def list_plans(include_inactive? \\ false) do
    SubscriptionPlan
    |> maybe_active_only(include_inactive?)
    |> order_by([p], asc: p.position, asc: p.inserted_at)
    |> Repo.all()
  end

  defp maybe_active_only(query, true), do: query
  defp maybe_active_only(query, false), do: where(query, [p], p.is_active)

  def get_plan(id), do: Repo.get(SubscriptionPlan, id)

  def create_plan(attrs) do
    %SubscriptionPlan{}
    |> SubscriptionPlan.changeset(attrs)
    |> Repo.insert()
  end

  def update_plan(%SubscriptionPlan{} = plan, attrs) do
    plan
    |> SubscriptionPlan.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  True if `business` currently has access to `feature_key`. A business
  still inside its trial gets every feature (no plan is chosen yet, and
  the point of a trial is to evaluate the full product); once the trial
  ends, access follows whatever the chosen plan grants.
  """
  def has_feature?(%Business{} = business, feature_key) do
    case get_subscription(business) do
      nil ->
        false

      sub ->
        case Lifecycle.effective_status(sub) do
          status when status in [:trialing, :trial_ending_soon] ->
            true

          status ->
            Lifecycle.entitled?(status) and SubscriptionPlan.has_feature?(sub.plan, feature_key)
        end
    end
  end

  ## Trial + subscription lifecycle

  @doc """
  Starts the free trial for a newly-registered business (Phase 2 §4).
  Idempotent - if the business somehow already has a subscription record,
  that one is returned unchanged rather than creating a second one.
  """
  def start_trial(%Business{} = business) do
    case get_subscription(business) do
      nil ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)
        ends_at = DateTime.add(now, trial_period_days() * 86_400, :second)

        %Subscription{}
        |> Subscription.changeset(%{
          business_id: business.id,
          status: "trialing",
          trial_started_at: now,
          trial_ends_at: ends_at
        })
        |> Repo.insert()

      %Subscription{} = existing ->
        {:ok, existing}
    end
  end

  def trial_period_days do
    Application.get_env(:posbd, :subscriptions, [])
    |> Keyword.get(:trial_period_days, 30)
  end

  @doc "The business's subscription record with its plan preloaded, or `nil` if trial hasn't been started (shouldn't normally happen post-registration)."
  def get_subscription(%Business{} = business) do
    Subscription
    |> Repo.get_by(business_id: business.id)
    |> Repo.preload(:plan)
  end

  @doc """
  A frontend-ready summary of the scope's business subscription: effective
  status, whether the business is currently entitled to use the app, days
  remaining on the trial/current period, and the plan.
  """
  def status_summary(%Scope{business: business}), do: status_summary(business)

  def status_summary(%Business{} = business) do
    case get_subscription(business) do
      nil ->
        %{
          status: :subscription_required,
          entitled: false,
          trial_ends_at: nil,
          days_remaining: nil,
          plan: nil
        }

      sub ->
        now = DateTime.utc_now()
        status = Lifecycle.effective_status(sub, now)

        relevant_deadline =
          case status do
            s when s in [:trialing, :trial_ending_soon] -> sub.trial_ends_at
            s when s in [:active, :renewal_due] -> sub.current_period_end
            :grace_period -> sub.grace_period_ends_at
            _ -> nil
          end

        %{
          status: status,
          entitled: Lifecycle.entitled?(status),
          trial_ends_at: sub.trial_ends_at,
          days_remaining: Lifecycle.days_remaining(relevant_deadline, now),
          plan: sub.plan
        }
    end
  end

  @doc """
  Platform-admin action: activates (or changes to) a plan for a business
  and records the payment that funded it (Phase 2 §12). This is the
  manual stand-in for automated checkout until a payment provider is
  wired up (see `record_webhook_payment/1` for that path) - it can only
  be called with an authenticated `%PlatformAdmin{}`, never from a
  business's own request, so a business can never grant itself access.
  """
  def activate_plan(%Business{} = business, %SubscriptionPlan{} = plan, payment_attrs, admin) do
    Repo.transact(fn ->
      with {:ok, sub, now, period_end} <- activate_subscription_period(business, plan),
           {:ok, payment} <-
             %SubscriptionPayment{}
             |> SubscriptionPayment.changeset(%{
               business_id: business.id,
               subscription_id: sub.id,
               plan_id: plan.id,
               plan_name_snapshot: plan.name,
               amount: plan.price,
               currency: plan.currency,
               period_start: now,
               period_end: period_end,
               status: "paid",
               payment_provider: payment_attrs[:payment_provider] || "manual",
               provider_reference: payment_attrs[:provider_reference],
               notes: payment_attrs[:notes],
               paid_at: now,
               recorded_by_id: admin.id
             })
             |> Repo.insert() do
        {:ok, %{subscription: sub, payment: payment}}
      end
    end)
  end

  # Shared by the admin's manual `activate_plan/4` and the self-service
  # Razorpay checkout below - both end with the same "start a new paid
  # period on this plan" state change, just funded through a different
  # payment record (Phase 2 §52 - don't duplicate business logic).
  defp activate_subscription_period(business, plan) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    period_days = if plan.billing_period == "monthly", do: 30, else: 365
    period_end = DateTime.add(now, period_days * 86_400, :second)
    sub = get_subscription(business) || %Subscription{business_id: business.id}

    with {:ok, sub} <-
           sub
           |> Subscription.changeset(%{
             business_id: business.id,
             plan_id: plan.id,
             status: "active",
             current_period_start: now,
             current_period_end: period_end,
             cancel_at: nil,
             cancelled_at: nil,
             grace_period_ends_at: nil
           })
           |> Repo.insert_or_update() do
      {:ok, Repo.preload(sub, :plan), now, period_end}
    end
  end

  @doc "Cancels a business's subscription immediately (platform admin action)."
  def cancel_subscription(%Business{} = business) do
    case get_subscription(business) do
      nil ->
        {:error, %{message: "This business has no subscription"}}

      sub ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        sub
        |> Subscription.changeset(%{status: "cancelled", cancelled_at: now})
        |> Repo.update()
    end
  end

  ## Self-service checkout (Phase 2 §10) - Razorpay

  @doc """
  Checkout step 1: creates a Razorpay Order and a matching `pending`
  payment record, and returns what the frontend needs to open Razorpay
  Checkout. Never returns the key secret - only the public key id.
  """
  def create_checkout_order(%Scope{business: business}, %SubscriptionPlan{} = plan) do
    payment_id = Ecto.UUID.generate()

    with {:ok, order_id} <- Razorpay.create_order(plan.price, plan.currency, payment_id),
         {:ok, payment} <-
           %SubscriptionPayment{id: payment_id}
           |> SubscriptionPayment.changeset(%{
             business_id: business.id,
             plan_id: plan.id,
             plan_name_snapshot: plan.name,
             amount: plan.price,
             currency: plan.currency,
             status: "pending",
             payment_provider: "razorpay",
             provider_order_id: order_id
           })
           |> Repo.insert() do
      {:ok,
       %{
         payment_id: payment.id,
         order_id: order_id,
         key_id: Razorpay.key_id(),
         amount: plan.price,
         currency: plan.currency
       }}
    end
  end

  @doc """
  Checkout step 2: verifies the Razorpay Checkout signature (Phase 2 §10
  - the frontend's "payment succeeded" callback is never trusted on its
  own) and, if valid, marks the payment paid and activates the
  subscription for one billing period.
  """
  def verify_and_activate_checkout(%Scope{business: business}, order_id, payment_id, signature) do
    with true <- Razorpay.verify_payment_signature(order_id, payment_id, signature),
         %SubscriptionPayment{status: "pending"} = payment <-
           Repo.get_by(SubscriptionPayment, business_id: business.id, provider_order_id: order_id)
           |> maybe_preload_plan(),
         %SubscriptionPlan{} = plan <- payment.plan do
      complete_checkout_payment(business, payment, plan, payment_id)
    else
      false -> {:error, %{message: "Payment verification failed"}}
      nil -> {:error, %{message: "No matching pending payment for this order"}}
      %SubscriptionPayment{} -> {:error, %{message: "This payment has already been processed"}}
      error -> error
    end
  end

  defp maybe_preload_plan(nil), do: nil
  defp maybe_preload_plan(payment), do: Repo.preload(payment, :plan)

  defp complete_checkout_payment(business, payment, plan, provider_payment_id) do
    Repo.transact(fn ->
      with {:ok, sub, now, period_end} <- activate_subscription_period(business, plan),
           {:ok, payment} <-
             payment
             |> SubscriptionPayment.changeset(%{
               subscription_id: sub.id,
               status: "paid",
               provider_payment_id: provider_payment_id,
               period_start: now,
               period_end: period_end,
               paid_at: now
             })
             |> Repo.update() do
        {:ok, %{subscription: sub, payment: payment}}
      end
    end)
  end

  @doc """
  Processes one Razorpay webhook delivery (Phase 2 §11). The unique index
  on `{provider, provider_event_id}` makes this idempotent - a retried
  delivery for an event already recorded is a no-op, never a second
  activation. This is the durable backstop for checkout: it activates a
  subscription even if the customer closed their browser right after
  paying, before the checkout redirect could complete.
  """
  def process_webhook_event(event_type, event_id, payload) do
    %SubscriptionWebhookEvent{}
    |> SubscriptionWebhookEvent.changeset(%{
      provider: "razorpay",
      event_type: event_type,
      provider_event_id: event_id,
      payload: payload
    })
    |> Repo.insert()
    |> case do
      {:ok, event} -> handle_webhook_event(event)
      {:error, %Ecto.Changeset{errors: errors}} -> handle_duplicate_event(errors)
    end
  end

  defp handle_duplicate_event(errors) do
    if Keyword.has_key?(errors, :provider_event_id),
      do: :ok,
      else: {:error, %{message: "Could not record webhook event"}}
  end

  defp handle_webhook_event(%SubscriptionWebhookEvent{event_type: "payment.captured"} = event) do
    with {:ok, order_id, provider_payment_id} <- extract_payment_ids(event.payload),
         %SubscriptionPayment{status: "pending"} = payment <-
           Repo.get_by(SubscriptionPayment, provider_order_id: order_id)
           |> maybe_preload(:plan)
           |> maybe_preload(:business) do
      complete_checkout_payment(payment.business, payment, payment.plan, provider_payment_id)
      mark_webhook(event, "processed")
    else
      _ -> mark_webhook(event, "ignored")
    end
  end

  defp handle_webhook_event(%SubscriptionWebhookEvent{event_type: "payment.failed"} = event) do
    with {:ok, order_id, _provider_payment_id} <- extract_payment_ids(event.payload),
         %SubscriptionPayment{} = payment <-
           Repo.get_by(SubscriptionPayment, provider_order_id: order_id) do
      payment |> SubscriptionPayment.changeset(%{status: "failed"}) |> Repo.update()
      mark_webhook(event, "processed")
    else
      _ -> mark_webhook(event, "ignored")
    end
  end

  defp handle_webhook_event(event), do: mark_webhook(event, "ignored")

  defp extract_payment_ids(%{
         "payload" => %{"payment" => %{"entity" => %{"order_id" => order_id, "id" => payment_id}}}
       }),
       do: {:ok, order_id, payment_id}

  defp extract_payment_ids(_), do: :error

  defp maybe_preload(nil, _assoc), do: nil
  defp maybe_preload(record, assoc), do: Repo.preload(record, assoc)

  defp mark_webhook(event, status) do
    event
    |> SubscriptionWebhookEvent.changeset(%{
      status: status,
      processed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.update()

    :ok
  end

  @doc "Payment history for a business, newest first (Phase 2 §12 - businesses can view their own subscription/payment history)."
  def list_payments(%Business{} = business) do
    SubscriptionPayment
    |> where([p], p.business_id == ^business.id)
    |> order_by([p], desc: p.inserted_at)
    |> Repo.all()
  end

  ## Platform admin dashboard (Phase 2 §13)

  @doc "Counts of businesses by effective subscription status, for the admin summary dashboard."
  def dashboard_counts do
    now = DateTime.utc_now()

    Subscription
    |> Repo.all()
    |> Enum.frequencies_by(&Lifecycle.effective_status(&1, now))
  end

  @doc "Businesses with their effective status, newest first, optionally filtered to one status."
  def list_businesses_with_status(status_filter \\ nil) do
    now = DateTime.utc_now()

    Subscription
    |> preload([:business, :plan])
    |> order_by([s], desc: s.inserted_at)
    |> Repo.all()
    |> Enum.map(fn sub -> {sub, Lifecycle.effective_status(sub, now)} end)
    |> then(fn rows ->
      if status_filter,
        do: Enum.filter(rows, fn {_, s} -> to_string(s) == status_filter end),
        else: rows
    end)
  end
end
