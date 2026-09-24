defmodule PosbdWeb.Api.ImportJSON do
  alias Posbd.Imports.ImportLog

  def preview(%{total: total, valid: valid, invalid: invalid, rows: rows}) do
    %{
      data: %{
        total: total,
        valid: valid,
        invalid: invalid,
        rows: Enum.map(rows, &row_json/1)
      }
    }
  end

  def commit(%{created: created, failed: failed}) do
    %{
      data: %{
        created: created,
        failed_count: length(failed),
        failed: Enum.map(failed, fn f -> %{row_number: f.row_number, errors: f.errors} end)
      }
    }
  end

  def history(%{logs: logs}) do
    %{data: Enum.map(logs, &log_json/1)}
  end

  defp row_json(row) do
    %{
      row_number: row.row_number,
      fields: row.fields,
      valid: row.valid,
      errors: row.errors
    }
  end

  defp log_json(%ImportLog{} = log) do
    %{
      id: log.id,
      import_type: log.import_type,
      total_rows: log.total_rows,
      success_count: log.success_count,
      error_count: log.error_count,
      inserted_at: log.inserted_at
    }
  end
end
