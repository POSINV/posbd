defmodule PosbdWeb.SecurityTest do
  @moduledoc """
  Regression tests for the security review: tenant isolation, role
  checks, plan/trial/payment bypasses and webhook forgery. Each test
  reproduces an attack that used to work.
  """

  # Some tests flip global application env (webhook secret), so this
  # module can't run alongside async tests.
  use PosbdWeb.ConnCase, async: false

  import Posbd.DataCase, only: [errors_on: 1]
  import Posbd.BusinessesFixtures
  import Posbd.CustomersFixtures
  import Posbd.ProductsFixtures
  import Posbd.SubscriptionsFixtures

  alias Posbd.{Billing, Businesses, Products, Repo, Subscriptions}
  alias Posbd.Businesses.{Membership, Roles}
  alias Posbd.Subscriptions.SubscriptionPayment

  defp member_conn(scope, role) do
    user = Posbd.AccountsFixtures.user_fixture()

    {:ok, _} =
      %Membership{}
      |> Membership.owner_changeset(scope.business.id, user.id)
      |> Ecto.Changeset.change(role: role, permissions: Roles.default_permissions_for(role))
      |> Repo.insert()

    token = Posbd.Accounts.create_api_token(user)

    build_conn()
    |> put_req_header("authorization", "Bearer #{token}")
    |> put_req_header("x-business-id", scope.business.id)
  end

  defp hmac(secret, data),
    do: :crypto.mac(:hmac, :sha256, secret, data) |> Base.encode16(case: :lower)

  defp stub_razorpay_order(order_id) do
    Req.Test.stub(Posbd.Payments.Razorpay, fn conn -> Req.Test.json(conn, %{"id" => order_id}) end)
  end

  defp captured_body(order_id, payment_id, amount) do
    %{
      "event" => "payment.captured",
      "payload" => %{
        "payment" => %{
          "entity" => %{
            "id" => payment_id,
            "order_id" => order_id,
            "amount" => amount,
            "currency" => "INR"
          }
        }
      }
    }
  end

  defp post_razorpay_webhook(body, signature) do
    build_conn()
    |> put_req_header("content-type", "application/json")
    |> put_req_header("x-razorpay-signature", signature)
    |> post(~p"/api/v1/webhooks/razorpay", Jason.encode!(body))
  end

  describe "payment gateway" do
    test "a webhook signed with an empty key is rejected when the webhook secret is unset" do
      original = Application.get_env(:posbd, :razorpay)
      Application.put_env(:posbd, :razorpay, Keyword.put(original, :webhook_secret, nil))
      on_exit(fn -> Application.put_env(:posbd, :razorpay, original) end)

      scope = full_scope_fixture()
      plan = plan_fixture()
      stub_razorpay_order("order_forged")
      {:ok, _} = Subscriptions.create_checkout_order(scope, plan)

      body = captured_body("order_forged", "pay_forged", 99_900)
      conn = post_razorpay_webhook(body, hmac("", Jason.encode!(body)))

      assert json_response(conn, 401)

      assert Repo.get_by!(SubscriptionPayment, provider_order_id: "order_forged").status ==
               "pending"
    end

    test "a captured webhook whose amount doesn't match the order doesn't activate anything" do
      scope = full_scope_fixture()
      plan = plan_fixture()
      stub_razorpay_order("order_short")
      {:ok, _} = Subscriptions.create_checkout_order(scope, plan)

      assert :ok =
               Subscriptions.process_webhook_event(
                 "payment.captured",
                 "evt_short",
                 captured_body("order_short", "pay_short", 100)
               )

      assert Repo.get_by!(SubscriptionPayment, provider_order_id: "order_short").status ==
               "pending"
    end

    test "an inactive plan can't be bought through checkout", %{conn: _conn} do
      scope = full_scope_fixture()
      plan = plan_fixture(%{is_active: false})

      conn = post(authed_conn(scope), ~p"/api/v1/subscription/checkout", %{plan_id: plan.id})

      assert json_response(conn, 422)["error"]["message"] == "Unknown plan"
      refute Repo.get_by(SubscriptionPayment, business_id: scope.business.id)
    end

    test "a payment already activated by the webhook can't be activated again by verify" do
      scope = full_scope_fixture()
      plan = plan_fixture()
      stub_razorpay_order("order_race")
      {:ok, _} = Subscriptions.create_checkout_order(scope, plan)

      assert :ok =
               Subscriptions.process_webhook_event(
                 "payment.captured",
                 "evt_race",
                 captured_body("order_race", "pay_race", 99_900)
               )

      signature = hmac("fake_key_secret", "order_race|pay_race")

      assert {:error, %{message: "This payment has already been processed"}} =
               Subscriptions.verify_and_activate_checkout(
                 scope,
                 "order_race",
                 "pay_race",
                 signature
               )
    end
  end

  describe "subscription bypass" do
    test "only a user's first business gets a free trial" do
      scope = full_scope_fixture()
      second = business_fixture(Posbd.Accounts.Scope.for_user(scope.user))

      assert Subscriptions.status_summary(scope.business).entitled
      refute Subscriptions.status_summary(second).entitled
    end

    test "a paid period that lapsed past the grace period blocks access" do
      scope = full_scope_fixture()
      plan = plan_fixture()
      admin = platform_admin_fixture()
      {:ok, %{subscription: sub}} = Subscriptions.activate_plan(scope.business, plan, %{}, admin)

      long_ago = DateTime.utc_now() |> DateTime.add(-30, :day) |> DateTime.truncate(:second)
      sub |> Ecto.Changeset.change(current_period_end: long_ago) |> Repo.update!()

      refute Subscriptions.status_summary(scope.business).entitled
      assert json_response(get(authed_conn(scope), ~p"/api/v1/products"), 402)
    end

    test "a plan without the offers/migration features can't use those APIs" do
      scope = full_scope_fixture()
      plan = plan_fixture(%{features: %{}})
      admin = platform_admin_fixture()
      {:ok, _} = Subscriptions.activate_plan(scope.business, plan, %{}, admin)

      offer = %{
        "name" => "Sneaky",
        "code" => "FREE50",
        "discount_type" => "percentage",
        "discount_value" => "50"
      }

      assert json_response(post(authed_conn(scope), ~p"/api/v1/offers", offer: offer), 403)

      assert json_response(
               post(authed_conn(scope), ~p"/api/v1/imports/products/commit", rows: []),
               403
             )
    end
  end

  describe "tenant isolation" do
    test "an invoice can't reference another business's customer" do
      scope = full_scope_fixture()
      other = full_scope_fixture()
      victim = customer_fixture(other)
      product = product_fixture(scope)

      assert {:error, %{message: "Customer not found"}} =
               Billing.create_invoice(scope, %{
                 "customer_id" => victim.id,
                 "items" => [%{"product_id" => product.id, "quantity" => 1}]
               })
    end

    test "a product can't be put in another business's category" do
      scope = full_scope_fixture()
      other = full_scope_fixture()
      foreign_category = category_fixture(other)

      assert {:error, changeset} =
               Products.create_product(
                 scope,
                 valid_product_attrs(%{category_id: foreign_category.id})
               )

      assert %{category_id: ["does not exist"]} = errors_on(changeset)
    end

    test "a category can't be nested under another business's category" do
      scope = full_scope_fixture()
      other = full_scope_fixture()
      foreign_parent = category_fixture(other)

      assert {:error, changeset} =
               Posbd.Categories.create_category(scope, %{
                 "name" => "Sneaky",
                 "parent_id" => foreign_parent.id
               })

      assert %{parent_id: ["does not exist"]} = errors_on(changeset)
    end
  end

  describe "role checks" do
    test "inventory staff can't read customer personal data" do
      scope = full_scope_fixture()
      customer = customer_fixture(scope)
      conn = member_conn(scope, "inventory_staff")

      assert json_response(get(conn, ~p"/api/v1/customers"), 403)
      assert json_response(get(conn, ~p"/api/v1/customers/#{customer.id}"), 403)
      assert json_response(get(conn, ~p"/api/v1/customers/#{customer.id}/summary"), 403)
    end

    test "a cashier can still look up customers for billing" do
      scope = full_scope_fixture()
      customer_fixture(scope)

      assert json_response(get(member_conn(scope, "cashier"), ~p"/api/v1/customers"), 200)
    end

    test "only settings managers can complete onboarding" do
      scope = full_scope_fixture()
      conn = member_conn(scope, "cashier")

      assert json_response(
               post(conn, ~p"/api/v1/businesses/#{scope.business.id}/complete_onboarding"),
               403
             )

      refute Businesses.get_business(scope.business.id).onboarding_completed_at
    end
  end

  describe "login brute force" do
    test "repeated failed logins for one email are throttled" do
      user = Posbd.AccountsFixtures.user_fixture()

      for _ <- 1..10 do
        conn = post(build_conn(), ~p"/api/v1/auth/login", email: user.email, password: "wrong")
        assert json_response(conn, 401)
      end

      conn =
        post(build_conn(), ~p"/api/v1/auth/login",
          email: user.email,
          password: Posbd.AccountsFixtures.valid_user_password()
        )

      assert json_response(conn, 429)
      assert get_resp_header(conn, "retry-after") != []
    end

    test "a non-string email is rejected instead of crashing" do
      conn = post(build_conn(), ~p"/api/v1/auth/login", email: ["a"], password: "x")
      assert json_response(conn, 401)
    end
  end
end
