defmodule Posbd.Subscriptions.Lifecycle do
  @moduledoc """
  The subscription state machine (Phase 2 §5), kept as one small pure
  module rather than scattered status strings throughout the app.

  A `%Subscription{}` only *persists* the small set of states that are
  genuine decisions (`trialing`, `active`, `past_due`, `grace_period`,
  `suspended`, `cancelled`). Presentational states from the spec's fuller
  lifecycle - trial ending soon, trial expired, renewal due, subscription
  required - are derived here from the stored dates every time they're
  read, so they're always correct even before any background job has run.
  """

  alias Posbd.Subscriptions.Subscription

  @warning_window_days 7

  @doc """
  The full presentational status as an atom: `:trialing`,
  `:trial_ending_soon`, `:trial_expired`, `:active`, `:renewal_due`,
  `:past_due`, `:grace_period`, `:suspended`, or `:cancelled`.
  """
  def effective_status(%Subscription{} = sub, now \\ DateTime.utc_now()) do
    case sub.status do
      "cancelled" -> :cancelled
      "suspended" -> :suspended
      "grace_period" -> grace_status(sub, now)
      "past_due" -> :past_due
      "active" -> active_status(sub, now)
      "trialing" -> trialing_status(sub, now)
    end
  end

  defp grace_status(%{grace_period_ends_at: nil}, _now), do: :suspended

  defp grace_status(%{grace_period_ends_at: ends_at}, now) do
    if DateTime.compare(now, ends_at) == :gt, do: :suspended, else: :grace_period
  end

  defp active_status(%{current_period_end: nil}, _now), do: :active

  defp active_status(%{current_period_end: period_end}, now) do
    cond do
      DateTime.compare(now, period_end) == :gt -> :renewal_due
      days_until(period_end, now) <= @warning_window_days -> :renewal_due
      true -> :active
    end
  end

  defp trialing_status(%{trial_ends_at: nil}, _now), do: :trialing

  defp trialing_status(%{trial_ends_at: ends_at}, now) do
    cond do
      DateTime.compare(now, ends_at) == :gt -> :trial_expired
      days_until(ends_at, now) <= @warning_window_days -> :trial_ending_soon
      true -> :trialing
    end
  end

  defp days_until(datetime, now), do: div(DateTime.diff(datetime, now, :second), 86_400)

  @blocked [:trial_expired, :suspended, :cancelled]

  @doc """
  Whether a business in this status may keep using the application (Phase
  2 §9) - a trial that hasn't converted, or a subscription that was
  suspended/cancelled, blocks access; everything still mid-grace-period
  (including a failed payment that hasn't escalated to suspension yet)
  does not.
  """
  def entitled?(status) when status in @blocked, do: false
  def entitled?(_status), do: true

  @doc "Days remaining until `datetime`, floored at 0, or `nil` if `datetime` is `nil`."
  def days_remaining(nil, _now), do: nil

  def days_remaining(datetime, now) do
    days_until(datetime, now) |> max(0)
  end
end
