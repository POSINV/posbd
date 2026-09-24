defmodule Posbd.Inventory do
  @moduledoc """
  The stock movement ledger (see AGENTS.md §9). `record_movement/3` is the
  only way stock quantities change - it always writes an append-only
  `InventoryTransaction` row and atomically adjusts the cached
  `stock_quantity` on the product/variant in the same DB transaction, so
  the two can never drift apart. Nothing else in the codebase should
  update `stock_quantity` directly.
  """

  import Ecto.Query, warn: false

  alias Posbd.AuditLogs
  alias Posbd.Repo
  alias Posbd.Accounts.Scope
  alias Posbd.Inventory.InventoryTransaction
  alias Posbd.Products.{Product, ProductVariant}

  @doc """
  Records a stock movement against `target` (a `%Product{}` or
  `%ProductVariant{}`) and returns `{:ok, transaction}` with the
  transaction preloaded with `:performed_by`. `attrs` needs
  `movement_type`, `direction` ("in"/"out"), and `quantity` (a positive
  integer); `reference`, `notes`, and `occurred_at` are optional.
  """
  def record_movement(%Scope{business: business, user: user} = scope, target, attrs) do
    delta = signed_delta(attrs)

    result =
      Repo.transact(fn ->
        changeset_attrs =
          attrs
          |> Map.new(fn {k, v} -> {to_string(k), v} end)
          |> Map.merge(%{
            "business_id" => business.id,
            "performed_by_id" => user.id,
            target_key(target) => target.id
          })

        with {:ok, transaction} <-
               %InventoryTransaction{}
               |> InventoryTransaction.changeset(changeset_attrs)
               |> Repo.insert(),
             {1, _} <- adjust_stock(target, delta) do
          {:ok, Repo.preload(transaction, :performed_by)}
        else
          {:error, _} = error -> error
          _ -> {:error, :stock_update_failed}
        end
      end)

    case result do
      {:ok, transaction} = ok ->
        # Only manual corrections are audited here - sales/returns/opening
        # stock already have their own trail (invoice, import log) and the
        # InventoryTransaction row itself, so logging every movement would
        # just duplicate that instead of adding signal.
        if transaction.movement_type == "adjustment" do
          AuditLogs.record(scope, "inventory.adjusted", entity_type(target), target.id, %{
            direction: transaction.direction,
            quantity: transaction.quantity,
            notes: transaction.notes
          })
        end

        ok

      error ->
        error
    end
  end

  defp entity_type(%Product{}), do: "Product"
  defp entity_type(%ProductVariant{}), do: "ProductVariant"

  defp signed_delta(%{"direction" => "out", "quantity" => qty}), do: -qty
  defp signed_delta(%{direction: "out", quantity: qty}), do: -qty
  defp signed_delta(%{"quantity" => qty}), do: qty
  defp signed_delta(%{quantity: qty}), do: qty

  defp target_key(%Product{}), do: "product_id"
  defp target_key(%ProductVariant{}), do: "variant_id"

  defp adjust_stock(%Product{id: id}, delta) do
    from(p in Product, where: p.id == ^id)
    |> Repo.update_all(inc: [stock_quantity: delta])
  end

  defp adjust_stock(%ProductVariant{id: id}, delta) do
    from(v in ProductVariant, where: v.id == ^id)
    |> Repo.update_all(inc: [stock_quantity: delta])
  end

  @doc """
  Lists movements for a product or variant (`%{product_id: id}` or
  `%{variant_id: id}`), newest first, paginated.
  """
  def list_movements(%Scope{business: business}, target, params \\ %{}) do
    page = max(to_integer(params[:page] || params["page"], 1), 1)
    page_size = min(to_integer(params[:page_size] || params["page_size"], 25), 100)

    base_query =
      InventoryTransaction
      |> where([t], t.business_id == ^business.id)
      |> filter_target(target)

    total_count = base_query |> select(count()) |> Repo.one()

    transactions =
      base_query
      |> order_by([t], desc: t.occurred_at)
      |> limit(^page_size)
      |> offset(^((page - 1) * page_size))
      |> preload(:performed_by)
      |> Repo.all()

    %{data: transactions, page: page, page_size: page_size, total_count: total_count}
  end

  defp filter_target(query, %{product_id: id}), do: where(query, [t], t.product_id == ^id)
  defp filter_target(query, %{variant_id: id}), do: where(query, [t], t.variant_id == ^id)

  defp to_integer(nil, default), do: default

  defp to_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> default
    end
  end

  defp to_integer(value, _default) when is_integer(value), do: value
end
