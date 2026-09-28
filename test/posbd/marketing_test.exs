defmodule Posbd.MarketingTest do
  use Posbd.DataCase, async: true

  alias Posbd.{Billing, Loyalty, Marketing}
  alias Posbd.Whatsapp.WhatsappMessage

  import Posbd.BusinessesFixtures
  import Posbd.CustomersFixtures
  import Posbd.MarketingFixtures
  import Posbd.ProductsFixtures
  import Posbd.WhatsappFixtures

  setup do
    %{scope: full_scope_fixture()}
  end

  describe "create_offer/2" do
    test "normalizes the code to uppercase", %{scope: scope} do
      {:ok, offer} = Marketing.create_offer(scope, valid_offer_attrs(%{"code" => " save10 "}))
      assert offer.code == "SAVE10"
    end

    test "rejects a duplicate code for the same business, but allows two offers with no code", %{
      scope: scope
    } do
      {:ok, _} = Marketing.create_offer(scope, valid_offer_attrs(%{"code" => "SUMMER"}))

      assert {:error, changeset} =
               Marketing.create_offer(scope, valid_offer_attrs(%{"code" => "summer"}))

      assert "has already been taken" in errors_on(changeset).code

      assert {:ok, _} = Marketing.create_offer(scope, valid_offer_attrs())
      assert {:ok, _} = Marketing.create_offer(scope, valid_offer_attrs())
    end

    test "rejects a percentage discount over 100", %{scope: scope} do
      assert {:error, changeset} =
               Marketing.create_offer(scope, valid_offer_attrs(%{"discount_value" => "150"}))

      assert %{discount_value: ["must be less than or equal to 100"]} = errors_on(changeset)
    end
  end

  describe "resolve/4 with no code (automatic offers)" do
    test "no-op when nothing qualifies", %{scope: scope} do
      assert {:ok, %{offer: nil, discount_amount: amount}} =
               Marketing.resolve(scope.business, nil, nil, Decimal.new("500"))

      assert Decimal.equal?(amount, 0)
    end

    test "applies the single eligible automatic offer", %{scope: scope} do
      offer_fixture(scope, %{"discount_type" => "percentage", "discount_value" => "10"})

      assert {:ok, %{offer: offer, discount_amount: amount}} =
               Marketing.resolve(scope.business, nil, nil, Decimal.new("200"))

      assert offer
      assert Decimal.equal?(amount, Decimal.new("20.00"))
    end

    test "picks the larger discount when two automatic offers both qualify", %{scope: scope} do
      offer_fixture(scope, %{
        "name" => "Small",
        "discount_type" => "fixed_amount",
        "discount_value" => "10"
      })

      offer_fixture(scope, %{
        "name" => "Big",
        "discount_type" => "fixed_amount",
        "discount_value" => "50"
      })

      assert {:ok, %{offer: offer, discount_amount: amount}} =
               Marketing.resolve(scope.business, nil, nil, Decimal.new("200"))

      assert offer.name == "Big"
      assert Decimal.equal?(amount, Decimal.new("50"))
    end

    test "a coded offer is never applied automatically", %{scope: scope} do
      offer_fixture(scope, %{"code" => "VIP20"})

      assert {:ok, %{offer: nil}} =
               Marketing.resolve(scope.business, nil, nil, Decimal.new("500"))
    end
  end

  describe "resolve/4 with a code" do
    test "an unknown code is rejected", %{scope: scope} do
      assert {:error, %{message: message}} =
               Marketing.resolve(scope.business, nil, "NOPE", Decimal.new("100"))

      assert message =~ "not found"
    end

    test "a valid code applies", %{scope: scope} do
      offer_fixture(scope, %{
        "code" => "SAVE20",
        "discount_type" => "fixed_amount",
        "discount_value" => "20"
      })

      assert {:ok, %{offer: offer, discount_amount: amount}} =
               Marketing.resolve(scope.business, nil, "save20", Decimal.new("100"))

      assert offer.code == "SAVE20"
      assert Decimal.equal?(amount, Decimal.new("20"))
    end

    test "rejects a bill below the minimum purchase amount", %{scope: scope} do
      offer_fixture(scope, %{"code" => "BIG50", "min_purchase_amount" => "1000"})

      assert {:error, %{message: message}} =
               Marketing.resolve(scope.business, nil, "BIG50", Decimal.new("500"))

      assert message =~ "minimum purchase"
    end

    test "rejects an out-of-window offer", %{scope: scope} do
      past = DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.truncate(:second)
      offer_fixture(scope, %{"code" => "EXPIRED", "ends_at" => past})

      assert {:error, %{message: message}} =
               Marketing.resolve(scope.business, nil, "EXPIRED", Decimal.new("100"))

      assert message =~ "expired"
    end

    test "segment eligibility: a freshly-created customer qualifies for a 'new'-segment offer", %{
      scope: scope
    } do
      offer_fixture(scope, %{"code" => "WELCOME", "eligible_segment" => "new"})
      customer = customer_fixture(scope)

      assert {:ok, %{offer: offer}} =
               Marketing.resolve(scope.business, customer, "WELCOME", Decimal.new("100"))

      assert offer

      assert {:error, %{message: message}} =
               Marketing.resolve(scope.business, nil, "WELCOME", Decimal.new("100"))

      assert message =~ "new customers"
    end

    test "usage_limit_total stops further redemptions once reached", %{scope: scope} do
      offer = offer_fixture(scope, %{"code" => "LIMITED", "usage_limit_total" => 1})
      {:ok, _} = Marketing.record_redemption(scope.business, offer, nil, nil, Decimal.new("5"))

      assert {:error, %{message: message}} =
               Marketing.resolve(scope.business, nil, "LIMITED", Decimal.new("100"))

      assert message =~ "usage limit"
    end

    test "usage_limit_per_customer only blocks the customer who already redeemed it", %{
      scope: scope
    } do
      offer = offer_fixture(scope, %{"code" => "ONE-EACH", "usage_limit_per_customer" => 1})
      customer1 = customer_fixture(scope)
      customer2 = customer_fixture(scope)

      {:ok, _} =
        Marketing.record_redemption(scope.business, offer, customer1.id, nil, Decimal.new("5"))

      assert {:error, %{message: message}} =
               Marketing.resolve(scope.business, customer1, "ONE-EACH", Decimal.new("100"))

      assert message =~ "already used"

      assert {:ok, %{offer: found}} =
               Marketing.resolve(scope.business, customer2, "ONE-EACH", Decimal.new("100"))

      assert found
    end
  end

  describe "offer_performance/2" do
    test "aggregates redemption count and total discount", %{scope: scope} do
      offer = offer_fixture(scope)
      {:ok, _} = Marketing.record_redemption(scope.business, offer, nil, nil, Decimal.new("10"))
      {:ok, _} = Marketing.record_redemption(scope.business, offer, nil, nil, Decimal.new("15"))

      assert %{redemption_count: 2, total_discount: total} =
               Marketing.offer_performance(scope, offer)

      assert Decimal.equal?(total, Decimal.new("25"))
    end
  end

  describe "run_daily_retention/1" do
    test "sends a birthday message and awards the configured bonus to a customer whose birthday is today",
         %{
           scope: scope
         } do
      {:ok, _} =
        Loyalty.upsert_program(scope, %{"enabled" => true, "birthday_bonus_points" => 50})

      approved_template_fixture(scope, %{
        "purpose" => "birthday",
        "body" => "Happy birthday, {{1}}!"
      })

      today = Date.utc_today()
      birthday = %{today | year: today.year - 20}

      customer =
        customer_fixture(scope, date_of_birth: birthday, accepts_promotional_messages: true)

      assert :ok = Marketing.run_daily_retention(scope.business)

      assert [message] = Repo.all(WhatsappMessage)
      assert message.customer_id == customer.id
      assert message.kind == "promotional"

      assert Posbd.Customers.get_customer(scope, customer.id).loyalty_points_balance == 50
    end

    test "does not message a customer whose birthday isn't today", %{scope: scope} do
      approved_template_fixture(scope, %{"purpose" => "birthday"})
      not_today = Date.add(Date.utc_today(), 10)
      customer_fixture(scope, date_of_birth: not_today, accepts_promotional_messages: true)

      assert :ok = Marketing.run_daily_retention(scope.business)
      assert Repo.all(WhatsappMessage) == []
    end

    test "sends a win-back message to a customer inactive for over 90 days", %{scope: scope} do
      approved_template_fixture(scope, %{"purpose" => "winback", "body" => "We miss you, {{1}}!"})
      customer = customer_fixture(scope, accepts_promotional_messages: true)
      product = product_fixture(scope, selling_price: "50.00")

      old_date =
        DateTime.utc_now() |> DateTime.add(-100 * 86_400, :second) |> DateTime.truncate(:second)

      {:ok, _invoice} =
        Billing.import_historical_invoice(scope, %{
          "invoice_number" => "OLD-1",
          "issued_at" => old_date,
          "customer_id" => customer.id,
          "items" => [%{"product_id" => product.id, "quantity" => 1, "unit_price" => "50.00"}]
        })

      assert :ok = Marketing.run_daily_retention(scope.business)

      assert [message] = Repo.all(WhatsappMessage)
      assert message.customer_id == customer.id
      assert message.body =~ "We miss you"
    end

    test "does not win-back a recently active customer", %{scope: scope} do
      approved_template_fixture(scope, %{"purpose" => "winback"})
      customer = customer_fixture(scope, accepts_promotional_messages: true)
      product = product_fixture(scope, selling_price: "50.00")

      {:ok, _invoice} =
        Billing.create_invoice(scope, %{
          "customer_id" => customer.id,
          "items" => [%{"product_id" => product.id, "quantity" => 1}]
        })

      assert :ok = Marketing.run_daily_retention(scope.business)
      assert Repo.all(WhatsappMessage) == []
    end
  end
end
