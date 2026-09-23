defmodule PosbdWeb.Api.InventoryJSON do
  alias Posbd.Inventory.InventoryTransaction

  def show(%{transaction: transaction}), do: %{data: transaction_json(transaction)}

  def index(%{data: transactions, page: page, page_size: page_size, total_count: total_count}) do
    %{
      data: Enum.map(transactions, &transaction_json/1),
      pagination: %{page: page, page_size: page_size, total_count: total_count}
    }
  end

  defp transaction_json(%InventoryTransaction{} = t) do
    %{
      id: t.id,
      product_id: t.product_id,
      variant_id: t.variant_id,
      movement_type: t.movement_type,
      direction: t.direction,
      quantity: t.quantity,
      reference: t.reference,
      notes: t.notes,
      occurred_at: t.occurred_at,
      performed_by: performed_by_json(t.performed_by)
    }
  end

  defp performed_by_json(%Ecto.Association.NotLoaded{}), do: nil
  defp performed_by_json(nil), do: nil
  defp performed_by_json(user), do: %{id: user.id, full_name: user.full_name}
end
