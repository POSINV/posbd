defmodule Posbd.AuditLogs do
  @moduledoc """
  Append-only audit trail (AGENTS.md §26). `record/5` is called from other
  contexts right after a business-significant mutation succeeds -
  product created, price changed, stock adjusted, bill created/cancelled,
  settings changed, bulk import performed. It never raises into the
  caller, so a logging hiccup can never roll back or fail the operation
  it is describing.
  """

  import Ecto.Query, warn: false

  alias Posbd.Repo
  alias Posbd.Accounts.Scope
  alias Posbd.AuditLogs.AuditLog

  @default_page_size 25

  @doc """
  Records `action` (e.g. `"product.price_changed"`) against `entity_type`
  (e.g. `"Product"`) + `entity_id`, with optional `metadata` describing the
  relevant change. Never pass secrets (passwords, tokens) in `metadata`.
  """
  def record(
        %Scope{business: business, user: user},
        action,
        entity_type,
        entity_id,
        metadata \\ %{}
      ) do
    %AuditLog{}
    |> AuditLog.changeset(%{
      business_id: business.id,
      user_id: user && user.id,
      action: action,
      entity_type: entity_type,
      entity_id: entity_id,
      metadata: metadata
    })
    |> Repo.insert()
  end

  @doc """
  Lists audit log entries for the scope's business, newest first. Accepts
  optional `action`, `entity_type`, `from`/`to` (ISO-8601 date strings) filters
  and `page`/`page_size` pagination (AGENTS.md §29).
  """
  def list(%Scope{business: business}, params \\ %{}) do
    page = max(to_integer(params[:page] || params["page"], 1), 1)

    page_size =
      min(to_integer(params[:page_size] || params["page_size"], @default_page_size), 100)

    base_query =
      from(l in AuditLog, where: l.business_id == ^business.id)
      |> maybe_filter_action(params[:action] || params["action"])
      |> maybe_filter_entity_type(params[:entity_type] || params["entity_type"])
      |> maybe_filter_from(params[:from] || params["from"])
      |> maybe_filter_to(params[:to] || params["to"])

    total_count = base_query |> select(count()) |> Repo.one()

    logs =
      base_query
      |> order_by([l], desc: l.inserted_at)
      |> limit(^page_size)
      |> offset(^((page - 1) * page_size))
      |> preload(:user)
      |> Repo.all()

    %{data: logs, page: page, page_size: page_size, total_count: total_count}
  end

  defp maybe_filter_action(query, nil), do: query
  defp maybe_filter_action(query, ""), do: query
  defp maybe_filter_action(query, action), do: from(l in query, where: l.action == ^action)

  defp maybe_filter_entity_type(query, nil), do: query
  defp maybe_filter_entity_type(query, ""), do: query

  defp maybe_filter_entity_type(query, type),
    do: from(l in query, where: l.entity_type == ^type)

  defp maybe_filter_from(query, nil), do: query
  defp maybe_filter_from(query, ""), do: query

  defp maybe_filter_from(query, date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} ->
        from(l in query, where: l.inserted_at >= ^DateTime.new!(date, ~T[00:00:00]))

      :error ->
        query
    end
  end

  defp maybe_filter_to(query, nil), do: query
  defp maybe_filter_to(query, ""), do: query

  defp maybe_filter_to(query, date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} ->
        from(l in query, where: l.inserted_at <= ^DateTime.new!(date, ~T[23:59:59]))

      :error ->
        query
    end
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
