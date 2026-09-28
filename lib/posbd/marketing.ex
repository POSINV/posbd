defmodule Posbd.Marketing do
  @moduledoc """
  Offers/promotions (Phase 2 §21/§30): code-based or automatic discounts,
  scoped by validity window, minimum purchase, customer segment, and
  usage limits. `resolve/4` is the backend-validated pricing decision
  `Posbd.Billing` calls into while creating an invoice - a client can
  request a `code`, but never the discount amount itself.

  `run_daily_retention/1` is the other half (Phase 2 §31) - birthday and
  win-back-the-inactive automation, run once a day by
  `Posbd.Marketing.RetentionWorker` for every business.
  """

  import Ecto.Query, warn: false

  alias Posbd.AuditLogs
  alias Posbd.Billing.Invoice
  alias Posbd.Customers
  alias Posbd.Loyalty
  alias Posbd.Repo
  alias Posbd.Accounts.Scope
  alias Posbd.Businesses.Business
  alias Posbd.Customers.Customer
  alias Posbd.Marketing.{Offer, OfferRedemption}
  alias Posbd.Whatsapp

  ## CRUD (business side)

  def list_offers(%Scope{business: business}) do
    Offer
    |> where([o], o.business_id == ^business.id)
    |> order_by([o], desc: o.inserted_at)
    |> Repo.all()
  end

  def get_offer(%Scope{business: business}, id) do
    Repo.get_by(Offer, id: id, business_id: business.id)
  end

  def create_offer(%Scope{business: business, user: user} = scope, attrs) do
    %Offer{business_id: business.id, created_by_id: user.id}
    |> Offer.changeset(attrs)
    |> Repo.insert()
    |> after_write(scope, "offer.created")
  end

  def update_offer(%Scope{} = scope, %Offer{} = offer, attrs) do
    offer
    |> Offer.changeset(attrs)
    |> Repo.update()
    |> after_write(scope, "offer.updated")
  end

  defp after_write({:ok, offer} = ok, scope, action) do
    AuditLogs.record(scope, action, "Offer", offer.id, %{name: offer.name, code: offer.code})
    ok
  end

  defp after_write(error, _scope, _action), do: error

  @doc "Redemption count and total discount given for one offer (Phase 2 §34 - offer performance)."
  def offer_performance(%Scope{business: business}, %Offer{} = offer) do
    OfferRedemption
    |> where([r], r.business_id == ^business.id and r.offer_id == ^offer.id)
    |> select([r], %{
      redemption_count: count(r.id),
      total_discount: coalesce(sum(r.discount_amount), 0)
    })
    |> Repo.one()
  end

  ## Resolution (called by Posbd.Billing - no DB writes except the redemption record after invoice insert)

  @doc """
  Resolves which offer (if any) applies to a bill of `subtotal` for
  `customer` (may be `nil` for a walk-in sale), given an optional
  `code` the cashier/customer entered. Returns
  `{:ok, %{offer: nil | offer, discount_amount: Decimal}}` -
  `offer: nil` is a normal, common outcome (no code entered and no
  automatic offer currently qualifies), never an error. An explicitly
  entered `code` that doesn't resolve to a valid, currently-usable offer
  *is* an error - the cashier asked for something specific and got
  nothing, so they should be told why.
  """
  def resolve(%Business{} = business, customer, code, subtotal) when code in [nil, ""] do
    offer =
      automatic_offers(business)
      |> Enum.filter(&eligible?(&1, business, customer, subtotal))
      |> Enum.max_by(&discount_for(&1, subtotal), Decimal, fn -> nil end)

    {:ok, %{offer: offer, discount_amount: discount_for(offer, subtotal)}}
  end

  def resolve(%Business{} = business, customer, code, subtotal) do
    normalized = code |> String.trim() |> String.upcase()

    case Repo.get_by(Offer, business_id: business.id, code: normalized) do
      nil ->
        {:error, %{message: "Offer code not found"}}

      offer ->
        case ineligibility_reason(offer, business, customer, subtotal) do
          nil -> {:ok, %{offer: offer, discount_amount: discount_for(offer, subtotal)}}
          reason -> {:error, %{message: reason}}
        end
    end
  end

  defp automatic_offers(business) do
    Offer
    |> where([o], o.business_id == ^business.id and o.status == "active" and is_nil(o.code))
    |> Repo.all()
  end

  defp eligible?(offer, business, customer, subtotal),
    do: ineligibility_reason(offer, business, customer, subtotal) == nil

  defp discount_for(nil, _subtotal), do: Decimal.new(0)

  defp discount_for(%Offer{discount_type: "percentage"} = offer, subtotal) do
    subtotal |> Decimal.mult(offer.discount_value) |> Decimal.div(100) |> Decimal.round(2)
  end

  defp discount_for(%Offer{discount_type: "fixed_amount"} = offer, subtotal) do
    Decimal.min(offer.discount_value, subtotal)
  end

  defp ineligibility_reason(%Offer{status: "inactive"}, _business, _customer, _subtotal),
    do: "This offer is no longer active"

  defp ineligibility_reason(offer, business, customer, subtotal) do
    now = DateTime.utc_now()

    cond do
      offer.starts_at && DateTime.compare(now, offer.starts_at) == :lt ->
        "This offer is not valid yet"

      offer.ends_at && DateTime.compare(now, offer.ends_at) == :gt ->
        "This offer has expired"

      Decimal.compare(subtotal, offer.min_purchase_amount) == :lt ->
        "A minimum purchase of #{Decimal.to_string(offer.min_purchase_amount)} is required for this offer"

      offer.eligible_segment != "all" and
          not segment_matches?(business, customer, offer.eligible_segment) ->
        "This offer is only available to #{String.replace(offer.eligible_segment, "_", " ")} customers"

      offer.usage_limit_total && total_redemptions(offer) >= offer.usage_limit_total ->
        "This offer has reached its usage limit"

      offer.usage_limit_per_customer && customer &&
          customer_redemptions(offer, customer) >= offer.usage_limit_per_customer ->
        "You've already used this offer the maximum number of times"

      offer.usage_limit_per_customer && is_nil(customer) ->
        "This offer requires a registered customer"

      true ->
        nil
    end
  end

  defp segment_matches?(_business, nil, _segment), do: false

  defp segment_matches?(business, %Customer{} = customer, segment) do
    Customers.purchase_summary(%Scope{business: business}, customer).segment ==
      String.to_existing_atom(segment)
  end

  defp total_redemptions(offer) do
    OfferRedemption
    |> where([r], r.offer_id == ^offer.id)
    |> select([r], count(r.id))
    |> Repo.one()
  end

  defp customer_redemptions(offer, customer) do
    OfferRedemption
    |> where([r], r.offer_id == ^offer.id and r.customer_id == ^customer.id)
    |> select([r], count(r.id))
    |> Repo.one()
  end

  @doc "Records that `offer` was applied to `invoice` - called by `Posbd.Billing` once the invoice (and so its id) exists."
  def record_redemption(
        %Business{} = business,
        %Offer{} = offer,
        customer_id,
        invoice_id,
        discount_amount
      ) do
    %OfferRedemption{}
    |> OfferRedemption.changeset(%{
      "business_id" => business.id,
      "offer_id" => offer.id,
      "customer_id" => customer_id,
      "invoice_id" => invoice_id,
      "discount_amount" => discount_amount
    })
    |> Repo.insert()
  end

  ## Retention automation (Phase 2 §31) - birthday bonuses/messages and
  ## win-back nudges for inactive customers. `Posbd.Whatsapp.notify_birthday/2`
  ## and `notify_winback/2` already skip a customer who hasn't consented to
  ## promotional messages or was already contacted too recently (Phase 2
  ## §34's frequency limit), so nothing here needs to duplicate those checks.

  # Same "inactive" definition `Posbd.Customers.segment/2` uses, so a
  # customer becomes a win-back candidate at the same point they'd show
  # up as "inactive" anywhere else in the app.
  @winback_after_days 90

  @doc "Runs birthday and win-back automation for one business - called once a day, for every business, by `Posbd.Marketing.RetentionWorker`."
  def run_daily_retention(%Business{} = business) do
    send_birthday_messages(business)
    send_winback_messages(business)
    :ok
  end

  defp send_birthday_messages(business) do
    today = Date.utc_today()

    Customer
    |> where([c], c.business_id == ^business.id and not is_nil(c.date_of_birth))
    |> where(
      [c],
      fragment("EXTRACT(MONTH FROM ?)", c.date_of_birth) == ^today.month and
        fragment("EXTRACT(DAY FROM ?)", c.date_of_birth) == ^today.day
    )
    |> Repo.all()
    |> Enum.each(&handle_birthday(business, &1))
  end

  defp handle_birthday(business, customer) do
    Whatsapp.notify_birthday(business, customer)
    maybe_award_birthday_bonus(business, customer)
  end

  defp maybe_award_birthday_bonus(business, customer) do
    program = Loyalty.get_program(business)

    if Loyalty.active?(business) and program.birthday_bonus_points > 0 do
      Loyalty.record_entry(%Scope{business: business}, %{
        "customer_id" => customer.id,
        "entry_type" => "bonus",
        "points" => program.birthday_bonus_points,
        "description" => "Birthday bonus"
      })
    end
  end

  defp send_winback_messages(business) do
    cutoff = DateTime.add(DateTime.utc_now(), -@winback_after_days * 86_400, :second)

    from(c in Customer,
      join: i in Invoice,
      on: i.customer_id == c.id,
      where: c.business_id == ^business.id and i.status != "cancelled",
      group_by: c.id,
      having: max(i.issued_at) < ^cutoff,
      select: c
    )
    |> Repo.all()
    |> Enum.each(&Whatsapp.notify_winback(business, &1))
  end
end
