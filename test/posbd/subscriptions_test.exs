defmodule Posbd.SubscriptionsTest do
  use Posbd.DataCase, async: true

  alias Posbd.{Repo, Subscriptions}
  alias Posbd.Subscriptions.{Lifecycle, Subscription}

  import Posbd.BusinessesFixtures
  import Posbd.SubscriptionsFixtures

  describe "Lifecycle.effective_status/2" do
    setup do
      %{now: ~U[2026-06-15 00:00:00Z]}
    end

    test "trialing: far out, ending soon, and expired", %{now: now} do
      far = %Subscription{status: "trialing", trial_ends_at: DateTime.add(now, 20, :day)}
      soon = %Subscription{status: "trialing", trial_ends_at: DateTime.add(now, 3, :day)}
      expired = %Subscription{status: "trialing", trial_ends_at: DateTime.add(now, -1, :day)}

      assert Lifecycle.effective_status(far, now) == :trialing
      assert Lifecycle.effective_status(soon, now) == :trial_ending_soon
      assert Lifecycle.effective_status(expired, now) == :trial_expired
    end

    test "active: far out, renewal due soon, and overdue", %{now: now} do
      far = %Subscription{status: "active", current_period_end: DateTime.add(now, 200, :day)}
      soon = %Subscription{status: "active", current_period_end: DateTime.add(now, 5, :day)}
      overdue = %Subscription{status: "active", current_period_end: DateTime.add(now, -1, :day)}

      assert Lifecycle.effective_status(far, now) == :active
      assert Lifecycle.effective_status(soon, now) == :renewal_due
      assert Lifecycle.effective_status(overdue, now) == :renewal_due
    end

    test "grace_period escalates to suspended once its deadline passes", %{now: now} do
      in_grace = %Subscription{
        status: "grace_period",
        grace_period_ends_at: DateTime.add(now, 2, :day)
      }

      past_grace = %Subscription{
        status: "grace_period",
        grace_period_ends_at: DateTime.add(now, -1, :day)
      }

      assert Lifecycle.effective_status(in_grace, now) == :grace_period
      assert Lifecycle.effective_status(past_grace, now) == :suspended
    end

    test "past_due, suspended, and cancelled pass through directly", %{now: now} do
      assert Lifecycle.effective_status(%Subscription{status: "past_due"}, now) == :past_due
      assert Lifecycle.effective_status(%Subscription{status: "suspended"}, now) == :suspended
      assert Lifecycle.effective_status(%Subscription{status: "cancelled"}, now) == :cancelled
    end
  end

  describe "Lifecycle.entitled?/1" do
    test "only trial_expired, suspended, and cancelled block access" do
      refute Lifecycle.entitled?(:trial_expired)
      refute Lifecycle.entitled?(:suspended)
      refute Lifecycle.entitled?(:cancelled)

      for status <- [
            :trialing,
            :trial_ending_soon,
            :active,
            :renewal_due,
            :past_due,
            :grace_period
          ] do
        assert Lifecycle.entitled?(status)
      end
    end
  end

  describe "start_trial/1" do
    test "a new business automatically gets a ~30 day trial" do
      scope = full_scope_fixture()
      sub = Subscriptions.get_subscription(scope.business)

      assert sub.status == "trialing"
      assert sub.trial_started_at
      assert sub.trial_ends_at

      days = DateTime.diff(sub.trial_ends_at, sub.trial_started_at, :day)
      assert days == Subscriptions.trial_period_days()
    end

    test "is idempotent - calling it again does not create a second row" do
      scope = full_scope_fixture()
      first = Subscriptions.get_subscription(scope.business)

      assert {:ok, second} = Subscriptions.start_trial(scope.business)
      assert second.id == first.id
      assert Repo.aggregate(Subscription, :count) == 1
    end
  end

  describe "status_summary/1" do
    test "a fresh trial is entitled with ~30 days remaining" do
      scope = full_scope_fixture()
      summary = Subscriptions.status_summary(scope)

      assert summary.status == :trialing
      assert summary.entitled

      assert summary.days_remaining in (Subscriptions.trial_period_days() - 1)..Subscriptions.trial_period_days()

      assert summary.plan == nil
    end

    test "a business with no subscription row is subscription_required" do
      scope = full_scope_fixture()
      Repo.delete_all(Subscription)

      summary = Subscriptions.status_summary(scope)
      assert summary.status == :subscription_required
      refute summary.entitled
    end
  end

  describe "has_feature?/2" do
    test "a trialing business gets every feature, even one no plan grants" do
      scope = full_scope_fixture()
      assert Subscriptions.has_feature?(scope.business, "whatsapp")
    end

    test "after activation, access follows the plan's own feature map" do
      scope = full_scope_fixture()
      admin = platform_admin_fixture()
      plan = plan_fixture(features: %{"loyalty" => true})

      {:ok, _} = Subscriptions.activate_plan(scope.business, plan, %{}, admin)

      assert Subscriptions.has_feature?(scope.business, "loyalty")
      refute Subscriptions.has_feature?(scope.business, "whatsapp")
    end

    test "a business with no subscription at all has no features" do
      scope = full_scope_fixture()
      Repo.delete_all(Subscription)

      refute Subscriptions.has_feature?(scope.business, "loyalty")
    end
  end

  describe "activate_plan/4" do
    test "upgrades the same subscription row and records a paid payment", %{} do
      scope = full_scope_fixture()
      admin = platform_admin_fixture()
      plan = plan_fixture(price: "1499.00", billing_period: "monthly")

      assert {:ok, %{subscription: sub, payment: payment}} =
               Subscriptions.activate_plan(
                 scope.business,
                 plan,
                 %{payment_provider: "manual", provider_reference: "REF-1"},
                 admin
               )

      assert sub.status == "active"
      assert sub.plan.id == plan.id
      assert Repo.aggregate(Subscription, :count) == 1

      assert payment.status == "paid"
      assert payment.recorded_by_id == admin.id
      assert Decimal.equal?(payment.amount, Decimal.new("1499.00"))
      assert payment.plan_name_snapshot == plan.name

      assert Lifecycle.effective_status(sub) == :active
    end
  end

  describe "cancel_subscription/1" do
    test "marks the subscription cancelled" do
      scope = full_scope_fixture()
      assert {:ok, cancelled} = Subscriptions.cancel_subscription(scope.business)
      assert cancelled.status == "cancelled"
      assert cancelled.cancelled_at
      refute Lifecycle.entitled?(Lifecycle.effective_status(cancelled))
    end

    test "errors clearly when the business has no subscription" do
      scope = full_scope_fixture()
      Repo.delete_all(Subscription)

      assert {:error, %{message: _}} = Subscriptions.cancel_subscription(scope.business)
    end
  end

  describe "dashboard_counts/0 and list_businesses_with_status/1" do
    test "counts and lists businesses by their effective status" do
      trial_scope = full_scope_fixture()
      admin = platform_admin_fixture()
      plan = plan_fixture()
      active_scope = full_scope_fixture()
      {:ok, _} = Subscriptions.activate_plan(active_scope.business, plan, %{}, admin)

      counts = Subscriptions.dashboard_counts()
      assert counts[:trialing] == 1
      assert counts[:active] == 1

      active_rows = Subscriptions.list_businesses_with_status("active")
      assert [{sub, :active}] = active_rows
      assert sub.business_id == active_scope.business.id
      assert sub.business.id == active_scope.business.id

      assert {_trial_sub, :trialing} =
               Enum.find(Subscriptions.list_businesses_with_status(), fn {sub, _} ->
                 sub.business_id == trial_scope.business.id
               end)
    end
  end

  describe "create_checkout_order/2 and verify_and_activate_checkout/4" do
    defp hmac(secret, data),
      do: :crypto.mac(:hmac, :sha256, secret, data) |> Base.encode16(case: :lower)

    test "the full happy path activates the subscription" do
      scope = full_scope_fixture()
      plan = plan_fixture(price: "999.00", currency: "INR")

      Req.Test.stub(Posbd.Payments.Razorpay, fn conn ->
        Req.Test.json(conn, %{"id" => "order_happy"})
      end)

      assert {:ok, checkout} = Subscriptions.create_checkout_order(scope, plan)
      assert checkout.order_id == "order_happy"
      assert checkout.key_id == "rzp_test_fake_key"
      assert Decimal.equal?(checkout.amount, Decimal.new("999.00"))

      signature = hmac("fake_key_secret", "order_happy|pay_happy")

      assert {:ok, %{subscription: sub, payment: payment}} =
               Subscriptions.verify_and_activate_checkout(
                 scope,
                 "order_happy",
                 "pay_happy",
                 signature
               )

      assert sub.status == "active"
      assert sub.plan.id == plan.id
      assert payment.status == "paid"
      assert payment.provider_payment_id == "pay_happy"
    end

    test "an invalid signature is rejected and never activates anything" do
      scope = full_scope_fixture()
      plan = plan_fixture()

      Req.Test.stub(Posbd.Payments.Razorpay, fn conn ->
        Req.Test.json(conn, %{"id" => "order_bad"})
      end)

      {:ok, _} = Subscriptions.create_checkout_order(scope, plan)

      assert {:error, %{message: _}} =
               Subscriptions.verify_and_activate_checkout(
                 scope,
                 "order_bad",
                 "pay_bad",
                 "not-a-real-signature"
               )

      summary = Subscriptions.status_summary(scope)
      assert summary.status == :trialing
    end

    test "an unknown order_id is rejected", %{} do
      scope = full_scope_fixture()
      signature = hmac("fake_key_secret", "unknown-order|pay_x")

      assert {:error, %{message: _}} =
               Subscriptions.verify_and_activate_checkout(
                 scope,
                 "unknown-order",
                 "pay_x",
                 signature
               )
    end
  end

  describe "process_webhook_event/3" do
    defp captured_payload(order_id, payment_id) do
      %{
        "event" => "payment.captured",
        "payload" => %{"payment" => %{"entity" => %{"id" => payment_id, "order_id" => order_id}}}
      }
    end

    test "payment.captured activates the matching pending payment" do
      scope = full_scope_fixture()
      plan = plan_fixture()

      Req.Test.stub(Posbd.Payments.Razorpay, fn conn ->
        Req.Test.json(conn, %{"id" => "order_wh1"})
      end)

      {:ok, _} = Subscriptions.create_checkout_order(scope, plan)

      assert :ok =
               Subscriptions.process_webhook_event(
                 "payment.captured",
                 "evt_1",
                 captured_payload("order_wh1", "pay_wh1")
               )

      summary = Subscriptions.status_summary(scope)
      assert summary.status == :active
    end

    test "the same event id is never processed twice" do
      scope = full_scope_fixture()
      plan = plan_fixture()

      Req.Test.stub(Posbd.Payments.Razorpay, fn conn ->
        Req.Test.json(conn, %{"id" => "order_wh2"})
      end)

      {:ok, _} = Subscriptions.create_checkout_order(scope, plan)

      payload = captured_payload("order_wh2", "pay_wh2")
      assert :ok = Subscriptions.process_webhook_event("payment.captured", "evt_dup", payload)
      assert :ok = Subscriptions.process_webhook_event("payment.captured", "evt_dup", payload)

      assert Repo.aggregate(Posbd.Subscriptions.SubscriptionWebhookEvent, :count) == 1
    end

    test "payment.failed marks the payment failed without activating anything" do
      scope = full_scope_fixture()
      plan = plan_fixture()

      Req.Test.stub(Posbd.Payments.Razorpay, fn conn ->
        Req.Test.json(conn, %{"id" => "order_wh3"})
      end)

      {:ok, _} = Subscriptions.create_checkout_order(scope, plan)

      failed_payload = %{
        "event" => "payment.failed",
        "payload" => %{
          "payment" => %{"entity" => %{"id" => "pay_wh3", "order_id" => "order_wh3"}}
        }
      }

      assert :ok =
               Subscriptions.process_webhook_event("payment.failed", "evt_fail", failed_payload)

      [payment] = Subscriptions.list_payments(scope.business)
      assert payment.status == "failed"
      assert Subscriptions.status_summary(scope).status == :trialing
    end
  end
end
