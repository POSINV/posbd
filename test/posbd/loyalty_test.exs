defmodule Posbd.LoyaltyTest do
  use Posbd.DataCase, async: true

  alias Posbd.AuditLogs
  alias Posbd.Loyalty
  alias Posbd.Loyalty.LoyaltyProgram

  import Posbd.BusinessesFixtures
  import Posbd.CustomersFixtures

  setup do
    %{scope: full_scope_fixture()}
  end

  describe "get_program/1" do
    test "returns a default, disabled program when the business never configured one", %{
      scope: scope
    } do
      program = Loyalty.get_program(scope.business)
      refute program.enabled
      assert program.id == nil
      assert Decimal.equal?(program.earn_amount_per_point, Decimal.new("100"))
    end
  end

  describe "upsert_program/2" do
    test "creates the program on first call and updates it on later calls", %{scope: scope} do
      assert {:ok, program} =
               Loyalty.upsert_program(scope, %{
                 "enabled" => true,
                 "earn_amount_per_point" => "50",
                 "redeem_value_per_point" => "1"
               })

      assert program.enabled
      assert Decimal.equal?(program.earn_amount_per_point, Decimal.new("50"))

      assert {:ok, updated} = Loyalty.upsert_program(scope, %{"enabled" => false})
      assert updated.id == program.id
      refute updated.enabled

      assert [latest, first] = AuditLogs.list(scope).data
      assert latest.action == "loyalty.program_updated"
      assert first.action == "loyalty.program_updated"
    end

    test "rejects an out-of-range max_redemption_percentage", %{scope: scope} do
      assert {:error, changeset} =
               Loyalty.upsert_program(scope, %{"max_redemption_percentage" => "150"})

      assert %{max_redemption_percentage: ["must be less than or equal to 100"]} =
               errors_on(changeset)
    end
  end

  describe "active?/1" do
    test "false when never configured", %{scope: scope} do
      refute Loyalty.active?(scope.business)
    end

    test "true once enabled, since a fresh business is still inside its trial", %{scope: scope} do
      {:ok, _} = Loyalty.upsert_program(scope, %{"enabled" => true})
      assert Loyalty.active?(scope.business)
    end
  end

  describe "points_for_amount/2" do
    test "floors to whole points and is 0 for a disabled program" do
      program = %LoyaltyProgram{enabled: true, earn_amount_per_point: Decimal.new("100")}
      assert Loyalty.points_for_amount(program, Decimal.new("250")) == 2

      disabled = %LoyaltyProgram{program | enabled: false}
      assert Loyalty.points_for_amount(disabled, Decimal.new("250")) == 0
    end
  end

  describe "quote_redemption/4" do
    @program %LoyaltyProgram{
      enabled: true,
      min_redeem_points: 100,
      redeem_value_per_point: Decimal.new("0.5"),
      max_redemption_percentage: Decimal.new("50")
    }

    test "is a no-op for nil/zero requests" do
      assert {:ok, %{points: 0, value: value}} =
               Loyalty.quote_redemption(@program, 500, nil, Decimal.new("1000"))

      assert Decimal.equal?(value, Decimal.new(0))
    end

    test "rejects redeeming more points than the customer has" do
      assert {:error, %{message: message}} =
               Loyalty.quote_redemption(@program, 50, 200, Decimal.new("1000"))

      assert message =~ "only has 50 points"
    end

    test "rejects below the minimum redeemable points" do
      assert {:error, %{message: message}} =
               Loyalty.quote_redemption(@program, 500, 50, Decimal.new("1000"))

      assert message =~ "minimum of 100 points"
    end

    test "rejects a redemption above the max-percentage cap" do
      # 500 points * 0.5 = 250, but 50% of a 300 bill is only 150
      assert {:error, %{message: message}} =
               Loyalty.quote_redemption(@program, 500, 500, Decimal.new("300"))

      assert message =~ "limited to"
    end

    test "returns the redemption value for a valid request" do
      assert {:ok, %{points: 200, value: value}} =
               Loyalty.quote_redemption(@program, 500, 200, Decimal.new("1000"))

      assert Decimal.equal?(value, Decimal.new("100.00"))
    end
  end

  describe "record_entry/2 and balance" do
    test "earning credits the balance and writes a ledger row with balance_after", %{
      scope: scope
    } do
      customer = customer_fixture(scope)

      assert {:ok, entry} =
               Loyalty.record_entry(scope, %{
                 "customer_id" => customer.id,
                 "entry_type" => "earn",
                 "points" => 30,
                 "description" => "test earn"
               })

      assert entry.balance_after == 30

      reloaded = Posbd.Customers.get_customer(scope, customer.id)
      assert reloaded.loyalty_points_balance == 30
    end

    test "redeeming beyond the balance is rejected and never goes negative", %{scope: scope} do
      customer = customer_fixture(scope)

      {:ok, _} =
        Loyalty.record_entry(scope, %{
          "customer_id" => customer.id,
          "entry_type" => "earn",
          "points" => 30
        })

      assert {:error, %{message: message}} =
               Loyalty.record_entry(scope, %{
                 "customer_id" => customer.id,
                 "entry_type" => "redeem",
                 "points" => -50
               })

      assert message =~ "Insufficient"
      assert Posbd.Customers.get_customer(scope, customer.id).loyalty_points_balance == 30
    end
  end

  describe "list_ledger/3" do
    test "returns entries for the customer, newest first", %{scope: scope} do
      customer = customer_fixture(scope)

      {:ok, _} =
        Loyalty.record_entry(scope, %{
          "customer_id" => customer.id,
          "entry_type" => "earn",
          "points" => 10
        })

      {:ok, _} =
        Loyalty.record_entry(scope, %{
          "customer_id" => customer.id,
          "entry_type" => "earn",
          "points" => 5
        })

      result = Loyalty.list_ledger(scope, customer.id)
      assert result.total_count == 2
      assert [%{points: 5}, %{points: 10}] = result.data
    end
  end
end
