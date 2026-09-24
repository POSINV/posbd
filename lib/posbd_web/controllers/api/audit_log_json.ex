defmodule PosbdWeb.Api.AuditLogJSON do
  alias Posbd.AuditLogs.AuditLog

  def index(%{data: logs, page: page, page_size: page_size, total_count: total_count}) do
    %{
      data: Enum.map(logs, &log_json/1),
      pagination: %{page: page, page_size: page_size, total_count: total_count}
    }
  end

  defp log_json(%AuditLog{} = log) do
    %{
      id: log.id,
      action: log.action,
      entity_type: log.entity_type,
      entity_id: log.entity_id,
      metadata: log.metadata,
      user:
        case log.user do
          %Posbd.Accounts.User{} = user -> %{id: user.id, full_name: user.full_name}
          _ -> nil
        end,
      inserted_at: log.inserted_at
    }
  end
end
