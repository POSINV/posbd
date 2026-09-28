defmodule Posbd.Whatsapp do
  @moduledoc """
  WhatsApp Business Platform integration (Phase 2 §23-§29): templates
  (with their platform-admin approval workflow), the event-driven sends
  that fire after a bill/payment/loyalty event, promotional campaigns to
  a customer segment, and the message history log both feed. Every send
  goes through `Posbd.Whatsapp.SendMessageWorker` on an Oban queue
  (Phase 2 §35/§26) - nothing here ever calls the provider inline, so a
  slow or failing WhatsApp API call can never slow down or fail the
  request that triggered it (a sale, a payment, a campaign schedule).

  Requires the business's subscription plan to grant the `"whatsapp"`
  feature (see `Posbd.Subscriptions.has_feature?/2`) - checked on every
  send, not just once, so a downgraded plan takes effect immediately.
  """

  import Ecto.Query, warn: false

  alias Posbd.Repo
  alias Posbd.Accounts.Scope
  alias Posbd.Businesses.Business
  alias Posbd.Customers
  alias Posbd.Customers.Customer
  alias Posbd.PlatformAdmins.PlatformAdmin
  alias Posbd.Subscriptions

  alias Posbd.Whatsapp.{
    CampaignDispatchWorker,
    SendMessageWorker,
    WhatsappCampaign,
    WhatsappMessage,
    WhatsappTemplate
  }

  @meta_language_codes %{
    "en" => "en_US",
    "hi" => "hi",
    "ta" => "ta",
    "te" => "te",
    "ml" => "ml",
    "mr" => "mr",
    "gu" => "gu",
    "bn" => "bn",
    "kn" => "kn"
  }

  ## Templates (business side)

  def list_templates(%Scope{business: business}) do
    WhatsappTemplate
    |> where([t], t.business_id == ^business.id)
    |> order_by([t], desc: t.inserted_at)
    |> Repo.all()
  end

  def get_template(%Scope{business: business}, id) do
    Repo.get_by(WhatsappTemplate, id: id, business_id: business.id)
  end

  @doc "Creates a template; it always starts in `pending_approval`, regardless of what a client sends."
  def create_template(%Scope{business: business}, attrs) do
    %WhatsappTemplate{business_id: business.id}
    |> WhatsappTemplate.submit_changeset(attrs)
    |> Repo.insert()
  end

  @doc "Updating a template's content resubmits it for approval - a previously-approved name/status can never silently keep serving edited content."
  def update_template(%Scope{}, %WhatsappTemplate{} = template, attrs) do
    template |> WhatsappTemplate.submit_changeset(attrs) |> Repo.update()
  end

  ## Templates (platform-admin review, Phase 2 §24)

  def list_templates_for_review(status_filter \\ "pending_approval") do
    WhatsappTemplate
    |> maybe_filter_status(status_filter)
    |> order_by([t], asc: t.inserted_at)
    |> preload(:business)
    |> Repo.all()
  end

  defp maybe_filter_status(query, nil), do: query
  defp maybe_filter_status(query, status), do: where(query, [t], t.status == ^status)

  def get_template_for_review(id), do: Repo.get(WhatsappTemplate, id) |> Repo.preload(:business)

  def approve_template(
        %PlatformAdmin{} = admin,
        %WhatsappTemplate{} = template,
        provider_template_name
      ) do
    template |> WhatsappTemplate.approve_changeset(provider_template_name, admin) |> Repo.update()
  end

  def reject_template(%PlatformAdmin{} = admin, %WhatsappTemplate{} = template, reason) do
    template |> WhatsappTemplate.reject_changeset(reason, admin) |> Repo.update()
  end

  ## Event-driven sends (Phase 2 §25-§26) - called by other contexts right
  ## after the event they describe has already committed. Never raises
  ## into the caller (mirrors `Posbd.AuditLogs.record/5`'s guarantee) -
  ## a WhatsApp hiccup must never be able to fail the sale/payment/points
  ## it's just reporting on.

  def notify_invoice_created(%Business{} = business, invoice) do
    safely(fn ->
      with %Customer{} = customer <- invoice.customer,
           %WhatsappTemplate{} = template <- find_template(business, "billing", customer) do
        variables =
          template_variables(template, [customer.name, invoice.invoice_number, money(invoice)])

        send_via_template(business, customer, template, "transactional", variables)
      else
        _ -> {:skip, :not_applicable}
      end
    end)
  end

  def notify_payment_recorded(%Business{} = business, invoice, payment) do
    safely(fn ->
      with %Customer{} = customer <- invoice.customer,
           %WhatsappTemplate{} = template <- find_template(business, "payment", customer) do
        amount = "#{invoice.currency} #{Decimal.to_string(payment.amount)}"
        variables = template_variables(template, [customer.name, amount, invoice.invoice_number])
        send_via_template(business, customer, template, "transactional", variables)
      else
        _ -> {:skip, :not_applicable}
      end
    end)
  end

  def notify_loyalty_earned(%Business{} = business, invoice) do
    safely(fn ->
      with true <- (invoice.loyalty_points_earned || 0) > 0,
           %Customer{} = customer <- invoice.customer,
           %WhatsappTemplate{} = template <- find_template(business, "loyalty", customer) do
        balance =
          Customers.get_customer(%Scope{business: business}, customer.id).loyalty_points_balance

        variables =
          template_variables(template, [customer.name, invoice.loyalty_points_earned, balance])

        send_via_template(business, customer, template, "transactional", variables)
      else
        _ -> {:skip, :not_applicable}
      end
    end)
  end

  @doc "A birthday message (and, per the business's loyalty config, a birthday points bonus - see `Posbd.Marketing.run_daily_retention/1`) for one customer, if an approved `birthday`-purpose template exists and they've consented to promotional messages."
  def notify_birthday(%Business{} = business, %Customer{} = customer) do
    safely(fn ->
      with %WhatsappTemplate{} = template <- find_template(business, "birthday", customer) do
        variables = template_variables(template, [customer.name])
        send_via_template(business, customer, template, "promotional", variables)
      else
        _ -> {:skip, :not_applicable}
      end
    end)
  end

  @doc "A 'we miss you' win-back nudge for a customer who hasn't purchased in a while, if an approved `winback`-purpose template exists and they've consented to promotional messages."
  def notify_winback(%Business{} = business, %Customer{} = customer) do
    safely(fn ->
      with %WhatsappTemplate{} = template <- find_template(business, "winback", customer) do
        variables = template_variables(template, [customer.name])
        send_via_template(business, customer, template, "promotional", variables)
      else
        _ -> {:skip, :not_applicable}
      end
    end)
  end

  defp safely(fun) do
    fun.()
  rescue
    _ -> {:skip, :error}
  end

  defp money(invoice), do: "#{invoice.currency} #{Decimal.to_string(invoice.total_amount)}"

  defp template_variables(template, values), do: Enum.take(values, template.variable_count)

  defp find_template(%Business{} = business, purpose, %Customer{} = customer) do
    templates =
      WhatsappTemplate
      |> where(
        [t],
        t.business_id == ^business.id and t.purpose == ^purpose and t.status == "approved"
      )
      |> Repo.all()

    preferred = customer.preferred_language

    Enum.find(templates, &(&1.language == preferred)) ||
      Enum.find(templates, &(&1.language == business.language)) ||
      Enum.find(templates, &(&1.language == "en")) ||
      List.first(templates)
  end

  ## Core send primitive

  # No more than one promotional message per customer in this window,
  # whether it came from a campaign or automated retention (Phase 2
  # §31/§34) - enforced here, in the one place every promotional send
  # passes through, rather than trusted to each caller.
  @promotional_cooldown_days 7

  defp send_via_template(business, customer, template, kind, variables, campaign_id \\ nil) do
    cond do
      not Subscriptions.has_feature?(business, "whatsapp") ->
        {:skip, :not_entitled}

      blank?(customer.phone) ->
        {:skip, :no_phone}

      kind == "transactional" and not customer.accepts_transactional_messages ->
        {:skip, :opted_out}

      kind == "promotional" and not customer.accepts_promotional_messages ->
        {:skip, :opted_out}

      kind == "promotional" and recently_sent_promotional?(business, customer.id) ->
        {:skip, :frequency_limited}

      true ->
        do_send(business, customer, template, kind, variables, campaign_id)
    end
  end

  defp recently_sent_promotional?(business, customer_id) do
    cutoff = DateTime.add(DateTime.utc_now(), -@promotional_cooldown_days * 86_400, :second)

    WhatsappMessage
    |> where(
      [m],
      m.business_id == ^business.id and m.customer_id == ^customer_id and m.kind == "promotional" and
        m.inserted_at >= ^cutoff
    )
    |> Repo.exists?()
  end

  defp do_send(business, customer, template, kind, variables, campaign_id) do
    body = render_body(template.body, variables)

    {:ok, message} =
      %WhatsappMessage{}
      |> WhatsappMessage.changeset(%{
        business_id: business.id,
        customer_id: customer.id,
        template_id: template.id,
        campaign_id: campaign_id,
        kind: kind,
        phone: customer.phone,
        body: body
      })
      |> Repo.insert()

    %{
      "message_id" => message.id,
      "phone" => customer.phone,
      "provider_template_name" => template.provider_template_name,
      "language" => meta_language_code(template.language),
      "variables" => Enum.map(variables, &to_string/1)
    }
    |> SendMessageWorker.new()
    |> Oban.insert()

    {:ok, message}
  end

  defp render_body(body, variables) do
    variables
    |> Enum.with_index(1)
    |> Enum.reduce(body, fn {value, index}, acc ->
      String.replace(acc, "{{#{index}}}", to_string(value))
    end)
  end

  defp meta_language_code(code), do: Map.get(@meta_language_codes, code, code)

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_), do: false

  ## Campaigns (Phase 2 §28)

  def list_campaigns(%Scope{business: business}) do
    WhatsappCampaign
    |> where([c], c.business_id == ^business.id)
    |> order_by([c], desc: c.inserted_at)
    |> preload(:template)
    |> Repo.all()
  end

  def get_campaign(%Scope{business: business}, id) do
    WhatsappCampaign
    |> where([c], c.id == ^id and c.business_id == ^business.id)
    |> preload(:template)
    |> Repo.one()
  end

  @doc "Creates a draft campaign against one of the business's own *approved* templates."
  def create_campaign(%Scope{business: business, user: user}, attrs) do
    template_id = attrs["template_id"]

    template =
      template_id not in [nil, ""] &&
        Repo.get_by(WhatsappTemplate, id: template_id, business_id: business.id)

    case template do
      %WhatsappTemplate{status: "approved"} = template ->
        %WhatsappCampaign{}
        |> WhatsappCampaign.changeset(
          Map.merge(attrs, %{
            "business_id" => business.id,
            "created_by_id" => user.id,
            "template_id" => template.id
          })
        )
        |> Repo.insert()

      %WhatsappTemplate{status: status} ->
        {:error, %{message: "Template is #{status}, not approved"}}

      _ ->
        {:error, %{message: "Template not found"}}
    end
  end

  @doc """
  Schedules (or immediately dispatches, if `scheduled_at` is nil/past) a
  draft campaign. Either way, the actual fan-out to customers always
  happens in `Posbd.Whatsapp.CampaignDispatchWorker`, never inline here.
  """
  def schedule_campaign(
        %Scope{business: business} = scope,
        %WhatsappCampaign{} = campaign,
        scheduled_at \\ nil
      ) do
    unless Subscriptions.has_feature?(business, "whatsapp") do
      {:error, %{message: "WhatsApp is not available on this business's current plan"}}
    else
      with {:ok, campaign} <- put_schedule(scope, campaign, scheduled_at) do
        enqueue_dispatch(campaign)
        {:ok, campaign}
      end
    end
  end

  defp put_schedule(_scope, campaign, nil) do
    campaign |> WhatsappCampaign.status_changeset("sent") |> Repo.update()
  end

  defp put_schedule(_scope, campaign, scheduled_at) do
    # `scheduled_at` is `:utc_datetime` (not usec) - normalize here so every
    # caller (controller, tests, ...) gets this for free rather than each
    # needing to remember to truncate.
    scheduled_at = DateTime.truncate(scheduled_at, :second)

    if DateTime.compare(scheduled_at, DateTime.utc_now()) == :gt do
      campaign
      |> Ecto.Changeset.change(scheduled_at: scheduled_at, status: "scheduled")
      |> Repo.update()
    else
      campaign |> WhatsappCampaign.status_changeset("sent") |> Repo.update()
    end
  end

  defp enqueue_dispatch(%WhatsappCampaign{status: "scheduled", scheduled_at: at} = campaign) do
    %{"campaign_id" => campaign.id}
    |> CampaignDispatchWorker.new(scheduled_at: at)
    |> Oban.insert()
  end

  defp enqueue_dispatch(%WhatsappCampaign{} = campaign) do
    %{"campaign_id" => campaign.id} |> CampaignDispatchWorker.new() |> Oban.insert()
  end

  @doc "Cancels a campaign that hasn't sent yet."
  def cancel_campaign(%Scope{}, %WhatsappCampaign{status: status} = campaign)
      when status in ["draft", "scheduled"] do
    campaign |> WhatsappCampaign.status_changeset("cancelled") |> Repo.update()
  end

  def cancel_campaign(%Scope{}, %WhatsappCampaign{}),
    do: {:error, %{message: "This campaign has already been sent"}}

  @doc "Delivery status breakdown for one campaign's messages (Phase 2 §34 - campaign analytics)."
  def campaign_stats(%Scope{business: business}, %WhatsappCampaign{} = campaign) do
    counts =
      WhatsappMessage
      |> where([m], m.business_id == ^business.id and m.campaign_id == ^campaign.id)
      |> group_by([m], m.status)
      |> select([m], {m.status, count(m.id)})
      |> Repo.all()
      |> Map.new()

    %{
      queued: Map.get(counts, "queued", 0),
      sent: Map.get(counts, "sent", 0),
      delivered: Map.get(counts, "delivered", 0),
      read: Map.get(counts, "read", 0),
      failed: Map.get(counts, "failed", 0),
      total: counts |> Map.values() |> Enum.sum()
    }
  end

  @doc "Fans a campaign out to its audience - called by `CampaignDispatchWorker`, never directly from a request."
  def dispatch_campaign(campaign_id) do
    campaign = Repo.get!(WhatsappCampaign, campaign_id) |> Repo.preload([:business, :template])

    campaign
    |> resolve_audience()
    |> Enum.each(fn customer ->
      variables = template_variables(campaign.template, [customer.name])

      send_via_template(
        campaign.business,
        customer,
        campaign.template,
        "promotional",
        variables,
        campaign.id
      )
    end)

    :ok
  end

  defp resolve_audience(%WhatsappCampaign{business: business, audience_segment: "all"}) do
    %Scope{business: business}
    |> Customers.list_customers()
    |> Enum.map(& &1.customer)
    |> Enum.filter(&eligible_for_promotional?/1)
  end

  defp resolve_audience(%WhatsappCampaign{business: business, audience_segment: segment}) do
    %Scope{business: business}
    |> Customers.list_customers(%{"segment" => segment})
    |> Enum.map(& &1.customer)
    |> Enum.filter(&eligible_for_promotional?/1)
  end

  defp eligible_for_promotional?(%Customer{} = customer),
    do: customer.accepts_promotional_messages and not blank?(customer.phone)

  ## Message history (Phase 2 §27)

  def list_messages(%Scope{business: business}, params \\ %{}) do
    page = max(to_integer(params[:page] || params["page"], 1), 1)
    page_size = min(to_integer(params[:page_size] || params["page_size"], 25), 100)

    base_query =
      WhatsappMessage
      |> where([m], m.business_id == ^business.id)
      |> maybe_filter_customer(params[:customer_id] || params["customer_id"])
      |> maybe_filter_campaign(params[:campaign_id] || params["campaign_id"])

    total_count = base_query |> select(count()) |> Repo.one()

    messages =
      base_query
      |> order_by([m], desc: m.inserted_at)
      |> limit(^page_size)
      |> offset(^((page - 1) * page_size))
      |> preload([:customer, :template])
      |> Repo.all()

    %{data: messages, page: page, page_size: page_size, total_count: total_count}
  end

  defp maybe_filter_customer(query, nil), do: query
  defp maybe_filter_customer(query, ""), do: query
  defp maybe_filter_customer(query, id), do: where(query, [m], m.customer_id == ^id)

  defp maybe_filter_campaign(query, nil), do: query
  defp maybe_filter_campaign(query, ""), do: query
  defp maybe_filter_campaign(query, id), do: where(query, [m], m.campaign_id == ^id)

  ## Delivery-status webhook (Phase 2 §27)

  @doc "Applies one Meta status callback entry (`sent`/`delivered`/`read`/`failed`) to the matching message, looked up by `provider_message_id`. A status for a message we don't have (e.g. a duplicate/out-of-order delivery) is a no-op."
  def process_status_update(provider_message_id, status) do
    case Repo.get_by(WhatsappMessage, provider_message_id: provider_message_id) do
      nil -> :ok
      message -> message |> WhatsappMessage.status_update_changeset(status) |> Repo.update()
    end

    :ok
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
