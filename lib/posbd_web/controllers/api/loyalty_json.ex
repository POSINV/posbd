defmodule PosbdWeb.Api.LoyaltyJSON do
  alias Posbd.Loyalty.{LoyaltyLedgerEntry, LoyaltyProgram}
  alias PosbdWeb.Api.ProductJSON

  def program(%{program: program, active: active}) do
    %{data: program_json(program) |> Map.put(:active, active)}
  end

  def ledger(%{
        data: entries,
        page: page,
        page_size: page_size,
        total_count: total_count,
        balance: balance
      }) do
    %{
      data: Enum.map(entries, &entry_json/1),
      balance: balance,
      pagination: %{page: page, page_size: page_size, total_count: total_count}
    }
  end

  defp program_json(%LoyaltyProgram{} = program) do
    %{
      enabled: program.enabled,
      earn_amount_per_point: ProductJSON.money(program.earn_amount_per_point),
      redeem_value_per_point: ProductJSON.money(program.redeem_value_per_point),
      min_redeem_points: program.min_redeem_points,
      max_redemption_percentage: ProductJSON.money(program.max_redemption_percentage),
      points_expiry_days: program.points_expiry_days,
      birthday_bonus_points: program.birthday_bonus_points
    }
  end

  defp entry_json(%LoyaltyLedgerEntry{} = entry) do
    %{
      id: entry.id,
      entry_type: entry.entry_type,
      points: entry.points,
      balance_after: entry.balance_after,
      description: entry.description,
      invoice_id: entry.invoice_id,
      invoice_number: invoice_number(entry),
      inserted_at: entry.inserted_at
    }
  end

  defp invoice_number(%LoyaltyLedgerEntry{invoice: %Ecto.Association.NotLoaded{}}), do: nil
  defp invoice_number(%LoyaltyLedgerEntry{invoice: nil}), do: nil
  defp invoice_number(%LoyaltyLedgerEntry{invoice: invoice}), do: invoice.invoice_number
end
