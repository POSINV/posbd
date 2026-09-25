defmodule PosbdWeb.Api.SubscriptionControllerTest do
  use PosbdWeb.ConnCase, async: true

  alias Posbd.Repo
  alias Posbd.Subscriptions.Subscription

  import Posbd.BusinessesFixtures
  import Posbd.SubscriptionsFixtures

  defp hmac(secret, data),
    do: :crypto.mac(:hmac, :sha256, secret, data) |> Base.encode16(case: :lower)

  setup do
    %{scope: full_scope_fixture()}
  end

  test "GET /subscription_plans is public and needs no auth" do
    conn = get(build_conn(), ~p"/api/v1/subscription_plans")
    assert %{"data" => plans} = json_response(conn, 200)
    assert is_list(plans)
  end

  test "GET /subscription returns the trial status and available plans", %{scope: scope} do
    conn = get(authed_conn(scope), ~p"/api/v1/subscription")

    assert %{"data" => %{"status" => "trialing", "entitled" => true, "plans" => plans}} =
             json_response(conn, 200)

    assert is_list(plans)
  end

  test "GET /subscription/payments starts empty", %{scope: scope} do
    conn = get(authed_conn(scope), ~p"/api/v1/subscription/payments")
    assert %{"data" => []} = json_response(conn, 200)
  end

  test "a gated endpoint is blocked once the trial has expired, but /subscription itself still works",
       %{
         scope: scope
       } do
    sub = Repo.get_by!(Subscription, business_id: scope.business.id)

    sub
    |> Ecto.Changeset.change(
      trial_ends_at: DateTime.utc_now() |> DateTime.add(-1, :day) |> DateTime.truncate(:second)
    )
    |> Repo.update!()

    conn = get(authed_conn(scope), ~p"/api/v1/products")
    assert %{"error" => %{"subscription_status" => "trial_expired"}} = json_response(conn, 402)

    conn2 = get(authed_conn(scope), ~p"/api/v1/subscription")

    assert %{"data" => %{"status" => "trial_expired", "entitled" => false}} =
             json_response(conn2, 200)
  end

  test "checkout: create + verify activates the subscription", %{scope: scope} do
    plan = plan_fixture(price: "999.00", currency: "INR")

    Req.Test.stub(Posbd.Payments.Razorpay, fn conn ->
      Req.Test.json(conn, %{"id" => "order_ctrl1"})
    end)

    checkout_conn =
      post(authed_conn(scope), ~p"/api/v1/subscription/checkout", %{"plan_id" => plan.id})

    assert %{"data" => %{"order_id" => "order_ctrl1", "key_id" => "rzp_test_fake_key"}} =
             json_response(checkout_conn, 200)

    signature = hmac("fake_key_secret", "order_ctrl1|pay_ctrl1")

    verify_conn =
      post(authed_conn(scope), ~p"/api/v1/subscription/checkout/verify", %{
        "razorpay_order_id" => "order_ctrl1",
        "razorpay_payment_id" => "pay_ctrl1",
        "razorpay_signature" => signature
      })

    assert %{"data" => %{"status" => "active", "payment" => %{"status" => "paid"}}} =
             json_response(verify_conn, 200)
  end

  test "checkout verify rejects a forged signature", %{scope: scope} do
    plan = plan_fixture()

    Req.Test.stub(Posbd.Payments.Razorpay, fn conn ->
      Req.Test.json(conn, %{"id" => "order_ctrl2"})
    end)

    post(authed_conn(scope), ~p"/api/v1/subscription/checkout", %{"plan_id" => plan.id})

    verify_conn =
      post(authed_conn(scope), ~p"/api/v1/subscription/checkout/verify", %{
        "razorpay_order_id" => "order_ctrl2",
        "razorpay_payment_id" => "pay_ctrl2",
        "razorpay_signature" => "forged"
      })

    assert json_response(verify_conn, 422)
  end

  test "a cashier cannot start checkout for the business" do
    scope = full_scope_fixture()
    plan = plan_fixture()

    user = Posbd.AccountsFixtures.user_fixture()
    token = Posbd.Accounts.create_api_token(user)

    {:ok, _} =
      %Posbd.Businesses.Membership{}
      |> Posbd.Businesses.Membership.owner_changeset(scope.business.id, user.id)
      |> Ecto.Changeset.change(
        role: "cashier",
        permissions: Posbd.Businesses.Roles.default_permissions_for("cashier")
      )
      |> Posbd.Repo.insert()

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> put_req_header("x-business-id", scope.business.id)
      |> post(~p"/api/v1/subscription/checkout", %{"plan_id" => plan.id})

    assert json_response(conn, 403)
  end
end
