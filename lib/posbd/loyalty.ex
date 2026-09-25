defmodule Posbd.Loyalty do
  @moduledoc """
  Loyalty points: per-business configuration, the append-only points
  ledger, and the earning/redemption math that `Posbd.Billing` calls into
  while creating an invoice (Phase 2 §17-§20).

  A business only ever gets loyalty if its subscription plan grants the
  `"loyalty"` feature (see `Posbd.Subscriptions.has_feature?/2`) *and* it
  has switched the program on - `active?/1` is the single source of
  truth other contexts should check, so entitlement can never be
  bypassed by a stale `enabled: true` row left over from a downgraded
  plan.
  """

  import Ecto.Query, warn: false

  alias Posbd.AuditLogs
  alias Posbd.Repo
  alias Posbd.Accounts.Scope
  alias Posbd.Businesses.Business
  alias Posbd.Customers.Customer
  alias Posbd.Loyalty.{LoyaltyLedgerEntry, LoyaltyProgram}
  alias Posbd.Subscriptions

  ## Program configuration

  @doc "The business's loyalty configuration, or a default (disabled) one if it has never configured it."
  def get_program(%Business{} = business) do
    Repo.get_by(LoyaltyProgram, business_id: business.id) ||
      %LoyaltyProgram{business_id: business.id}
  end

  @doc "True if `business` both has the `loyalty` feature on its plan and has switched the program on."
  def active?(%Business{} = business) do
    program = get_program(business)
    program.enabled && Subscriptions.has_feature?(business, "loyalty")
  end

  @doc "Creates or updates the business's loyalty program configuration."
  def upsert_program(%Scope{business: business} = scope, attrs) do
    program =
      Repo.get_by(LoyaltyProgram, business_id: business.id) ||
        %LoyaltyProgram{business_id: business.id}

    result = program |> LoyaltyProgram.changeset(attrs) |> Repo.insert_or_update()

    case result do
      {:ok, program} = ok ->
        AuditLogs.record(scope, "loyalty.program_updated", "LoyaltyProgram", program.id, %{
          enabled: program.enabled
        })

        ok

      error ->
        error
    end
  end

  ## Earning / redemption math (pure - no DB writes)

  @doc "Points `amount` (a Decimal, the business's currency) would earn under `program`. `0` if the program is disabled."
  def points_for_amount(%LoyaltyProgram{enabled: false}, _amount), do: 0

  def points_for_amount(%LoyaltyProgram{} = program, %Decimal{} = amount) do
    if Decimal.positive?(program.earn_amount_per_point) do
      amount
      |> Decimal.div(program.earn_amount_per_point)
      |> Decimal.round(0, :floor)
      |> Decimal.to_integer()
      |> max(0)
    else
      0
    end
  end

  @doc """
  Validates a redemption request of `requested_points` against a
  customer's `balance` and the given `bill_total`, returning the
  discount it's worth. `requested_points` of `nil`/`0` is a no-op
  (`{:ok, %{points: 0, value: Decimal.new(0)}}`), so callers don't need
  to special-case "no redemption requested".
  """
  def quote_redemption(_program, _balance, requested, _bill_total) when requested in [nil, 0] do
    {:ok, %{points: 0, value: Decimal.new(0)}}
  end

  def quote_redemption(%LoyaltyProgram{enabled: false}, _balance, _requested, _bill_total) do
    {:error, %{message: "Loyalty program is not enabled for this business"}}
  end

  def quote_redemption(%LoyaltyProgram{} = program, balance, requested, bill_total) do
    cond do
      requested < 0 ->
        {:error, %{message: "Points to redeem must be a positive number"}}

      requested > balance ->
        {:error, %{message: "Customer only has #{balance} points available"}}

      requested < program.min_redeem_points ->
        {:error,
         %{message: "A minimum of #{program.min_redeem_points} points is required to redeem"}}

      true ->
        value =
          requested
          |> Decimal.new()
          |> Decimal.mult(program.redeem_value_per_point)
          |> Decimal.round(2)

        max_value =
          bill_total
          |> Decimal.mult(program.max_redemption_percentage)
          |> Decimal.div(100)
          |> Decimal.round(2)

        cond do
          Decimal.compare(value, max_value) == :gt ->
            {:error,
             %{
               message:
                 "Redemption is limited to #{Decimal.to_string(max_value)} " <>
                   "(#{Decimal.to_string(program.max_redemption_percentage)}% of this bill)"
             }}

          Decimal.compare(value, bill_total) == :gt ->
            {:error, %{message: "Cannot redeem more points than the bill total"}}

          true ->
            {:ok, %{points: requested, value: value}}
        end
    end
  end

  ## Ledger (append-only, with an atomically-maintained cached balance)

  @doc """
  Records one ledger movement and atomically adjusts the customer's
  cached `loyalty_points_balance` in the same DB transaction - mirrors
  `Posbd.Inventory.record_movement/3`. `attrs` needs `customer_id`,
  `entry_type`, and signed `points` (positive to credit, negative to
  debit); `invoice_id`, `description`, and `created_by_id` are optional.
  Locks the customer row for the duration of the transaction so
  concurrent redemptions against the same customer can never both
  succeed against a balance that only covers one of them.
  """
  def record_entry(%Scope{business: business}, attrs) do
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
    customer_id = attrs["customer_id"]
    points = attrs["points"]

    Repo.transact(fn ->
      with %Customer{} = customer <- lock_customer(customer_id) || {:error, :customer_not_found},
           new_balance = customer.loyalty_points_balance + points,
           :ok <- check_non_negative(new_balance),
           {1, _} <-
             from(c in Customer, where: c.id == ^customer.id)
             |> Repo.update_all(set: [loyalty_points_balance: new_balance]) do
        %LoyaltyLedgerEntry{}
        |> LoyaltyLedgerEntry.changeset(
          Map.merge(attrs, %{
            "business_id" => business.id,
            "customer_id" => customer.id,
            "balance_after" => new_balance
          })
        )
        |> Repo.insert()
      end
    end)
  end

  defp lock_customer(nil), do: nil

  defp lock_customer(customer_id) do
    Customer |> where([c], c.id == ^customer_id) |> lock("FOR UPDATE") |> Repo.one()
  end

  defp check_non_negative(balance) when balance >= 0, do: :ok

  defp check_non_negative(_balance),
    do: {:error, %{message: "Insufficient loyalty points balance"}}

  @doc "The customer's current points balance."
  def balance(%Customer{loyalty_points_balance: balance}), do: balance

  @doc "Paginated ledger history for one customer, newest first."
  def list_ledger(%Scope{business: business}, customer_id, params \\ %{}) do
    page = max(to_integer(params[:page] || params["page"], 1), 1)
    page_size = min(to_integer(params[:page_size] || params["page_size"], 25), 100)

    base_query =
      LoyaltyLedgerEntry
      |> where([e], e.business_id == ^business.id and e.customer_id == ^customer_id)

    total_count = base_query |> select(count()) |> Repo.one()

    entries =
      base_query
      |> order_by([e], desc: e.inserted_at)
      |> limit(^page_size)
      |> offset(^((page - 1) * page_size))
      |> preload(:invoice)
      |> Repo.all()

    %{data: entries, page: page, page_size: page_size, total_count: total_count}
  end

  defp to_integer(nil, default), do: default

  defp to_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> default
    end
  end

  defp to_integer(value, _default) when is_integer(value), do: value
end
