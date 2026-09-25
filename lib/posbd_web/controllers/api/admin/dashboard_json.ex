defmodule PosbdWeb.Api.Admin.DashboardJSON do
  alias PosbdWeb.Api.SubscriptionJSON

  def show(%{counts: counts}) do
    %{data: Map.new(counts, fn {status, count} -> {to_string(status), count} end)}
  end

  def businesses(%{rows: rows}) do
    %{data: Enum.map(rows, &business_row_json/1)}
  end

  defp business_row_json({sub, status}) do
    %{
      business_id: sub.business_id,
      business_name: sub.business.name,
      business_type: sub.business.business_type,
      status: status,
      plan: sub.plan && SubscriptionJSON.plan_json(sub.plan),
      trial_ends_at: sub.trial_ends_at,
      current_period_end: sub.current_period_end,
      inserted_at: sub.inserted_at
    }
  end
end
